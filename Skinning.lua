local _, ns = ...

-- Unit tooltips: append the skinning skill beside the level of a creature the
-- player can skin, and learn which NPC ids are skinnable from "Skinnable"
-- lines on looted corpses.

local UnitIsPlayer = UnitIsPlayer
local UnitPlayerControlled = UnitPlayerControlled
local UnitCreatureType = UnitCreatureType
local UnitIsDead = UnitIsDead
local UnitCanAttack = UnitCanAttack
local UnitLevel = UnitLevel
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitTokenFromGUID = UnitTokenFromGUID
local UnitIsTapDenied = UnitIsTapDenied

local SecretBlocked = ns.SecretBlocked
local ReadableString = ns.ReadableString
local CanIndex = ns.CanIndex

-- Level of the last creature we decorated; the gather watch falls back to it
-- when neither target nor mouseover is a dead creature any more.
local lastSkinLevel

function ns.LastSkinLevel()
	return lastSkinLevel
end

local function SkinLabel()
	local label = ns.ProfessionName(ns.SKIN_SKILL_LINE, ns.L.SKINNING)
	if type(label) ~= "string" or label == "" or SecretBlocked(label) then
		return ns.L.SKINNING
	end
	return label
end

local function SkillSuffix(skill, required)
	local db = ns.db
	local label = SkinLabel()
	if db.showCurrent and db.showRequired then
		return " (" .. label .. " " .. skill .. "/" .. required .. ")"
	elseif db.showCurrent then
		return " (" .. label .. " " .. skill .. ")"
	elseif db.showRequired then
		return " (" .. label .. " " .. required .. ")"
	end
	return nil
end

local function UsableLevel(level)
	if SecretBlocked(level) or type(level) ~= "number" or level < 1 then
		return nil
	end
	return math.floor(level)
end

-- Finds the tooltip line carrying the creature level: the line whose first
-- number equals `level`, or (when the level is unknown) the first line with
-- any number. Returns fontString, rawText, textWithoutOurSuffix, parsedLevel.
local function LevelLine(tooltip, level)
	local count = tooltip:NumLines()
	if SecretBlocked(count) or type(count) ~= "number" or count < 2 then
		return nil
	end
	local last = count < 4 and count or 4
	local fallbackFs, fallbackRaw, fallbackBase, fallbackLevel
	for i = 2, last do
		local fs = ns.FontStringByIndex(tooltip, i)
		local raw = fs and ReadableString(fs:GetText())
		if raw then
			local base = ns.StripSkillSuffix(raw)
			local found = ns.FirstNumber(base)
			if found then
				if level and found == level then
					return fs, raw, base
				end
				if not fallbackFs then
					fallbackFs, fallbackRaw, fallbackBase, fallbackLevel = fs, raw, base, found
				end
			end
		end
	end
	if level then
		return nil
	end
	return fallbackFs, fallbackRaw, fallbackBase, fallbackLevel
end

function ns.NpcIdFromGUID(guid)
	guid = ReadableString(guid)
	if not guid then
		return nil
	end
	local id = guid:match("^Creature%-.-%-(%d+)%-%x+$")
	if not id then
		return nil
	end
	return tonumber(id)
end

local function UnitNpcID(unit, data)
	local id = ns.NpcIdFromGUID(UnitGUID(unit))
	if id then
		return id
	end
	if data and CanIndex(data) then
		return ns.NpcIdFromGUID(data.guid)
	end
	return nil
end

-- Unknown NPCs fall back to creature type: numeric id first (locale
-- independent), localized name second (COMPAT-003). In debug mode a
-- disagreement between the two is printed so the id table can be confirmed.
local function SkinnableCreatureType(unit)
	local kind, kindID = UnitCreatureType(unit)
	local byID = false
	if type(kindID) == "number" and not SecretBlocked(kindID) then
		byID = ns.SKIN_TYPE_IDS[kindID] == true
	end
	local name = ReadableString(kind)
	local byName = name ~= nil and ns.SKIN_TYPES[name] == true
	if name and byID ~= byName then
		ns.Debug("creature type mismatch", name, tostring(kindID), "id:", tostring(byID), "name:", tostring(byName))
	end
	return byID or byName
end

local function CanSkinUnit(unit, dead, npcID)
	local player = UnitIsPlayer(unit)
	if SecretBlocked(player) or player then
		return false
	end
	local controlled = UnitPlayerControlled(unit)
	if SecretBlocked(controlled) or controlled then
		return false
	end
	local known = npcID and ns.db.skinIds[npcID]
	if known == false then
		return false
	end
	if known ~= true and not SkinnableCreatureType(unit) then
		return false
	end
	if not dead then
		local canAttack = UnitCanAttack("player", unit)
		if SecretBlocked(canAttack) or not canAttack then
			return false
		end
	end
	return true
end

-- Skinning skill at which a creature of `level` turns orange.
function ns.SkinningOrange(level)
	if level <= 10 then
		return 1
	elseif level <= 20 then
		return (level * 10) - 100
	end
	return level * 5
end

