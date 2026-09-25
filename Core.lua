local ADDON_NAME, ns = ...

ns.TITLE = "GatherSkillTooltip"

local issecretvalue = issecretvalue
local canaccessvalue = canaccessvalue
local issecrettable = issecrettable
local canaccesstable = canaccesstable
local C_Timer = C_Timer
local C_Minimap = C_Minimap
local GetTime = GetTime
local UnitIsPlayer = UnitIsPlayer
local UnitPlayerControlled = UnitPlayerControlled
local UnitCreatureType = UnitCreatureType
local UnitIsDead = UnitIsDead
local UnitCanAttack = UnitCanAttack
local UnitLevel = UnitLevel
local UnitGUID = UnitGUID
local UnitTokenFromGUID = UnitTokenFromGUID
local UnitIsTapDenied = UnitIsTapDenied
local GetNumLootItems = GetNumLootItems
local UnitIsTapped = UnitIsTapped
local UnitIsTappedByPlayer = UnitIsTappedByPlayer

local defaults = {
	enabled = true,
	herbalism = true,
	mining = true,
	skinning = true,
	showCurrent = true,
	showRequired = true,
	color = true,
	learnChat = false,
	warnTracking = true,
	warnTrain = true,
	showMinimapButton = false,
	minimapAngle = 200,
	debug = false,
}

ns.skills = {
	herb = nil,
	mine = nil,
	skin = nil,
	herbBase = nil,
	mineBase = nil,
	skinBase = nil,
	herbMax = nil,
	mineMax = nil,
	skinMax = nil,
}

local COLORS = {
	red = { 1.00, 0.10, 0.10 },
	orange = { 1.00, 0.50, 0.25 },
	yellow = { 1.00, 1.00, 0.00 },
	green = { 0.25, 0.75, 0.25 },
	grey = { 0.50, 0.50, 0.50 },
}

local function ColorPrefix(color)
	return string.format(
		"|cff%02x%02x%02x",
		math.floor(color[1] * 255 + 0.5),
		math.floor(color[2] * 255 + 0.5),
		math.floor(color[3] * 255 + 0.5)
	)
end

local COLOR_PREFIX = {
	red = ColorPrefix(COLORS.red),
	orange = ColorPrefix(COLORS.orange),
	yellow = ColorPrefix(COLORS.yellow),
	green = ColorPrefix(COLORS.green),
	grey = ColorPrefix(COLORS.grey),
}

local eventFrame = CreateFrame("Frame")
local warningFrame
local warningText
local trackingTimer
local lastWarningKey
local warningElapsed = 0
local WARNING_POLL_INTERVAL = 1.0
local minimapBtn
local ldbIcon
local minimapDragging
local lastDebugText
local skillsRefreshed
local lastNodeKey
local lastNodeProf
local lastNodeTime = 0
local lastSkinLevel
local gatherWatch
local MISS_GREY = 20
local RATE_TRIES = 4
local GATHER_WATCH_SECONDS = 1
-- A hovered node is only attributed to a gather cast that starts within this
-- window (CQ-001). Hovering an unknown object or an ambiguous pin stack clears it.
local NODE_KEY_SECONDS = 15

-- Bump when a one-time SavedVariables migration is added to MigrateDB.
local DB_VERSION = 2

-- Applies defaults and resets any option whose type no longer matches its
-- default (all options are booleans or numbers), so a corrupted or hand-edited
-- SavedVariables file recovers instead of erroring later (CQ-005).
local function CopyDefaults(db)
	for key, value in pairs(defaults) do
		if type(db[key]) ~= type(value) then
			db[key] = value
		end
	end
	return db
end

-- Converts legacy string keys ("71") in a count bucket to numeric keys,
-- summing when both forms exist.
local function NumericKeys(bucket)
	local fixed = {}
	for key, count in pairs(bucket) do
		local skill = tonumber(key)
		if skill and type(count) == "number" then
			fixed[skill] = (fixed[skill] or 0) + count
		end
	end
	return fixed
end

local function ValidateGather(gather)
	for key, obs in pairs(gather) do
		if type(key) ~= "string" or type(obs) ~= "table" then
			gather[key] = nil
		else
			obs.misses = type(obs.misses) == "table" and obs.misses or {}
			obs.gains = type(obs.gains) == "table" and obs.gains or {}
			if type(obs.gainedAt) ~= "number" then
				obs.gainedAt = nil
			end
		end
	end
end

local function ValidateSkinIds(skinIds)
	for key, value in pairs(skinIds) do
		if type(key) ~= "number" or type(value) ~= "boolean" then
			skinIds[key] = nil
		end
	end
end

local function ValidateMinimapIcon(icon)
	if type(icon.minimapPos) ~= "number" then
		icon.minimapPos = nil
	end
	if type(icon.hide) ~= "boolean" then
		icon.hide = nil
	end
end

-- One-time migrations keyed on db.version (CQ-004, ARCH-006). Runs before
-- validation so legacy shapes are converted rather than discarded.
local function MigrateDB(db)
	local version = type(db.version) == "number" and db.version or 1
	if version < 2 then
		-- 1.x: the default fallback-button angle moved from 220 to 200.
		if db.minimapAngle == 220 then
			db.minimapAngle = 200
		end
		-- 1.x: LibDBIcon positions in the old 210-220 default band were
		-- re-aligned with minimapAngle on every load; do it once here.
		if type(db.minimapIcon) == "table" then
			local pos = db.minimapIcon.minimapPos
			if type(pos) == "number" and pos >= 210 and pos <= 220 then
				db.minimapIcon.minimapPos = db.minimapAngle
			end
		end
		-- 1.x: early builds stored skill counts under string keys.
		if type(db.gather) == "table" then
			for _, obs in pairs(db.gather) do
				if type(obs) == "table" then
					if type(obs.misses) == "table" then
						obs.misses = NumericKeys(obs.misses)
					end
					if type(obs.gains) == "table" then
						obs.gains = NumericKeys(obs.gains)
					end
				end
			end
		end
	end
	db.version = DB_VERSION
