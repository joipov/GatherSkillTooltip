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

-- Text buttons under the message. They are smaller than the message on
-- purpose: the warning is the headline, the buttons are the fix.
local BUTTON_GAP = 14
local BUTTON_PADDING = 4

local function LayoutButtons(row)
	local totalWidth, maxHeight = 0, 0
	local previous
	for i = 1, #row.buttons do
		local button = row.buttons[i]
		if button:IsShown() then
			button:ClearAllPoints()
			if previous then
				button:SetPoint("LEFT", previous, "RIGHT", BUTTON_GAP, 0)
				totalWidth = totalWidth + BUTTON_GAP
			else
				button:SetPoint("LEFT", row, "LEFT", 0, 0)
			end
			previous = button
			totalWidth = totalWidth + button:GetWidth()
			local height = button:GetHeight()
			if height > maxHeight then
				maxHeight = height
			end
		end
	end
	if totalWidth < 1 then
		totalWidth = 1
	end
	if maxHeight < 1 then
		maxHeight = 1
	end
	row:SetSize(totalWidth, maxHeight)
	return totalWidth, maxHeight
end

-- hint is the second line, passed only while this frame is the drag anchor.
-- row is the optional text-button row under the message.
-- bannerX and bannerY are the message center. The drag box hangs around that
-- point, so locking does not move the message.
local function LayoutText(frame, text, hint, row)
	ApplyBannerFont(text)
	local width = text:GetStringWidth()
	local textH = text:GetStringHeight()
	local height = textH
	text:ClearAllPoints()
	frame.messageDy = 0

	local rowShown = false
	if row and row:IsShown() then
		local rowWidth, rowHeight = LayoutButtons(row)
		rowShown = true
		row:ClearAllPoints()
		row:SetPoint("TOP", text, "BOTTOM", 0, -4)
		if rowWidth > width then
			width = rowWidth
		end
		height = height + 4 + rowHeight
	end

	if hint then
		ApplyBannerFont(hint)
		hint:SetText(ns.L.BANNER_DRAG_HINT)
		hint:Show()
		hint:ClearAllPoints()
		if rowShown then
			hint:SetPoint("TOP", row, "BOTTOM", 0, -2)
		else
			hint:SetPoint("TOP", text, "BOTTOM", 0, -2)
		end
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
		frame:SetBackdrop(nil)
		frame:EnableMouse(false)
	end
	if width < 1 then
		width = 1
	end
	if height < 1 then
		height = 1
	end
	text:SetPoint("TOP", 0, -12)
	local frameH = height + 24
	if hint or rowShown then
		-- Keep the message itself on the saved point; the buttons and the
		-- drag hint hang below it.
		frame.messageDy = frameH / 2 - (12 + textH / 2)
	end
	frame:SetSize(width + 32, frameH)
end

-- Tracking warning ---------------------------------------------------------------

local warningFrame
local warningText
local warningHint
local warningButtonRow
local warningButtons = {}
local warningElapsed = 0
local lastWarningKey
local warningHerbMissing
local warningMineMissing
local trackingTimer
local optimisticTimer
local WARNING_POLL_INTERVAL = 1.0
local TRACKING_CHECK_DELAY = 0.5
-- How long a cast or button click counts as "turned on" while the client
-- will not tell us the real tracking state (combat secrets, stale reads).
local OPTIMISTIC_SECONDS = 5

local TRACKING_EVENTS = {
	"MINIMAP_UPDATE_TRACKING",
	"PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED",
	{ "UNIT_AURA", "player" },
}

local trainFrame
local trainText
local PlaceTrain
local CheckTracking
local trackingTrigger

local function DebugTrackingChange(what)
	ns.Debug("tracking warning", what, "after", trackingTrigger or "watchdog/other")
end

function ns.SetTrackingTrigger(event)
	trackingTrigger = event
end

-- Last readable tracking-list index per profession. Kept across reads so the
-- warning buttons still work when a combat read hides the list.
local trackingIndex = { herb = nil, mine = nil }
local enabledAt = {}

local function MarkTrackingOn(prof)
	enabledAt[prof] = GetTime()
end

local function OptimisticOn(prof)
	local at = enabledAt[prof]
	return at ~= nil and GetTime() - at < OPTIMISTIC_SECONDS
end

local function OnOptimisticTimer()
	optimisticTimer = nil
	CheckTracking()
end

local function ScheduleOptimisticRecheck()
	if optimisticTimer then
		return
	end
	optimisticTimer = C_Timer.NewTimer(OPTIMISTIC_SECONDS, OnOptimisticTimer)
end

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

