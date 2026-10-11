local _, ns = ...

-- Learning from play: which corpses were fully looted (for negative skinning
-- evidence) and whether a gather cast produced a skill-up (for node colors).

local C_Timer = C_Timer
local GetTime = GetTime
local UnitExists = UnitExists
local UnitIsPlayer = UnitIsPlayer
local UnitIsDead = UnitIsDead
local UnitLevel = UnitLevel
local UnitGUID = UnitGUID
local GetNumLootItems = GetNumLootItems

local SecretBlocked = ns.SecretBlocked
local ReadableString = ns.ReadableString
local CanIndex = ns.CanIndex
local COLOR_PREFIX = ns.COLOR_PREFIX

-- Chat line for learned data; only when the learnChat option is on.
function ns.LearnChat(text)
	local db = ns.db
	if not db or not db.enabled or not db.learnChat or type(text) ~= "string" or text == "" then
		return
	end
	ns.Print(text)
end

-- Loot tracking -----------------------------------------------------------------

-- CQ-002: on Classic-rules clients the "Skinnable" tooltip line appears only
-- after a corpse has been emptied. A missing line is therefore treated as
-- "cannot be skinned" only for corpses this client has fully looted.
local lootedCorpses = {}
local LOOTED_CORPSE_SECONDS = 600
local pendingLootGuid
local pendingLootSlots = 0

local LOOT_EVENTS = { "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED" }

local function DeadUnitGUID(unit)
	local dead = UnitIsDead(unit)
	if SecretBlocked(dead) or not dead then
		return nil
	end
	return ReadableString(UnitGUID(unit))
end

function ns.OnLootOpened()
	-- The corpse being looted is under the cursor (right-click) or targeted.
	-- CQ-103: debug which GUID won so a session can decide whether the target
	-- fallback is safe. The fallback itself stays until that session.
	local mouseGuid = DeadUnitGUID("mouseover")
	local targetGuid = DeadUnitGUID("target")
	pendingLootGuid = mouseGuid or targetGuid
	local slots = GetNumLootItems()
	pendingLootSlots = type(slots) == "number" and slots or 0
	ns.Debug(
		"loot opened",
		"mouseover", mouseGuid or "nil",
		"target", targetGuid or "nil",
		"slots", pendingLootSlots
	)
end

function ns.OnLootSlotCleared()
	if pendingLootSlots > 0 then
		pendingLootSlots = pendingLootSlots - 1
	end
end

function ns.OnLootClosed()
	local guid = pendingLootGuid
	pendingLootGuid = nil
	if not guid or pendingLootSlots > 0 then
		return
	end
	local now = GetTime()
	for old, seen in pairs(lootedCorpses) do
		if now - seen > LOOTED_CORPSE_SECONDS then
			lootedCorpses[old] = nil
		end
	end
	lootedCorpses[guid] = now
end

local lootEventsActive = false

-- Loot events are only registered while skinning learning can run (ARCH-002).
function ns.UpdateLootEvents()
	local db = ns.db
	local active = (db and db.enabled and db.skinning) and true or false
	if active == lootEventsActive then
		return
	end
	lootEventsActive = active
	ns.SetEventsRegistered(LOOT_EVENTS, active)
	if not active then
		pendingLootGuid = nil
	end
end

function ns.CorpseLooted(unit, data)
	local guid = ReadableString(UnitGUID(unit))
	if not guid and data and CanIndex(data) then
		guid = ReadableString(data.guid)
	end
	return guid ~= nil and lootedCorpses[guid] ~= nil
end

-- Gather watch -------------------------------------------------------------------

-- A cast is armed at UNIT_SPELLCAST_START and becomes pending when it
-- succeeds; a skill-up within GATHER_WATCH_SECONDS counts as a gain,
-- otherwise the timer records a miss.
local gatherWatch
local GATHER_WATCH_SECONDS = 1

local function ColorWord(prefix)
	local L = ns.L
	if prefix == COLOR_PREFIX.red then
		return L.COLOR_RED
	elseif prefix == COLOR_PREFIX.orange then
		return L.COLOR_ORANGE
	elseif prefix == COLOR_PREFIX.yellow then
		return L.COLOR_YELLOW
	elseif prefix == COLOR_PREFIX.green then
		return L.COLOR_GREEN
	elseif prefix == COLOR_PREFIX.grey then
		return L.COLOR_GREY
	end
	return nil
end

-- Display name and band for a learned-data key: "skin:N" or a node key
-- (ns.NODE_BY_KEY, ARCH-004).
local function GatherSubject(key)
	local level = type(key) == "string" and key:match("^skin:(%d+)$")
	if level then
		return ns.L.LEARNED_LEVEL:format(level), ns.SkinningBand(tonumber(level))
	end
	local node = ns.NODE_BY_KEY[key]
	if not node then
		return nil
	end
	return key, node
end