end

local function LoadDB(saved)
	local db = type(saved) == "table" and saved or {}
	MigrateDB(db)
	CopyDefaults(db)
	for _, key in ipairs({ "gather", "skinIds", "minimapIcon" }) do
		if type(db[key]) ~= "table" then
			db[key] = {}
		end
	end
	ValidateGather(db.gather)
	ValidateSkinIds(db.skinIds)
	ValidateMinimapIcon(db.minimapIcon)
	return db
end

local function CacheProfession(index)
	if not index then
		return
	end
	local _, _, skillLevel, maxSkillLevel, _, _, skillLine, skillModifier = GetProfessionInfo(index)
	local rank = (skillLevel or 0) + (skillModifier or 0)
	local base = skillLevel or 0
	local maxSkill = maxSkillLevel or 0
	if skillLine == ns.HERB_SKILL_LINE then
		ns.skills.herb = rank
		ns.skills.herbBase = base
		ns.skills.herbMax = maxSkill
	elseif skillLine == ns.MINE_SKILL_LINE then
		ns.skills.mine = rank
		ns.skills.mineBase = base
		ns.skills.mineMax = maxSkill
	elseif skillLine == ns.SKIN_SKILL_LINE then
		ns.skills.skin = rank
		ns.skills.skinBase = base
		ns.skills.skinMax = maxSkill
	end
end

local function RefreshSkills()
	ns.skills.herb = nil
	ns.skills.mine = nil
	ns.skills.skin = nil
	ns.skills.herbBase = nil
	ns.skills.mineBase = nil
	ns.skills.skinBase = nil
	ns.skills.herbMax = nil
	ns.skills.mineMax = nil
	ns.skills.skinMax = nil
	skillsRefreshed = true
	if not GetProfessions or not GetProfessionInfo then
		return
	end
	local prof1, prof2 = GetProfessions()
	CacheProfession(prof1)
	CacheProfession(prof2)
end

local function DifficultyColor(skill, node)
	local yellow, green, grey = node.yellow, node.green, node.grey
	if not yellow or not green or not grey then
		return nil
	end
	if skill < node.orange then
		return COLOR_PREFIX.red
	elseif skill < yellow then
		return COLOR_PREFIX.orange
	elseif skill < green then
		return COLOR_PREFIX.yellow
	elseif skill < grey then
		return COLOR_PREFIX.green
	end
	return COLOR_PREFIX.grey
end

local function NormalizeName(text)
	if not text or text == "" then
		return nil
	end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|T.-|t", ""):gsub("|A:.-|a", "")
	text = text:gsub(" %(%d+/%d+%)$", ""):gsub(" %(%d+%)$", "")
	return text:match("^%s*(.-)%s*$")
end

local function ExactNode(text)
	if not text or text == "" then
		return nil
	end
	local lookup = ns.LOOKUP
	if not lookup then
		return nil
	end
	if not text:find("|", 1, true) and not text:find("(", 1, true) then
		local node = lookup[text]
		if node then
			return text, node
		end
		return nil, nil, text
	end
	local cleaned = NormalizeName(text)
	if not cleaned or cleaned == "" then
		return nil
	end
	local node = lookup[cleaned]
	if node then
		return cleaned, node
	end
	return nil, nil, cleaned
end

local function TitleLine(name, skill, required)
	local db = ns.db
	if db.showCurrent and db.showRequired then
		return name .. " (" .. skill .. "/" .. required .. ")"
	elseif db.showCurrent then
		return name .. " (" .. skill .. ")"
	elseif db.showRequired then
		return name .. " (" .. required .. ")"
	end
	return name
end

local function CountAt(bucket, skill)
	local n = bucket[skill]
	if type(n) ~= "number" then
		return 0
	end
	return n
end

local function GatherObs(key)
	local db = ns.db
	if not db or not key then
		return nil
	end
	return db.gather[key]
end

local function GainedAtOrAbove(obs, skill)
	return type(obs.gainedAt) == "number" and obs.gainedAt >= skill
end

local function ApplyObservation(band, key)
	local obs = GatherObs(key)
	if not obs or type(obs.gainedAt) ~= "number" or obs.gainedAt >= band.orange then
		return band
	end
	return {
		orange = obs.gainedAt,
		yellow = band.yellow,
		green = band.green,
		grey = band.grey,
		prof = band.prof,
		key = key,
	}
end

local function ColorFromRate(gains, misses)
	local total = gains + misses
	if total < RATE_TRIES or gains <= 0 then
		return nil
	end
	local rate = gains / total
	if rate >= 0.75 then
		return COLOR_PREFIX.orange
	end
	if rate >= 0.4 then
		return COLOR_PREFIX.yellow
	end
	return COLOR_PREFIX.green
end

local function ObservedColor(skill, band, key)
	local color = DifficultyColor(skill, band)
	local obs = GatherObs(key)
	if not obs then
		return color
	end
	local gains = CountAt(obs.gains, skill)
	local misses = CountAt(obs.misses, skill)
	local rated = ColorFromRate(gains, misses)
	if rated then
		color = rated
	end
	if misses >= MISS_GREY and gains == 0 and not GainedAtOrAbove(obs, skill) then
		color = COLOR_PREFIX.grey
	end
	if GainedAtOrAbove(obs, skill) and color == COLOR_PREFIX.grey then
		color = COLOR_PREFIX.green
	end
	return color
end

local function FormatNode(name, node)
	local db = ns.db
	if node.prof == "herb" and not db.herbalism then
		return nil
	end
	if node.prof == "mine" and not db.mining then
		return nil
	end
	if not db.showCurrent and not db.showRequired and not db.color then
		return nil
	end
	if not skillsRefreshed then
		RefreshSkills()
	end
	local skill = ns.skills[node.prof]
	if type(skill) ~= "number" then
		return nil
	end
	local shown = ApplyObservation(node, node.key)
	return TitleLine(name, skill, shown.orange), ObservedColor(skill, shown, node.key)