-- Tracking state comes from the minimap tracking list only.
-- C_UnitAuras.GetPlayerAuraBySpellID is RequiresNonSecretAura in this build,
-- so it returns nothing in combat and only duplicates this answer otherwise.
-- herbKnown/mineKnown are false when combat secrets or stale client data stop
-- us from seeing whether that profession's tracking is on. Unknown is not off:
-- the caller stays quiet instead of warning about a state it could not read.
local function TrackingState()
	local herbSpell = ns.FIND_HERBS_SPELL
	local mineSpell = ns.FIND_MINERALS_SPELL
	local herbOn, mineOn, herbKnown, mineKnown = false, false, true, true
	local count = C_Minimap.GetNumTrackingTypes()
	if ns.SecretBlocked(count) or type(count) ~= "number" then
		return false, false, false, false
	end
	local sawSecret = false
	for i = 1, count do
		local info = C_Minimap.GetTrackingInfo(i)
		if ns.CanIndex(info) then
			local spellID = info.spellID
			if ns.SecretBlocked(spellID) then
				sawSecret = true
			elseif spellID == herbSpell then
				trackingIndex.herb = i
				if ns.SecretBlocked(info.active) then
					herbKnown = false
				elseif info.active then
					herbOn = true
				end
			elseif spellID == mineSpell then
				trackingIndex.mine = i
				if ns.SecretBlocked(info.active) then
					mineKnown = false
				elseif info.active then
					mineOn = true
				end
			end
		elseif info then
			-- A secret entry may be the herb or ore tracker; it may also be
			-- another tracking type. Treat the state as unknown, not as off.
			sawSecret = true
		end
	end
	if sawSecret then
		if not herbOn then
			herbKnown = false
		end
		if not mineOn then
			mineKnown = false
		end
	end
	return herbOn, mineOn, herbKnown, mineKnown
end

-- Button font: below the banner size, and never larger than 12.
local function ApplyButtonFont(button)
	local size = ns.ClampBannerFont(ns.db and ns.db.bannerFont) - 6
	if size < 9 then
		size = 9
	elseif size > 12 then
		size = 12
	end
	local small = _G.GameFontNormalSmall
	local file, _, flags
	if small and small.GetFont then
		file, _, flags = small:GetFont()
	end
	if file then
		button.label:SetFont(file, size, flags)
	elseif small then
		button.label:SetFontObject(small)
	end
	button:SetSize(button.label:GetStringWidth() + BUTTON_PADDING * 2, button.label:GetStringHeight() + 2)
end

local function PrepareButton(button, spellID, fallback)
	local name = ns.SpellName(spellID, fallback)
	if type(name) ~= "string" or ns.SecretBlocked(name) or name == "" then
		name = fallback
	end
	button.label:SetText(ns.L.BANNER_TURN_ON:format(name))
	ApplyButtonFont(button)
end

local function EnableTracking(prof)
	TrackingState()
	local index = trackingIndex[prof]
	if type(index) == "number" and C_Minimap.SetTracking then
		C_Minimap.SetTracking(index, true)
	elseif CastSpellByID then
		CastSpellByID(prof == "herb" and ns.FIND_HERBS_SPELL or ns.FIND_MINERALS_SPELL)
	end
	-- Act on it now, then let the next state read confirm it. This is what
	-- clears the warning while combat hides the real tracking state.
	MarkTrackingOn(prof)
	CheckTracking()
end

local function CreateWarningButton(parent, prof)
	local button = CreateFrame("Button", nil, parent)
	local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("LEFT", button, "LEFT", 0, 0)
	label:SetPoint("RIGHT", button, "RIGHT", 0, 0)
	label:SetJustifyH("CENTER")
	label:SetTextColor(1, 0.82, 0)
	button.label = label
	button:SetScript("OnEnter", function(self)
		self.label:SetTextColor(1, 1, 1)
	end)
	button:SetScript("OnLeave", function(self)
		self.label:SetTextColor(1, 0.82, 0)
	end)
	button:SetScript("OnClick", function()
		EnableTracking(prof)
	end)
	button:Hide()
	return button
end

local function HideWarningButtons()
	if warningButtonRow then
		warningButtonRow:Hide()
	end
	if warningButtons.herb then
		warningButtons.herb:Hide()
	end
	if warningButtons.mine then
		warningButtons.mine:Hide()
	end
end

local function ShowWarningButtons(herbMissing, mineMissing)
	if not warningButtonRow then
		return nil
	end
	if herbMissing then
		PrepareButton(warningButtons.herb, ns.FIND_HERBS_SPELL, ns.L.FIND_HERBS)
		warningButtons.herb:Show()
	else
		warningButtons.herb:Hide()
	end
	if mineMissing then
		PrepareButton(warningButtons.mine, ns.FIND_MINERALS_SPELL, ns.L.FIND_MINERALS)
		warningButtons.mine:Show()
	else
		warningButtons.mine:Hide()
	end
	if herbMissing or mineMissing then
		warningButtonRow:Show()
		return warningButtonRow
	end
	warningButtonRow:Hide()
	return nil
end

