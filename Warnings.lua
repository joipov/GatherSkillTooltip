local _, ns = ...

-- On-screen banners: the tracking warning ("Find Herbs is off") and the
-- trainer reminder ("visit a trainer"). One frame factory serves both
-- (ARCH-003); frames are created on first use, never at load.

local C_Timer = C_Timer
local C_Minimap = C_Minimap
local GetTime = GetTime

-- Banner frames ----------------------------------------------------------------

-- Returns (frame, fontString): a centered, click-through banner.
local function CreateBanner()
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetFrameStrata("HIGH")
	frame:SetSize(700, 64)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	frame:EnableMouse(false)
	frame:Hide()
	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	text:SetPoint("CENTER")
	text:SetJustifyH("CENTER")
	return frame, text
end

-- Tracking warning ---------------------------------------------------------------

local warningFrame
local warningText
local trackingTimer
local lastWarningKey
local warningElapsed = 0
local WARNING_POLL_INTERVAL = 1.0
local TRACKING_CHECK_DELAY = 0.5

local TRACKING_EVENTS = {
	"MINIMAP_UPDATE_TRACKING",
	"PLAYER_REGEN_ENABLED",
	{ "UNIT_AURA", "player" },
}

local function EnsureWarningFrame()
	if not warningFrame then
		warningFrame, warningText = CreateBanner()
	end
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
-- UNIT_AURA entry in TRACKING_EVENTS can be dropped.
local trackingTrigger

function ns.SetTrackingTrigger(event)
	trackingTrigger = event
end

local function DebugTrackingChange(what)
	ns.Debug("tracking warning", what, "after", trackingTrigger or "watchdog/other")
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
	ns.SetEventsRegistered(TRACKING_EVENTS, active)
end

-- Warning texts are built once the spell name is available and then reused
-- by the 1 Hz watchdog (PERF-003). A fallback-name result is not cached so
-- the real spell name is picked up once the client has it.
local spellOffMessages = {}

local function SpellOffMessage(key, spellID, fallback)
	local cached = spellOffMessages[key]
	if cached then
		return cached
	end
	local name = ns.SpellName(spellID, fallback)
	local message = ns.L.SPELL_OFF:format(name)
	if name ~= fallback then
		spellOffMessages[key] = message
	end
	return message
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
		message = SpellOffMessage("herb", ns.FIND_HERBS_SPELL, L.FIND_HERBS)
	else
		if mineOn then
			HideWarning()
			return
		end
		message = SpellOffMessage("mine", ns.FIND_MINERALS_SPELL, L.FIND_MINERALS)
	end

	if message == lastWarningKey and warningFrame and warningFrame:IsShown() then
		return
	end
	lastWarningKey = message
	ShowWarning(message)
end

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

-- Trainer reminder ---------------------------------------------------------------

local TRAIN_SECONDS = 4
local TRAIN_COOLDOWN = 30
local trainFrame
local trainText
local trainTimer
local lastTrainWarn = {}

local function EnsureTrainFrame()
	if not trainFrame then
		trainFrame, trainText = CreateBanner()
	end
end

local function OnTrainTimer()
	trainTimer = nil
	if trainFrame then
		trainFrame:Hide()
	end
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
	trainTimer = C_Timer.NewTimer(TRAIN_SECONDS, OnTrainTimer)
end

-- After a successful gather: remind the player when the profession is at its
-- current cap (base == max) and a higher rank exists.
function ns.CheckTrainReminder(prof)
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
	local skills = ns.skills
	local baseKey = prof .. "Base"
	local maxKey = prof .. "Max"
	local base = skills[baseKey]
	local maxSkill = skills[maxKey]
	if base == nil or maxSkill == nil then
		ns.RefreshSkills()
		base = skills[baseKey]
		maxSkill = skills[maxKey]
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