end

local function SecretBlocked(value)
	if not issecretvalue then
		return false
	end
	return issecretvalue(value) and not (canaccessvalue and canaccessvalue(value))
end

local function ReadableString(value)
	if type(value) ~= "string" or SecretBlocked(value) then
		return nil
	end
	if value == "" then
		return nil
	end
	return value
end

local function CanIndex(value)
	if value == nil or SecretBlocked(value) then
		return false
	end
	if issecrettable and issecrettable(value) and not (canaccesstable and canaccesstable(value)) then
		return false
	end
	return true
end

local function FontStringByIndex(tooltip, index)
	if SecretBlocked(index) then
		return nil
	end
	local fs = tooltip["TextLeft" .. index]
	if fs then
		return fs
	end
	local name = tooltip.GetName and ReadableString(tooltip:GetName())
	if not name then
		return nil
	end
	return _G[name .. "TextLeft" .. index]
end

local function TooltipFontString(tooltip)
	return FontStringByIndex(tooltip, 1)
end

-- GetPrimaryTooltipData is the current accessor; GetTooltipData is the
-- "to be deprecated" alias (TooltipDataHandlerMixin, COMPAT-001).
local function PrimaryTooltipData(tooltip)
	if tooltip.GetPrimaryTooltipData then
		return tooltip:GetPrimaryTooltipData()
	end
	if tooltip.GetTooltipData then
		return tooltip:GetTooltipData()
	end
	return nil
end

local function LastLineText(tooltip)
	local count = tooltip.NumLines and tooltip:NumLines()
	if SecretBlocked(count) or type(count) ~= "number" or count < 1 then
		return nil
	end
	local fs = FontStringByIndex(tooltip, count)
	return fs and ReadableString(fs:GetText())
end

local function ColorWrap(text, prefix)
	if not prefix then
		return text
	end
	return prefix .. text .. "|r"
end

local function DataLeftText(data)
	if not CanIndex(data) then
		return nil
	end
	local lines = data.lines
	if not CanIndex(lines) then
		return nil
	end
	local line = lines[1]
	if not CanIndex(line) then
		return nil
	end
	return ReadableString(line.leftText)
end

local function FirstLine(tooltip, data)
	local fs = TooltipFontString(tooltip)
	local fromData = DataLeftText(data)
	if fromData then
		return fromData, fs
	end
	return fs and ReadableString(fs:GetText()), fs
end

local function ShowUnmatched(raw, cleaned)
	local db = ns.db
	if db.debug and cleaned and cleaned ~= lastDebugText and #cleaned < 60 then
		lastDebugText = cleaned
		print("|cff88ccff" .. ns.TITLE .. ":|r unmatched", string.format("%q", raw))
	end
end

local function ApplyDisplay(tooltip, fs, display)
	local current = fs and fs:GetText()
	if fs and not SecretBlocked(current) then
		if ReadableString(current) ~= display then
			fs:SetText(display)
		end
		fs:SetTextColor(1, 1, 1)
		return true
	end
	if LastLineText(tooltip) == display then
		return true
	end
	tooltip:AddLine(display)
	return true
end

local function ApplyLine(db, line)
	local name, node, cleaned = ExactNode(line)
	if not node then
		return line, false, nil, cleaned
	end
	local title, prefix = FormatNode(name, node)
	if not title then
		return line, false, node, cleaned
	end
	if db.color then
		return ColorWrap(title, prefix), true, node, cleaned
	end
	return title, true, node, cleaned
end

local function ForgetNode()
	lastNodeKey = nil
	lastNodeProf = nil
	lastNodeTime = 0
end

-- Records the node under the cursor so a following gather cast can be
-- attributed to it. `node` is nil when the hovered object is unknown; the
-- previous node is then forgotten so it cannot be misattributed (CQ-001).
local function RememberNode(node)
	if node and node.key and (node.prof == "herb" or node.prof == "mine") then
		lastNodeKey = node.key
		lastNodeProf = node.prof
		lastNodeTime = GetTime()
		return
	end
	ForgetNode()
end

