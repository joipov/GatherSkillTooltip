local _, ns = ...

-- Learning from play: which corpses were fully looted (for negative skinning
-- evidence), unknown nodes read from a gather's loot window, and whether a
-- gather cast produced a skill-up (for node colors).

local C_Timer = C_Timer
local GetTime = GetTime
local UnitExists = UnitExists
local UnitIsPlayer = UnitIsPlayer
local UnitIsDead = UnitIsDead
local UnitLevel = UnitLevel
local UnitGUID = UnitGUID
local GetNumLootItems = GetNumLootItems
local GetLootSlotLink = GetLootSlotLink
local GetLootSourceInfo = GetLootSourceInfo
local UnitNameFromGUID = UnitNameFromGUID
local C_Item = C_Item

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

-- on Classic-rules clients the "Skinnable" tooltip line appears only
-- after a corpse has been emptied. A missing line is therefore treated as
-- "cannot be skinned" only for corpses this client has fully looted.
local lootedCorpses = {}
local LOOTED_CORPSE_SECONDS = 600
local pendingLootGuid
local pendingLootSlots = 0

local LOOT_EVENTS = { "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED", "LOOT_READY" }

-- Item class/subclass ids used to recognise a gathering node's loot. Ore can
-- also arrive with gems; any other item means the source was not a plain node.
local ITEM_CLASS_TRADE_GOODS = 7
local ITEM_CLASS_GEM = 3
local ITEM_SUBCLASS_HERB = 9
local ITEM_SUBCLASS_METAL_AND_STONE = 7

local pendingLoot
local LOOT_LEARN_SECONDS = 3

local function LootItemKind(class, subclass)
	if class == ITEM_CLASS_TRADE_GOODS then
		if subclass == ITEM_SUBCLASS_HERB then
			return "herb"
		elseif subclass == ITEM_SUBCLASS_METAL_AND_STONE then
			return "mine"
		end
	elseif class == ITEM_CLASS_GEM then
		return "gem"
	end
	return nil
end

-- "herb" or "mine" when every item belongs to one gathering profession, nil
-- for anything else. `items` is a list of { class, subclass } pairs.
function ns.LootKind(items)
	if type(items) ~= "table" then
		return nil
	end
	local kind
	for i = 1, #items do
		local item = items[i]
		local this = type(item) == "table" and LootItemKind(item[1], item[2])
		-- Ore nodes often carry a gem; it does not change the source kind.
		if this ~= "gem" then
			if not this then
				return nil
			end
			if kind and kind ~= this then
				return nil
			end
			kind = this
		end
	end
	return kind
end

