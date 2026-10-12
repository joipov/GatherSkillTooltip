local _, ns = ...

-- On-screen banners: the tracking warning ("Find Herbs is off") and the
-- trainer reminder ("visit a trainer"). One frame factory serves both.
-- Frames are created on first use, never at load.

local C_Timer = C_Timer
local C_Minimap = C_Minimap
local GetTime = GetTime

-- Banner frames ----------------------------------------------------------------

local BANNER_BACKDROP = {
	bgFile = "Interface/Tooltips/UI-Tooltip-Background",
	edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
	tile = true,
	tileSize = 16,
	edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- Returns (frame, fontString): a banner. Click-through until unlock.
local function CreateBanner()
	local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame:Hide()
	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	text:SetJustifyH("CENTER")
	return frame, text
end

local function ApplyBannerFont(fs)
	local huge = _G.GameFontNormalHuge
	local file, _, flags
	if huge and huge.GetFont then
		file, _, flags = huge:GetFont()
	end
	local size = ns.ClampBannerFont(ns.db and ns.db.bannerFont)
	if file then
		fs:SetFont(file, size, flags)
	elseif huge then
		fs:SetFontObject(huge)
	end
end

local function AnchorUnlocked()
	local db = ns.db
	return db and db.enabled and db.bannerUnlocked or false
end

local function ClampOffset(x, y)
	local halfW = UIParent:GetWidth() / 2
	local halfH = UIParent:GetHeight() / 2
	local margin = 20
	if x < -halfW + margin then
		x = -halfW + margin
	elseif x > halfW - margin then
		x = halfW - margin
	end
	if y < -halfH + margin then
		y = -halfH + margin
	elseif y > halfH - margin then
		y = halfH - margin
	end
	return x, y
end

local function BannerOffset()
	local db = ns.db
	local x = db and type(db.bannerX) == "number" and db.bannerX or 0
	local y = db and type(db.bannerY) == "number" and db.bannerY or 80
	return ClampOffset(x, y)
end

local function PlaceBanner(frame, extraY)
	if frame.isMoving then
		return
	end
	local x, y = BannerOffset()
	local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local dy = (frame.messageDy or 0) * scale
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", x, y - dy + (extraY or 0))
end

-- hint is the second line, passed only while this frame is the drag anchor.
-- bannerX and bannerY are the message center. The drag box hangs around that
-- point, so locking does not move the message.
local function LayoutText(frame, text, hint)
	ApplyBannerFont(text)
	local width = text:GetStringWidth()
	local textH = text:GetStringHeight()
	local height = textH
	text:ClearAllPoints()
	frame.messageDy = 0
	if hint then
		ApplyBannerFont(hint)
		hint:SetText(ns.L.BANNER_DRAG_HINT)
		hint:Show()
		hint:ClearAllPoints()
		text:SetPoint("TOP", 0, -12)
		hint:SetPoint("TOP", text, "BOTTOM", 0, -2)
		local hintWidth = hint:GetStringWidth()
		if hintWidth > width then
			width = hintWidth
		end
		height = height + hint:GetStringHeight() + 2
		frame:SetBackdrop(BANNER_BACKDROP)
		frame:SetBackdropColor(0, 0, 0, 0.8)
		frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
		frame:EnableMouse(true)
	else
		text:SetPoint("CENTER")
		frame:SetBackdrop(nil)
		frame:EnableMouse(false)
	end
	if width < 1 then
		width = 1
	end
	if height < 1 then
		height = 1
	end
	local frameH = height + 24
	if hint then
		frame.messageDy = frameH / 2 - (12 + textH / 2)
	end
	frame:SetSize(width + 32, frameH)
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

local warningHint
local trainFrame
local trainText
local PlaceTrain

local function RepositionTrain()
	if PlaceTrain and trainFrame and trainFrame:IsShown() then
		PlaceTrain()
	end
end

local function SaveBannerPosition(frame)
	frame:StopMovingOrSizing()
	local x, y = frame:GetCenter()
	local px, py = UIParent:GetCenter()
	if not x or not px then
		frame.isMoving = nil
		PlaceBanner(frame, 0)
		return
	end
	local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	y = y + (frame.messageDy or 0)
	x, y = ClampOffset((x - px) * scale, (y - py) * scale)
	ns.db.bannerX = x
	ns.db.bannerY = y
	frame.isMoving = nil
	PlaceBanner(frame, 0)
	RepositionTrain()
end

local function OnAnchorMouseDown(self, button)
	if button == "LeftButton" then
		self.isMoving = true
		self:StartMoving()
	elseif button == "RightButton" then
		if self.isMoving then
			SaveBannerPosition(self)
		end
		ns.LockBanner()
	end
end

local function OnAnchorMouseUp(self)
	if self.isMoving then
		SaveBannerPosition(self)
	end
end

local function EnsureWarningFrame()
	if warningFrame then
		return
	end
	warningFrame, warningText = CreateBanner()
	warningHint = warningFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	warningHint:SetJustifyH("CENTER")
	warningHint:Hide()
	warningFrame:SetScript("OnMouseDown", OnAnchorMouseDown)
	warningFrame:SetScript("OnMouseUp", OnAnchorMouseUp)
end

-- Tracking state comes from the minimap tracking list only.
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

-- Which event caused the last visible
-- warning change. If UNIT_AURA never appears here over a full session, the
-- UNIT_AURA entry in TRACKING_EVENTS can be dropped.
local trackingTrigger

function ns.SetTrackingTrigger(event)
	trackingTrigger = event
end

local function DebugTrackingChange(what)
	ns.Debug("tracking warning", what, "after", trackingTrigger or "watchdog/other")
end

local function ShowAnchor()
	EnsureWarningFrame()
	local message = lastWarningKey or ns.L.TRACKING_OFF_BOTH
	warningText:SetText(message)
	LayoutText(warningFrame, warningText, warningHint)
	PlaceBanner(warningFrame, 0)
	warningFrame:Show()
	RepositionTrain()
end

local function HideWarning()
	local wasShown = warningFrame and warningFrame:IsShown()
	lastWarningKey = nil
	warningElapsed = 0
	if warningFrame then
		warningFrame:SetScript("OnUpdate", nil)
	end
	if AnchorUnlocked() then
		ShowAnchor()
		return
	end
	if wasShown then
		DebugTrackingChange("hidden")
	end
	if warningFrame then
		if warningHint then
			warningHint:Hide()
		end
		warningFrame:SetBackdrop(nil)
		warningFrame:EnableMouse(false)
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
	local hint = nil
	if AnchorUnlocked() then
		hint = warningHint
	elseif warningHint then
		warningHint:Hide()
	end
	LayoutText(warningFrame, warningText, hint)
	PlaceBanner(warningFrame, 0)
	warningElapsed = 0
	warningFrame:SetScript("OnUpdate", WarningWatchdogOnUpdate)
	if not warningFrame:IsShown() then
		DebugTrackingChange("shown")
	end
	warningFrame:Show()
	RepositionTrain()
end

function ns.ApplyBannerLayout()
	local db = ns.db
	if not db then
		return
	end
	if warningFrame and warningFrame.isMoving and not AnchorUnlocked() then
		SaveBannerPosition(warningFrame)
	end
	if trainFrame and trainText and trainText:GetText() and trainText:GetText() ~= "" then
		LayoutText(trainFrame, trainText, nil)
		RepositionTrain()
	end
	if AnchorUnlocked() then
		ShowAnchor()
		return
	end
	if not warningFrame then
		return
	end
	if lastWarningKey and db.enabled and db.warnTracking then
		ShowWarning(lastWarningKey)
		return
	end
	if warningHint then
		warningHint:Hide()
	end
	warningFrame:SetBackdrop(nil)
	warningFrame:EnableMouse(false)
	warningFrame:Hide()
end

function ns.LockBanner()
	local setting = ns.bannerUnlockSetting
	if setting and setting:GetValue() then
		setting:SetValue(false)
		return
	end
	if ns.db then
		ns.db.bannerUnlocked = false
	end
	ns.ApplyBannerLayout()
end

-- Tracking events are registered only while the warning feature can do
-- anything. UNIT_AURA in particular fires on every aura change.
local trackingEventsActive = false

local function SetTrackingEvents(active)
	if active == trackingEventsActive then
		return
	end
	trackingEventsActive = active
	ns.SetEventsRegistered(TRACKING_EVENTS, active)
end

-- Warning texts are built once the spell name is available and then reused
-- by the 1 Hz watchdog. A fallback-name result is not cached so
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

-- Coalesces bursts of tracking-related events into one check :
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
local trainTimer
local lastTrainWarn = {}

local function EnsureTrainFrame()
	if not trainFrame then
		trainFrame, trainText = CreateBanner()
	end
end

PlaceTrain = function()
	if not trainFrame or trainFrame.isMoving then
		return
	end
	if warningFrame and warningFrame:IsShown() then
		local top = warningFrame:GetTop()
		local _, parentY = UIParent:GetCenter()
		if top and parentY then
			local scale = warningFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
			local x = BannerOffset()
			local y = (top - parentY) * scale + 4 + trainFrame:GetHeight() / 2
			trainFrame:ClearAllPoints()
			trainFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
			return
		end
	end
	PlaceBanner(trainFrame, 0)
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
	if trainText:GetText() ~= message then
		trainText:SetText(message)
	end
	LayoutText(trainFrame, trainText, nil)
	PlaceTrain()
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