-- `trackNode` is true only for Object and MinimapMouseover tooltips, where
-- the first line names the world object the player is about to interact with.
local function ApplyTooltip(tooltip, data, trackNode)
	local db = ns.db
	if not db or not db.enabled or not tooltip or not tooltip.GetName then
		return false
	end
	if not data then
		data = PrimaryTooltipData(tooltip)
	end

	local raw, fs = FirstLine(tooltip, data)
	if not raw then
		return false
	end

	if not raw:find("\n", 1, true) then
		local line, matched, node, cleaned = ApplyLine(db, raw)
		if trackNode then
			RememberNode(node)
		end
		if not matched then
			if not node then
				ShowUnmatched(raw, cleaned)
			end
			return false
		end
		return ApplyDisplay(tooltip, fs, line)
	end

	-- Stacked minimap pins: several object names separated by newlines.
	local matched = false
	local known = false
	local firstCleaned
	local parts = {}
	local index = 0
	local nodeCount = 0
	local singleNode
	for line in (raw .. "\n"):gmatch("(.-)\n") do
		index = index + 1
		local nextLine, lineMatched, node, cleaned = ApplyLine(db, line)
		if index == 1 then
			firstCleaned = cleaned
		end
		if node then
			known = true
			nodeCount = nodeCount + 1
			singleNode = node
		end
		if lineMatched then
			matched = true
		end
		parts[#parts + 1] = nextLine
	end
	if trackNode then
		-- Only an unambiguous stack (exactly one known node) is remembered.
		RememberNode(nodeCount == 1 and singleNode or nil)
	end

	if not matched then
		if not known then
			ShowUnmatched(raw, firstCleaned)
		end
		return false
	end

	return ApplyDisplay(tooltip, fs, table.concat(parts, "\n"))
end

local function OnObjectTooltip(tooltip, data)
	return ApplyTooltip(tooltip, data, true)
end

local function EnsureWarningFrame()
	if warningFrame then
		return
	end
	warningFrame = CreateFrame("Frame", nil, UIParent)
	warningFrame:SetFrameStrata("HIGH")
	warningFrame:SetSize(700, 64)
	warningFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	warningFrame:EnableMouse(false)
	warningFrame:Hide()
	warningText = warningFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	warningText:SetPoint("CENTER")
	warningText:SetJustifyH("CENTER")
end

-- Tracking state comes from the minimap tracking list only (COMPAT-002).
-- C_UnitAuras.GetPlayerAuraBySpellID is RequiresNonSecretAura in this build,
-- so it returns nothing in combat and only duplicates this answer otherwise.
-- C_Minimap.GetTrackingInfo carries no secret flags.
local function TrackingState()
	local herbSpell = ns.FIND_HERBS_SPELL
	local mineSpell = ns.FIND_MINERALS_SPELL
	local herbOn, mineOn = false, false
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		local info = C_Minimap.GetTrackingInfo(i)
		if type(info) == "table" and info.active then
			if info.spellID == herbSpell then
				herbOn = true
			elseif info.spellID == mineSpell then
				mineOn = true
			end
			if herbOn and mineOn then
				break
			end
		end
	end
	return herbOn, mineOn
end

local CheckTracking

-- Debug instrumentation for COMPAT-002: which event caused the last visible
-- warning change. If UNIT_AURA never appears here over a full session, the
-- UNIT_AURA registration in SetTrackingEvents can be dropped.
local trackingTrigger

local function DebugTrackingChange(what)
	if ns.db and ns.db.debug then
		print("|cff88ccff" .. ns.TITLE .. ":|r tracking warning", what, "after", trackingTrigger or "watchdog/other")
	end
end

local function HideWarning()
	lastWarningKey = nil
	warningElapsed = 0
	if warningFrame and warningFrame:IsShown() then
		DebugTrackingChange("hidden")
	end
	if warningFrame then
		warningFrame:SetScript("OnUpdate", nil)
		warningFrame:Hide()
	end
end

local function WarningWatchdogOnUpdate(_, elapsed)
	warningElapsed = warningElapsed + elapsed
	if warningElapsed < WARNING_POLL_INTERVAL then
		return
	end
	warningElapsed = 0
	CheckTracking()
end

local function ShowWarning(message)
	EnsureWarningFrame()
	if warningText:GetText() ~= message then
		warningText:SetText(message)
	end
	warningElapsed = 0
	warningFrame:SetScript("OnUpdate", WarningWatchdogOnUpdate)
	if not warningFrame:IsShown() then
		DebugTrackingChange("shown")
	end
	warningFrame:Show()
end

-- Tracking events are registered only while the warning feature can do
-- anything (ARCH-002); UNIT_AURA in particular fires on every aura change.
local trackingEventsActive = false

local function SetTrackingEvents(active)
	if active == trackingEventsActive then
		return
	end
	trackingEventsActive = active
	if active then
		eventFrame:RegisterEvent("MINIMAP_UPDATE_TRACKING")
		eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
		eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
	else
		eventFrame:UnregisterEvent("MINIMAP_UPDATE_TRACKING")
		eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
		eventFrame:UnregisterEvent("UNIT_AURA")
	end
end

CheckTracking = function()
	local db = ns.db
	if not db or not db.enabled or not db.warnTracking then
		SetTrackingEvents(false)
		HideWarning()
		return
	end

	local L = ns.L
	local needHerb = db.herbalism and ns.skills.herb
	local needMine = db.mining and ns.skills.mine
	if not needHerb and not needMine then
		SetTrackingEvents(false)
		HideWarning()
		return
	end
	SetTrackingEvents(true)

	local herbOn, mineOn = TrackingState()
	local message
	if needHerb and needMine then
		if herbOn or mineOn then
			HideWarning()
			return
		end
		message = L.TRACKING_OFF_BOTH
	elseif needHerb then
		if herbOn then
			HideWarning()
			return
		end
		message = L.SPELL_OFF:format(ns.SpellName(ns.FIND_HERBS_SPELL, L.FIND_HERBS))
	else
		if mineOn then
			HideWarning()
			return
		end
		message = L.SPELL_OFF:format(ns.SpellName(ns.FIND_MINERALS_SPELL, L.FIND_MINERALS))
	end

	if message == lastWarningKey and warningFrame and warningFrame:IsShown() then
		return
	end
	lastWarningKey = message
	ShowWarning(message)
end

local TRACKING_CHECK_DELAY = 0.5

local function OnTrackingTimer()
	trackingTimer = nil
	CheckTracking()
	trackingTrigger = nil
end

-- Coalesces bursts of tracking-related events into one check (PERF-001):
-- one pending timer, one shared callback, no per-event closures.
function ns.QueueTrackingCheck()
	if trackingTimer then
		return
	end
	trackingTimer = C_Timer.NewTimer(TRACKING_CHECK_DELAY, OnTrackingTimer)
end

local TRAIN_SECONDS = 4
local TRAIN_COOLDOWN = 30
local trainFrame
local trainText
local trainTimer
local lastTrainWarn = {}

local GATHER_SPELLS = {
	[ns.HERB_GATHER_SPELL] = "herb",
	[2368] = "herb",
	[3570] = "herb",
	[11993] = "herb",
	[ns.MINE_GATHER_SPELL] = "mine",
	[2576] = "mine",
	[3564] = "mine",
	[10248] = "mine",
	[8613] = "skin",
	[8617] = "skin",
	[8618] = "skin",
	[10768] = "skin",
}

local TRACKING_SPELLS = {
	[ns.FIND_HERBS_SPELL] = true,
	[ns.FIND_MINERALS_SPELL] = true,
}

local TRACKING_QUEUE_EVENTS = {
	MINIMAP_UPDATE_TRACKING = true,
	PLAYER_REGEN_ENABLED = true,
	UNIT_AURA = true,
}

local function EnsureTrainFrame()
	if trainFrame then
		return
	end
	trainFrame = CreateFrame("Frame", nil, UIParent)
	trainFrame:SetFrameStrata("HIGH")
	trainFrame:SetSize(700, 64)
	trainFrame:EnableMouse(false)
	trainFrame:Hide()
	trainText = trainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	trainText:SetPoint("CENTER")
	trainText:SetJustifyH("CENTER")
end

function ns.HideTrainWarning()
	if trainTimer then
		trainTimer:Cancel()
		trainTimer = nil
	end
	if trainFrame then
		trainFrame:Hide()
	end
end

local function ShowTrainWarning(message)
	EnsureTrainFrame()
	local y = 80
	if warningFrame and warningFrame:IsShown() then
		y = 140
	end
	trainFrame:ClearAllPoints()
	trainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, y)
	if trainText:GetText() ~= message then
		trainText:SetText(message)
	end
	trainFrame:Show()
	if trainTimer then
		trainTimer:Cancel()
	end
	trainTimer = C_Timer.NewTimer(TRAIN_SECONDS, function()
		trainTimer = nil
		if trainFrame then
			trainFrame:Hide()
		end
	end)