local function UnitFromTooltip(tooltip, data)
	local _, unit = tooltip:GetUnit()
	if type(unit) == "string" and not SecretBlocked(unit) then
		return unit
	end
	if not data then
		return nil
	end
	local guid = data.guid
	if type(guid) ~= "string" or SecretBlocked(guid) then
		return nil
	end
	return UnitTokenFromGUID(guid)
end

local function TextHasSkinnable(text)
	text = ReadableString(text)
	local word = ns.SKINNABLE_TEXT
	if not text or type(word) ~= "string" or word == "" then
		return false
	end
	return text:find(word, 1, true) ~= nil
end

-- Prefers the tooltip data lines (the source the tooltip is rendered from);
-- the font-string scan is only the fallback when the data is inaccessible
-- (PERF-002: one scan per hover, not two).
local function TooltipHasSkinnable(tooltip, data)
	if data and CanIndex(data) and CanIndex(data.lines) then
		local lines = data.lines
		for i = 1, #lines do
			local line = lines[i]
			if CanIndex(line) and (TextHasSkinnable(line.leftText) or TextHasSkinnable(line.rightText)) then
				return true
			end
		end
		return false
	end
	local count = tooltip:NumLines()
	if SecretBlocked(count) or type(count) ~= "number" then
		return false
	end
	for i = 1, count do
		local left = ns.FontStringByIndex(tooltip, i)
		if left and TextHasSkinnable(left:GetText()) then
			return true
		end
		local right = ns.RightFontStringByIndex(tooltip, i)
		if right and TextHasSkinnable(right:GetText()) then
			return true
		end
	end
	return false
end

local function CorpseIsOurs(unit)
	local denied = UnitIsTapDenied(unit)
	if SecretBlocked(denied) then
		return false
	end
	return not denied
end

local function LearnSkin(tooltip, data, unit, dead, npcID)
	local db = ns.db
	if not dead or not npcID then
		return
	end
	local previous = db.skinIds[npcID]
	local name = ReadableString(UnitName(unit)) or tostring(npcID)
	if TooltipHasSkinnable(tooltip, data) then
		if previous ~= true then
			db.skinIds[npcID] = true
			ns.LearnChat(ns.L.LEARNED_SKIN_YES:format(name))
		end
		return
	end
	if previous ~= nil then
		return
	end
	-- Negative evidence is only trusted for our own, fully looted corpse (CQ-002).
	if CorpseIsOurs(unit) and ns.CorpseLooted(unit, data) then
		db.skinIds[npcID] = false
		ns.LearnChat(ns.L.LEARNED_SKIN_NO:format(name))
	end
end

-- Static skinning bands, one table per creature level, created on first use
-- and reused on every later hover (PERF-004). `key` is the learned-data key.
local SKIN_BANDS = {}

function ns.SkinningBand(level)
	local band = SKIN_BANDS[level]
	if not band then
		local orange = ns.SkinningOrange(level)
		band = {
			orange = orange,
			yellow = orange + 25,
			green = orange + 50,
			grey = orange + 100,
			prof = "skin",
			key = "skin:" .. level,
		}
		SKIN_BANDS[level] = band
	end
	return band
end

local function ApplySkinningLine(tooltip, unit, dead, npcID)
	local db = ns.db
	if not db.skinning then
		return
	end
	ns.EnsureSkills()
	local skills = ns.skills
	if type(skills.skin) ~= "number" then
		return
	end
	if not CanSkinUnit(unit, dead, npcID) then
		return
	end
	local level = UsableLevel(UnitLevel(unit))
	local fs, raw, base, parsed = LevelLine(tooltip, level)
	if not level then
		level = UsableLevel(parsed)
	end
	if not fs or not raw or not base or not level then
		return
	end
	lastSkinLevel = level
	local band = ns.SkinningBand(level)
	local orange = ns.EffectiveOrange(band, band.key)
	local suffix = SkillSuffix(skills.skin, orange)
	if not suffix then
		return
	end
	local first, last = base:find("%f[%d]" .. level .. "%f[%D]")
	if not first then
		return
	end
	local colored = suffix
	if db.color then
		colored = ns.ColorWrap(suffix, ns.ObservedColor(skills.skin, band, orange, band.key))
	end
	local display = base:sub(1, last) .. colored .. base:sub(last + 1)
	if raw == display then
		return
	end
	fs:SetText(display)
end

-- Unit and Corpse tooltips: resolve unit token, death state and NPC id once
-- per hover and hand them to both consumers (PERF-002).
function ns.OnUnitTooltip(tooltip, data)
	local db = ns.db
	if not db or not db.enabled or not tooltip then
		return
	end
	local unit = UnitFromTooltip(tooltip, data)
	if not unit then
		return
	end
	local dead = UnitIsDead(unit)
	if SecretBlocked(dead) then
		return
	end
	dead = dead and true or false
	local npcID = UnitNpcID(unit, data)
	LearnSkin(tooltip, data, unit, dead, npcID)
	ApplySkinningLine(tooltip, unit, dead, npcID)
end