-- Records the result and announces a color change when learnChat is on.
local function ReportGatherLearn(key, skill, gained)
	local name, band = GatherSubject(key)
	local before = name and ns.ObservedColor(skill, band, ns.EffectiveOrange(band, key), key)
	ns.NoteGatherResult(key, skill, gained)
	if not name then
		return
	end
	local after = ns.ObservedColor(skill, band, ns.EffectiveOrange(band, key), key)
	if before == after then
		return
	end
	local word = ColorWord(after)
	if not word then
		return
	end
	ns.LearnChat(ns.L.LEARNED_COLOR:format(name, word, skill))
end

local function FinishGatherWatch(entry, gained)
	if gatherWatch ~= entry or not entry.pending then
		return
	end
	gatherWatch = nil
	if entry.timer then
		entry.timer:Cancel()
		entry.timer = nil
	end
	if not gained and type(entry.maxSkill) == "number" and entry.base >= entry.maxSkill then
		return
	end
	ReportGatherLearn(entry.key, entry.skill, gained)
end

local function OnGatherWatchTimer()
	if gatherWatch then
		FinishGatherWatch(gatherWatch, false)
	end
end

local function DeadCreatureLevel(unit)
	if not UnitExists(unit) then
		return nil
	end
	local player = UnitIsPlayer(unit)
	if SecretBlocked(player) or player then
		return nil
	end
	local dead = UnitIsDead(unit)
	if SecretBlocked(dead) or not dead then
		return nil
	end
	local level = UnitLevel(unit)
	if SecretBlocked(level) or type(level) ~= "number" or level < 1 then
		return nil
	end
	return math.floor(level)
end

local function GatherKey(prof)
	if prof == "skin" then
		local level = DeadCreatureLevel("target") or DeadCreatureLevel("mouseover") or ns.LastSkinLevel()
		if not level then
			return nil
		end
		return "skin:" .. level
	end
	return ns.RecentNodeKey(prof)
end

local function CancelGatherWatch()
	if gatherWatch and gatherWatch.timer then
		gatherWatch.timer:Cancel()
	end
	gatherWatch = nil
end

-- UNIT_SPELLCAST_START: arm a watch for a gathering spell. The node key and,
-- when there is no known node, the unmatched object name are snapshotted here
-- (CQ-101). Success does not read the tooltip again.
function ns.OnGatherCastStart(spellID)
	local prof = ns.ProfessionForGatherSpell(spellID)
	if not prof or not ns.db or not ns.db.enabled then
		return
	end
	ns.RefreshSkills()
	local key = GatherKey(prof)
	local unknownName = nil
	if not key and (prof == "herb" or prof == "mine") and ns.RecentUnknownName then
		unknownName = ns.RecentUnknownName()
	end
	local skills = ns.skills
	local skill = skills[prof]
	local base = skills[prof .. "Base"]
	local maxSkill = skills[prof .. "Max"]
	CancelGatherWatch()
	if type(skill) ~= "number" or type(base) ~= "number" then
		return
	end
	if not key and (type(unknownName) ~= "string" or unknownName == "") then
		return
	end
	gatherWatch = {
		prof = prof,
		key = key,
		unknownName = unknownName,
		skill = skill,
		base = base,
		maxSkill = maxSkill,
		spell = spellID,
		pending = false,
	}
end

-- UNIT_SPELLCAST_INTERRUPTED / _FAILED: drop an armed (not yet pending) watch.
function ns.OnGatherCastStop(spellID)
	if SecretBlocked(spellID) then
		return
	end
	if gatherWatch and gatherWatch.spell == spellID and not gatherWatch.pending then
		CancelGatherWatch()
	end
end

-- UNIT_SPELLCAST_SUCCEEDED: a known-node watch becomes pending and a miss is
-- recorded unless a skill-up arrives within GATHER_WATCH_SECONDS. An unknown
-- herb/ore is learned only from the name snapshotted at cast start, using
-- that pre-cast skill (CQ-101, CQ-105).
function ns.OnGatherCastSucceeded(spellID)
	if SecretBlocked(spellID) then
		return
	end
	local watch = gatherWatch
	if not watch or watch.spell ~= spellID or watch.pending then
		return
	end
	if type(watch.unknownName) == "string" and watch.unknownName ~= "" then
		if ns.LearnCustomNode(watch.unknownName, watch.prof, watch.skill) and ns.ForgetUnknownName then
			ns.ForgetUnknownName()
		end
	end
	if not watch.key then
		gatherWatch = nil
		return
	end
	watch.pending = true
	watch.timer = C_Timer.NewTimer(GATHER_WATCH_SECONDS, OnGatherWatchTimer)
end

-- SKILL_LINES_CHANGED / CHAT_MSG_SKILL: returns true when the pending watch
-- was resolved as a gain (skills were refreshed on the way).
function ns.NoteGatherSkill()
	if not gatherWatch or not gatherWatch.pending then
		return false
	end
	ns.RefreshSkills()
	local base = ns.skills[gatherWatch.prof .. "Base"]
	if type(base) == "number" and base > gatherWatch.base then
		FinishGatherWatch(gatherWatch, true)
		return true
	end
	return false
end