end

local function ProfessionForGatherSpell(spellID)
	return spellID and GATHER_SPELLS[spellID]
end

local function CheckTrainReminder(prof)
	local db = ns.db
	if not db or not db.enabled or not db.warnTrain then
		return
	end
	if prof == "herb" and not db.herbalism then
		return
	end
	if prof == "mine" and not db.mining then
		return
	end
	if prof == "skin" and not db.skinning then
		return
	end
	local baseKey = prof .. "Base"
	local maxKey = prof .. "Max"
	local base = ns.skills[baseKey]
	local maxSkill = ns.skills[maxKey]
	if base == nil or maxSkill == nil then
		RefreshSkills()
		base = ns.skills[baseKey]
		maxSkill = ns.skills[maxKey]
	end
	if type(base) ~= "number" or type(maxSkill) ~= "number" or maxSkill <= 0 then
		return
	end
	if base < maxSkill or maxSkill >= ns.SKILL_CAP then
		return
	end
	local L = ns.L
	local skillLine = ns.SKIN_SKILL_LINE
	local fallback = L.SKINNING
	if prof == "herb" then
		skillLine = ns.HERB_SKILL_LINE
		fallback = L.HERBALISM
	elseif prof == "mine" then
		skillLine = ns.MINE_SKILL_LINE
		fallback = L.MINING
	end
	local now = GetTime()
	if now - (lastTrainWarn[prof] or 0) < TRAIN_COOLDOWN then
		return
	end
	lastTrainWarn[prof] = now
	ShowTrainWarning(L.TRAIN_NEXT:format(ns.ProfessionName(skillLine, fallback)))
end

local ICON_TEXTURE = "Interface\\Icons\\INV_Misc_Flower_02"

local function UpdateMinimapButtonPosition()
	if not minimapBtn or not Minimap or ldbIcon then
		return
	end
	if minimapBtn:GetParent() ~= Minimap then
		return
	end
	local angle = math.rad(ns.db.minimapAngle)
	local radius = (Minimap:GetWidth() / 2) + 10
	minimapBtn:ClearAllPoints()
	minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- `showMinimapButton` is the only user-facing setting; `minimapIcon.hide` is
-- the derived field LibDBIcon reads from its db table (ARCH-006). This is the
-- single place that derives it.
local function MinimapIconDB()
	local icon = ns.db.minimapIcon
	icon.hide = not ns.db.showMinimapButton
	return icon
end

function ns.UpdateMinimapButton()
	if not ns.db then
		return
	end
	if ldbIcon then
		if MinimapIconDB().hide then
			ldbIcon:Hide(ns.TITLE)
		else
			ldbIcon:Show(ns.TITLE)
		end
		return
	end
	if not minimapBtn then
		return
	end
	if ns.db and ns.db.showMinimapButton then
		minimapBtn:Show()
		UpdateMinimapButtonPosition()
	else
		minimapBtn:Hide()
	end
end

local function TryLibDBIcon()
	local LibStub = _G.LibStub
	if not LibStub then
		return false
	end
	local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
	local icon = LibStub:GetLibrary("LibDBIcon-1.0", true)
	if not ldb or not icon then
		return false
	end

	local obj = ldb:GetDataObjectByName(ns.TITLE)
	if not obj then
		obj = ldb:NewDataObject(ns.TITLE, {
			type = "launcher",
			text = ns.TITLE,
			icon = ICON_TEXTURE,
			OnClick = function()
				ns.OpenSettings()
			end,
			OnTooltipShow = function(tt)
				tt:AddLine(ns.TITLE)
				tt:AddLine(ns.L.CLICK_SETTINGS, 1, 1, 1)
			end,
		})
	end
	if not obj then
		return false
	end

	local iconDB = MinimapIconDB()
	if not iconDB.minimapPos then
		-- First use with LibDBIcon: carry over the fallback button's angle.
		iconDB.minimapPos = ns.db.minimapAngle
	end
	if not icon:IsRegistered(ns.TITLE) then
		icon:Register(ns.TITLE, obj, iconDB)
	end
	ldbIcon = icon
	minimapBtn = icon.GetMinimapButton and icon:GetMinimapButton(ns.TITLE)
	ns.UpdateMinimapButton()
	return true
end

local function CreateMinimapButton()
	if minimapBtn then
		return
	end
	if TryLibDBIcon() then
		return
	end
	if not Minimap then
		return
	end

	minimapBtn = CreateFrame("Button", nil, Minimap)
	minimapBtn:SetSize(31, 31)
	minimapBtn:SetFrameStrata("MEDIUM")
	minimapBtn:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
	minimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	minimapBtn:RegisterForDrag("LeftButton")
	minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local icon = minimapBtn:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER", 0, 1)
	icon:SetTexture(ICON_TEXTURE)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local border = minimapBtn:CreateTexture(nil, "OVERLAY")
	border:SetSize(50, 50)
	border:SetPoint("CENTER")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	minimapBtn:SetScript("OnClick", function()
		if not minimapDragging then
			ns.OpenSettings()
		end
	end)

	minimapBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(ns.TITLE)
		GameTooltip:AddLine(ns.L.CLICK_SETTINGS, 1, 1, 1)
		GameTooltip:AddLine(ns.L.DRAG_MOVE, 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	minimapBtn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	minimapBtn:SetScript("OnDragStart", function(self)
		if self:GetParent() ~= Minimap then
			return
		end
		minimapDragging = true
		GameTooltip:Hide()
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			ns.db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
			UpdateMinimapButtonPosition()
		end)
	end)

	minimapBtn:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		C_Timer.After(0, function()
			minimapDragging = false
		end)
	end)

	ns.UpdateMinimapButton()