-- Reads the open loot window's class/subclass pairs. nil means the window is
-- not readable yet, so a later loot event may still learn from it.
local function LootItems()
	if type(GetLootSlotLink) ~= "function" or type(GetNumLootItems) ~= "function" then
		return nil
	end
	if not C_Item or type(C_Item.GetItemInfoInstant) ~= "function" then
		return nil
	end
	local count = GetNumLootItems()
	if SecretBlocked(count) or type(count) ~= "number" or count < 1 then
		return nil
	end
	local items = {}
	for slot = 1, count do
		local link = GetLootSlotLink(slot)
		if SecretBlocked(link) or type(link) ~= "string" or link == "" then
			return nil
		end
		local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(link)
		if SecretBlocked(class) or SecretBlocked(subclass) then
			return nil
		end
		if type(class) ~= "number" or type(subclass) ~= "number" then
			return nil
		end
		items[#items + 1] = { class, subclass }
	end
	return items
end

local function LootSourceGuid()
	if type(GetLootSourceInfo) ~= "function" then
		return nil
	end
	local guid = GetLootSourceInfo(1)
	if SecretBlocked(guid) or type(guid) ~= "string" or guid == "" then
		return nil
	end
	if guid:sub(1, 11) ~= "GameObject-" then
		return nil
	end
	return guid
end

local function LootSourceName(guid)
	if type(UnitNameFromGUID) ~= "function" then
		return nil
	end
	local name = UnitNameFromGUID(guid)
	if SecretBlocked(name) or type(name) ~= "string" or name == "" then
		return nil
	end
	local unknown = _G.UNKNOWNOBJECT
	if type(unknown) == "string" and name == unknown then
		return nil
	end
	return name
end

local function DeadUnitGUID(unit)
	local dead = UnitIsDead(unit)
	if SecretBlocked(dead) or not dead then
		return nil
	end
	return ReadableString(UnitGUID(unit))
end

-- A gather cast can succeed without a readable tooltip name. The loot window
-- still identifies the source object and the profession of its contents, so
-- an unknown herb/ore can be learned from there. The record only exists for
-- LOOT_LEARN_SECONDS after a successful gather cast, which keeps the skill
-- value from before any skill-up and stops a later, unrelated loot from being
-- attributed to the gather.
function ns.LearnFromLoot()
	local pending = pendingLoot
	if not pending then
		return
	end
	local db = ns.db
	if not db or not db.enabled then
		pendingLoot = nil
		return
	end
	if GetTime() - pending.at > LOOT_LEARN_SECONDS then
		pendingLoot = nil
		return
	end
	local items = LootItems()
	if not items then
		-- The window can still be filling; the next loot event tries again.
		return
	end
	local kind = ns.LootKind(items)
	if kind ~= pending.prof then
		pendingLoot = nil
		return
	end
	local guid = LootSourceGuid()
	if not guid then
		-- The source can be readable on the other loot event only.
		return
	end
	local name = LootSourceName(guid) or pending.name
	name = name and ns.NormalizeName(name)
	pendingLoot = nil
	if not name or name == "" then
		return
	end
	if ns.LearnCustomNode(name, pending.prof, pending.skill) then
		ns.Debug("learned from loot", name, pending.prof, pending.skill)
		if ns.ForgetUnknownName then
			ns.ForgetUnknownName()
		end
	end
end

function ns.OnLootReady()
	ns.LearnFromLoot()
end

function ns.OnLootOpened()
	ns.LearnFromLoot()
	-- The corpse being looted is under the cursor (right-click) or targeted.
	-- debug which GUID won so a session can decide whether the target
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
	pendingLoot = nil
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

-- Loot events serve both skinning (corpse evidence) and herb/ore learning.
function ns.UpdateLootEvents()
	local db = ns.db
	local active = (db and db.enabled and (db.skinning or db.herbalism or db.mining)) and true or false
	if active == lootEventsActive then
		return
	end
	lootEventsActive = active
	ns.SetEventsRegistered(LOOT_EVENTS, active)
	if not active then
		pendingLootGuid = nil
		pendingLoot = nil
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

-- UNIT_SPELLCAST_SENT carries the target name just before the cast starts.
-- It is the fallback name for a node whose tooltip was not readable. A later
-- non-gathering cast overwrites it, so a stale name cannot travel far.
local castTargetName
local castTargetTime = 0
local CAST_TARGET_SECONDS = 2

function ns.NoteCastTarget(name)
	name = ReadableString(name)
	if not name then
		castTargetName = nil
		castTargetTime = 0
		return
	end
	castTargetName = name
	castTargetTime = GetTime()
end

local function RecentCastTarget()
	if not castTargetName then
		return nil
	end
	if GetTime() - castTargetTime > CAST_TARGET_SECONDS then
		castTargetName = nil
		castTargetTime = 0
		return nil
	end
	return castTargetName
end

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
-- (ns.NODE_BY_KEY).
local function GatherSubject(key)
	local level = type(key) == "string" and key:match("^skin:(%d+)$")
	if level then
		return ns.L.LEARNED_LEVEL:format(level), ns.SkinningBand(tonumber(level))
	end
	local node = ns.NODE_BY_KEY[key]
	if not node then
		return nil
	end
	local display = ns.NODE_DISPLAY and ns.NODE_DISPLAY[key]
	return display or key, node
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

-- A remembered node is only usable while that same object is still on the
-- tooltip. A stale minimap pin or an earlier hover must not lend its name to a
-- gather on a different node: that is how a Kingsblood gain could be recorded
-- as a Khadgar's Whisker gain and lower the wrong requirement.
local function KnownNodeAtCast(key)
	if type(key) ~= "string" or key == "" then
		return nil
	end
	if ns.TooltipShowsNode(_G.GameTooltip, key) then
		return key
	end
	return nil
end

-- A remembered unknown name is only usable while that same object is still on
-- the tooltip. Without this, a name hovered earlier (a player on the minimap,
-- a campfire, any other object) could be learned as the node of a later cast
-- whose own untyped tooltip did not replace the memory.
local function UnknownNameAtCast()
	local name = ns.RecentUnknownName and ns.RecentUnknownName()
	if not name then
		return nil
	end
	if not ns.TooltipShowsName(_G.GameTooltip, name) then
		if ns.ForgetUnknownName then
			ns.ForgetUnknownName()
		end
		return nil
	end
	return name
end

-- UNIT_SPELLCAST_START: arm a watch for a gathering spell. The node key and,
-- when there is no known node, the unmatched object name or the cast target
-- are snapshotted here. Success does not read the tooltip again.
function ns.OnGatherCastStart(spellID)
	local prof = ns.ProfessionForGatherSpell(spellID)
	if not prof or not ns.db or not ns.db.enabled then
		return
	end
	ns.RefreshSkills()
	local key
	local unknownName
	local targetName
	if prof == "herb" or prof == "mine" then
		key = GatherKey(prof)
		if key then
			key = KnownNodeAtCast(key)
		end
		if not key then
			unknownName = UnknownNameAtCast()
			if not unknownName then
				targetName = RecentCastTarget()
			end
		end
	else
		key = GatherKey(prof)
	end
	local skills = ns.skills
	local skill = skills[prof]
	local base = skills[prof .. "Base"]
	local maxSkill = skills[prof .. "Max"]
	CancelGatherWatch()
	pendingLoot = nil
	if type(skill) ~= "number" or type(base) ~= "number" then
		return
	end
	if not key and not unknownName and not targetName
		and prof ~= "herb" and prof ~= "mine" then
		return
	end
	gatherWatch = {
		prof = prof,
		key = key,
		unknownName = unknownName,
		targetName = targetName,
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
-- herb/ore is learned from the name snapshotted at cast start, using that
-- pre-cast skill; with no name at all, the loot window gets a short chance.
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
		if not watch.unknownName and (watch.prof == "herb" or watch.prof == "mine") then
			pendingLoot = {
				prof = watch.prof,
				skill = watch.skill,
				name = watch.targetName or RecentCastTarget(),
				at = GetTime(),
			}
		end
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