local function EnsureWarningFrame()
	if warningFrame then
		return
	end
	warningFrame, warningText = CreateBanner()
	warningHint = warningFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	warningHint:SetJustifyH("CENTER")
	warningHint:Hide()
	warningButtonRow = CreateFrame("Frame", nil, warningFrame)
	warningButtonRow.buttons = {}
	warningButtonRow.buttons[1] = CreateWarningButton(warningButtonRow, "herb")
	warningButtonRow.buttons[2] = CreateWarningButton(warningButtonRow, "mine")
	warningButtons.herb = warningButtonRow.buttons[1]
	warningButtons.mine = warningButtonRow.buttons[2]
	warningButtonRow:Hide()
	warningFrame:SetScript("OnMouseDown", OnAnchorMouseDown)
	warningFrame:SetScript("OnMouseUp", OnAnchorMouseUp)
end

local function ShowAnchor()
	EnsureWarningFrame()
	local message = lastWarningKey or ns.L.TRACKING_OFF_BOTH
	warningText:SetText(message)
	HideWarningButtons()
	LayoutText(warningFrame, warningText, warningHint)
	PlaceBanner(warningFrame, 0)
	warningFrame:Show()
	RepositionTrain()
end

local function HideWarning()
	local wasShown = warningFrame and warningFrame:IsShown()
	lastWarningKey = nil
	warningHerbMissing = nil
	warningMineMissing = nil
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
		HideWarningButtons()
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

local function ShowWarning(message, herbMissing, mineMissing)
	EnsureWarningFrame()
	if warningText:GetText() ~= message then
		warningText:SetText(message)
	end
	local hint = nil
	local row = nil
	if AnchorUnlocked() then
		hint = warningHint
		HideWarningButtons()
	else
		row = ShowWarningButtons(herbMissing, mineMissing)
		if warningHint then
			warningHint:Hide()
		end
	end
	LayoutText(warningFrame, warningText, hint, row)
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
		ShowWarning(lastWarningKey, warningHerbMissing, warningMineMissing)
		return
	end
	if warningHint then
		warningHint:Hide()
	end
	HideWarningButtons()
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
	if type(name) ~= "string" or ns.SecretBlocked(name) or name == "" then
		name = fallback
	end
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

	-- The tracking list is secret or stale in combat on this client. Do not
	-- keep a warning up on a state we cannot trust: stay quiet until combat
	-- ends and verify then.
	if InCombatLockdown() then
		HideWarning()
		return
	end

	local herbOn, mineOn, herbKnown, mineKnown = TrackingState()
	if herbOn then
		enabledAt.herb = nil
	end
	if mineOn then
		enabledAt.mine = nil
	end
	local herbOk = herbOn or OptimisticOn("herb")
	local mineOk = mineOn or OptimisticOn("mine")

	local herbMissing, mineMissing = false, false
	if needHerb and needMine then
		if herbOk or mineOk then
			-- One tracking spell is enough when both professions are on.
			if (not herbOn and herbOk) or (not mineOn and mineOk) then
				ScheduleOptimisticRecheck()
			end
			HideWarning()
			return
		end
		herbMissing, mineMissing = true, true
	elseif needHerb then
		herbMissing = not herbOk
	else
		mineMissing = not mineOk
	end

	if not herbMissing and not mineMissing then
		if (needHerb and not herbOn and herbOk) or (needMine and not mineOn and mineOk) then
			ScheduleOptimisticRecheck()
		end
		HideWarning()
		return
	end

	-- Never warn about tracking that could not be read. Wait for a readable
	-- answer, or for the player to turn it on (caught by the cast/button path).
	if (herbMissing and not herbKnown) or (mineMissing and not mineKnown) then
		HideWarning()
		return
	end

	local message
	if needHerb and needMine then
		message = L.TRACKING_OFF_BOTH
	elseif needHerb then
		message = SpellOffMessage("herb", ns.FIND_HERBS_SPELL, L.FIND_HERBS)
	else
		message = SpellOffMessage("mine", ns.FIND_MINERALS_SPELL, L.FIND_MINERALS)
	end

	if message == lastWarningKey and warningFrame and warningFrame:IsShown()
		and warningHerbMissing == herbMissing and warningMineMissing == mineMissing then
		return
	end
	lastWarningKey = message
	warningHerbMissing = herbMissing
	warningMineMissing = mineMissing
	ShowWarning(message, herbMissing, mineMissing)
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

-- A successful Find Herbs / Find Minerals cast is the strongest signal we get
-- in combat, where the tracking list may answer unknown or stay stale.
function ns.NoteTrackingSpell(spellID)
	if ns.SecretBlocked(spellID) then
		return
	end
	if spellID == ns.FIND_HERBS_SPELL then
		MarkTrackingOn("herb")
	elseif spellID == ns.FIND_MINERALS_SPELL then
		MarkTrackingOn("mine")
	else
		return
	end
	ns.QueueTrackingCheck()
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