end

-- CQ-002: on Classic-rules clients the "Skinnable" tooltip line appears only
-- after a corpse has been emptied. A missing line is therefore treated as
-- "cannot be skinned" only for corpses this client has fully looted.
local lootedCorpses = {}
local LOOTED_CORPSE_SECONDS = 600
local pendingLootGuid
local pendingLootSlots = 0

local function DeadUnitGUID(unit)
	local dead = UnitIsDead(unit)
	if SecretBlocked(dead) or not dead then
		return nil
	end
	return ReadableString(UnitGUID(unit))
end

local function OnLootOpened()
	-- The corpse being looted is under the cursor (right-click) or targeted.
	pendingLootGuid = DeadUnitGUID("mouseover") or DeadUnitGUID("target")
	local slots = GetNumLootItems()
	pendingLootSlots = type(slots) == "number" and slots or 0
end

local function OnLootSlotCleared()
	if pendingLootSlots > 0 then
		pendingLootSlots = pendingLootSlots - 1
	end
end

local function OnLootClosed()
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

-- Loot events are only needed while skinning learning can run (ARCH-002).
function ns.UpdateLootEvents()
	local db = ns.db
	local active = (db and db.enabled and db.skinning) and true or false
	if active == lootEventsActive then
		return
	end
	lootEventsActive = active
	if active then
		eventFrame:RegisterEvent("LOOT_OPENED")
		eventFrame:RegisterEvent("LOOT_SLOT_CLEARED")
		eventFrame:RegisterEvent("LOOT_CLOSED")
	else
		eventFrame:UnregisterEvent("LOOT_OPENED")
		eventFrame:UnregisterEvent("LOOT_SLOT_CLEARED")
		eventFrame:UnregisterEvent("LOOT_CLOSED")
		pendingLootGuid = nil
	end
end

local function CorpseLooted(unit, data)
	local guid = ReadableString(UnitGUID(unit))
	if not guid and data and CanIndex(data) then
		guid = ReadableString(data.guid)
	end
	return guid ~= nil and lootedCorpses[guid] ~= nil
end

local function NoteGatherResult(key, skill, gained)
	local db = ns.db
	if not db or not key or type(skill) ~= "number" then
		return
	end
	local obs = db.gather[key]
	if not obs then
		obs = { misses = {}, gains = {} }
		db.gather[key] = obs
	end
	if gained then
		obs.gains[skill] = CountAt(obs.gains, skill) + 1
		if not obs.gainedAt or skill > obs.gainedAt then
			obs.gainedAt = skill
		end
		return
	end
	obs.misses[skill] = CountAt(obs.misses, skill) + 1
end

local ReportGatherLearn

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
	if ReportGatherLearn then
		ReportGatherLearn(entry.key, entry.skill, gained)
		return
	end
	NoteGatherResult(entry.key, entry.skill, gained)
end

local function DeadCreatureLevel(unit)
	if UnitExists and not UnitExists(unit) then
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
		local level = DeadCreatureLevel("target") or DeadCreatureLevel("mouseover") or lastSkinLevel
		if not level then
			return nil
		end
		return "skin:" .. level
	end
	if not lastNodeKey or lastNodeProf ~= prof then
		return nil
	end
	if GetTime() - lastNodeTime > NODE_KEY_SECONDS then
		ForgetNode()
		return nil
	end
	return lastNodeKey
end

local function ArmGatherWatch(spellID)
	local prof = ProfessionForGatherSpell(spellID)
	if not prof or not ns.db or not ns.db.enabled then
		return
	end
	RefreshSkills()
	local key = GatherKey(prof)
	local skill = ns.skills[prof]
	local base = ns.skills[prof .. "Base"]
	local maxSkill = ns.skills[prof .. "Max"]
	if not key or type(skill) ~= "number" or type(base) ~= "number" then
		gatherWatch = nil
		return
	end
	if gatherWatch and gatherWatch.timer then
		gatherWatch.timer:Cancel()
	end
	gatherWatch = {
		prof = prof,
		key = key,
		skill = skill,
		base = base,
		maxSkill = maxSkill,
		spell = spellID,
		pending = false,
	}
end

local function NoteGatherSkill()
	if not gatherWatch or not gatherWatch.pending then
		return false
	end
	RefreshSkills()
	local base = ns.skills[gatherWatch.prof .. "Base"]
	if type(base) == "number" and base > gatherWatch.base then
		FinishGatherWatch(gatherWatch, true)
		return true
	end
	return false
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, arg1, _, arg3)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		_G.GatherSkillTooltipDB = LoadDB(_G.GatherSkillTooltipDB)
		ns.db = _G.GatherSkillTooltipDB
		eventFrame:UnregisterEvent("ADDON_LOADED")
		eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
		eventFrame:RegisterEvent("SKILL_LINES_CHANGED")
		eventFrame:RegisterEvent("CHAT_MSG_SKILL")
		eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
		eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
		eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
		ns.UpdateLootEvents()
		if ns.InitOptions then
			ns.InitOptions()
		end
		eventFrame:RegisterEvent("PLAYER_LOGIN")
		return
	end

	if event == "PLAYER_LOGIN" then
		CreateMinimapButton()
		return
	end

	if event == "PLAYER_ENTERING_WORLD" then
		RefreshSkills()
		ns.QueueTrackingCheck()
		if not minimapBtn then
			CreateMinimapButton()
		end
		return
	end

	if event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
		if not NoteGatherSkill() then
			RefreshSkills()
		end
		ns.QueueTrackingCheck()
		return
	end

	if TRACKING_QUEUE_EVENTS[event] then
		trackingTrigger = event
		ns.QueueTrackingCheck()
		return
	end

	if event == "LOOT_OPENED" then
		OnLootOpened()
		return
	end
	if event == "LOOT_SLOT_CLEARED" then
		OnLootSlotCleared()
		return
	end
	if event == "LOOT_CLOSED" then
		OnLootClosed()
		return
	end

	if event == "UNIT_SPELLCAST_START" then
		ArmGatherWatch(arg3)
		return
	end

	if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
		if gatherWatch and gatherWatch.spell == arg3 and not gatherWatch.pending then
			if gatherWatch.timer then
				gatherWatch.timer:Cancel()
			end
			gatherWatch = nil
		end
		return
	end

	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if TRACKING_SPELLS[arg3] then
			ns.QueueTrackingCheck()
		end
		if gatherWatch and gatherWatch.spell == arg3 and not gatherWatch.pending then
			local entry = gatherWatch
			entry.pending = true
			entry.timer = C_Timer.NewTimer(GATHER_WATCH_SECONDS, function()
				FinishGatherWatch(entry, false)
			end)
		end
		local db = ns.db
		if not db or not db.enabled or not db.warnTrain or (not db.herbalism and not db.mining and not db.skinning) then
			return
		end
		local prof = ProfessionForGatherSpell(arg3)
		if prof then
			CheckTrainReminder(prof)
		end
	end
end)

local function StripInline(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function StripSkillSuffix(text)
	text = StripInline(text)
	text = text:gsub(" %([^%d%)]*%d+/%d+%)", "", 1)
	return (text:gsub(" %([^%d%)]*%d+%)", "", 1))
end

local function FirstNumber(text)
	local digits = text:match("%f[%d](%d+)%f[%D]")
	if not digits then
		return nil
	end
	return tonumber(digits)
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

local function LevelLine(tooltip, level)
	local count = tooltip.NumLines and tooltip:NumLines()
	if SecretBlocked(count) or type(count) ~= "number" or count < 2 then
		return nil
	end
	local last = count < 4 and count or 4
	local fallbackFs, fallbackRaw, fallbackBase, fallbackLevel
	for i = 2, last do
		local fs = FontStringByIndex(tooltip, i)
		local raw = fs and ReadableString(fs:GetText())
		if raw then
			local base = StripSkillSuffix(raw)
			local found = FirstNumber(base)
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

local function NpcIdFromGUID(guid)
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
	if UnitGUID and type(unit) == "string" then
		local id = NpcIdFromGUID(UnitGUID(unit))
		if id then
			return id
		end
	end
	if data and CanIndex(data) then
		return NpcIdFromGUID(data.guid)
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
	if ns.db.debug and name and byID ~= byName then
		print("|cff88ccff" .. ns.TITLE .. ":|r creature type mismatch", name, tostring(kindID), "id:", tostring(byID), "name:", tostring(byName))
	end
	return byID or byName
end

local function CanSkinUnit(unit, data)
	if type(unit) ~= "string" or SecretBlocked(unit) then
		return false
	end
	local player = UnitIsPlayer(unit)
	if SecretBlocked(player) or player then
		return false
	end
	local controlled = UnitPlayerControlled(unit)
	if SecretBlocked(controlled) or controlled then
		return false
	end
	local npcID = UnitNpcID(unit, data)
	local known = npcID and ns.db.skinIds[npcID]
	if known == false then
		return false
	end
	if known ~= true and not SkinnableCreatureType(unit) then
		return false
	end
	local dead = UnitIsDead(unit)
	if SecretBlocked(dead) then
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

local function SkinningOrange(level)
	if level <= 10 then
		return 1
	elseif level <= 20 then
		return (level * 10) - 100
	end
	return level * 5
end

local function UnitFromTooltip(tooltip, data)
	if tooltip.GetUnit then
		local _, unit = tooltip:GetUnit()
		if type(unit) == "string" and not SecretBlocked(unit) then
			return unit
		end
	end
	if not data or not UnitTokenFromGUID then
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

local function TooltipHasSkinnable(tooltip, data)
	if data and CanIndex(data) and CanIndex(data.lines) then
		for i = 1, #data.lines do
			local line = data.lines[i]
			if CanIndex(line) and (TextHasSkinnable(line.leftText) or TextHasSkinnable(line.rightText)) then
				return true
			end
		end
	end
	local count = tooltip.NumLines and tooltip:NumLines()
	if SecretBlocked(count) or type(count) ~= "number" then
		return false
	end
	for i = 1, count do
		local left = FontStringByIndex(tooltip, i)
		if left and TextHasSkinnable(left:GetText()) then
			return true
		end
		local right = tooltip["TextRight" .. i]
		if not right and tooltip.GetName then
			local name = ReadableString(tooltip:GetName())
			right = name and _G[name .. "TextRight" .. i]
		end
		if right and TextHasSkinnable(right:GetText()) then
			return true
		end
	end
	return false
end

local function CorpseIsOurs(unit)
	if UnitIsTapDenied then
		local denied = UnitIsTapDenied(unit)
		if SecretBlocked(denied) then
			return false
		end
		return not denied
	end
	if not UnitIsTapped or not UnitIsTappedByPlayer then
		return false
	end
	local tapped = UnitIsTapped(unit)
	if SecretBlocked(tapped) then
		return false
	end
	if not tapped then
		return true
	end
	local byPlayer = UnitIsTappedByPlayer(unit)
	if SecretBlocked(byPlayer) then
		return false
	end
	return not not byPlayer
end

local function LearnChat(text)
	local db = ns.db
	if not db or not db.enabled or not db.learnChat or type(text) ~= "string" or text == "" then
		return
	end
	print("|cff88ccff" .. ns.TITLE .. ":|r " .. text)
end

local function LearnSkin(tooltip, data)
	local db = ns.db
	if not db or not db.enabled or not tooltip then
		return
	end
	local unit = UnitFromTooltip(tooltip, data)
	if not unit then
		return
	end
	local dead = UnitIsDead(unit)
	if SecretBlocked(dead) or not dead then
		return
	end
	local npcID = UnitNpcID(unit, data)
	if not npcID then
		return
	end
	local previous = db.skinIds[npcID]
	local name = UnitName and ReadableString(UnitName(unit)) or tostring(npcID)
	if TooltipHasSkinnable(tooltip, data) then
		if previous ~= true then
			db.skinIds[npcID] = true
			LearnChat(ns.L.LEARNED_SKIN_YES:format(name))
		end
		return
	end
	if previous ~= nil then
		return
	end
	-- Negative evidence is only trusted for our own, fully looted corpse.
	if CorpseIsOurs(unit) and CorpseLooted(unit, data) then
		db.skinIds[npcID] = false
		LearnChat(ns.L.LEARNED_SKIN_NO:format(name))
	end
end

local function SkinningBand(level)
	local orange = SkinningOrange(level)
	return ApplyObservation({
		orange = orange,
		yellow = orange + 25,
		green = orange + 50,
		grey = orange + 100,
		prof = "skin",
	}, "skin:" .. level)
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

local function NodeByKey(key)
	if not ns.NODES then
		return nil
	end
	for _, node in pairs(ns.NODES) do
		if node.key == key then
			return node
		end
	end
	return nil
end

local function GatherSubject(key)
	local level = type(key) == "string" and key:match("^skin:(%d+)$")
	if level then
		local orange = SkinningOrange(tonumber(level))
		return ns.L.LEARNED_LEVEL:format(level), {
			orange = orange,
			yellow = orange + 25,
			green = orange + 50,
			grey = orange + 100,
			prof = "skin",
		}
	end
	local node = NodeByKey(key)
	if not node then
		return nil
	end
	return key, node
end

ReportGatherLearn = function(key, skill, gained)
	local name, band = GatherSubject(key)
	local before = name and ObservedColor(skill, ApplyObservation(band, key), key)
	NoteGatherResult(key, skill, gained)
	if not name then
		return
	end
	local after = ObservedColor(skill, ApplyObservation(band, key), key)
	if before == after then
		return
	end
	local word = ColorWord(after)
	if not word then
		return
	end
	LearnChat(ns.L.LEARNED_COLOR:format(name, word, skill))
end

local function ApplySkinningLine(tooltip, data)
	local db = ns.db
	if not db or not db.enabled or not db.skinning or not tooltip then
		return
	end
	if not skillsRefreshed then
		RefreshSkills()
	end
	if type(ns.skills.skin) ~= "number" then
		return
	end
	local unit = UnitFromTooltip(tooltip, data)
	if not unit or not CanSkinUnit(unit, data) then
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
	local shown = SkinningBand(level)
	local suffix = SkillSuffix(ns.skills.skin, shown.orange)
	if not suffix then
		return
	end
	local first, last = base:find("%f[%d]" .. level .. "%f[%D]")
	if not first then
		return
	end
	local colored = suffix
	if db.color then
		colored = ColorWrap(suffix, ObservedColor(ns.skills.skin, shown, "skin:" .. level))
	end
	local display = base:sub(1, last) .. colored .. base:sub(last + 1)
	if raw == display then
		return
	end
	fs:SetText(display)
end

local function OnUnitTooltip(tooltip, data)
	LearnSkin(tooltip, data)
	ApplySkinningLine(tooltip, data)
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
	if Enum.TooltipDataType.MinimapMouseover then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.MinimapMouseover, OnObjectTooltip)
	end
	if Enum.TooltipDataType.Object then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, OnObjectTooltip)
	end
	if Enum.TooltipDataType.Unit then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
	end
	if Enum.TooltipDataType.Corpse then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Corpse, OnUnitTooltip)
	end
end

if GameTooltip and not (Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit) then
	GameTooltip:HookScript("OnTooltipSetUnit", OnUnitTooltip)
end

-- UI-001: fallback for GameTooltip shows that carry no tooltip data. Typed
-- tooltips (Object, MinimapMouseover, Unit, ...) are handled by the post-calls
-- above, so this only runs for UI tooltips. It is instrumented: if a full
-- session reported by `/gst stats` shows 0 applied, this block can go.
ns.fallbackStats = { shown = 0, checked = 0, applied = 0, retried = 0 }
do
	local stats = ns.fallbackStats
	local retryPending = false

	local function TooltipLineReady(tooltip)
		local fs = TooltipFontString(tooltip)
		if not fs then
			return false
		end
		local text = fs:GetText()
		if SecretBlocked(text) then
			return true
		end
		return type(text) == "string" and text ~= ""
	end

	local function FallbackApply(tooltip, data)
		stats.checked = stats.checked + 1
		if ApplyTooltip(tooltip, data) then
			stats.applied = stats.applied + 1
			-- UI-002: outside a post-call the tooltip does not re-layout by itself.
			tooltip:Show()
		end
	end

	local function RetryFallback()
		retryPending = false
		local tooltip = GameTooltip
		if not tooltip:IsShown() or not ns.db or not ns.db.enabled then
			return
		end
		local data = PrimaryTooltipData(tooltip)
		if data and data.type ~= nil then
			return
		end
		FallbackApply(tooltip, data)
	end

	GameTooltip:HookScript("OnShow", function(tooltip)
		if not ns.db or not ns.db.enabled then
			return
		end
		stats.shown = stats.shown + 1
		local data = PrimaryTooltipData(tooltip)
		if data and data.type ~= nil then
			return
		end
		if TooltipLineReady(tooltip) then
			FallbackApply(tooltip, data)
			return
		end
		if retryPending then
			return
		end
		retryPending = true
		stats.retried = stats.retried + 1
		C_Timer.After(0, RetryFallback)
	end)
end
