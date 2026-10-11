local _, ns = ...

-- Minimap launcher. LibDBIcon when that library is already loaded (Questie,
-- BigWigs). Otherwise a button named LibDBIcon10_<addon>, which is the frame
-- Ellesmere, ElvUI, and other collectors look for. The addon compartment is
-- the TOC entry, not LibDBIcon's showInCompartment.

local C_Timer = C_Timer
local GetCursorPosition = GetCursorPosition

local ICON_TEXTURE = "Interface\\Icons\\INV_Misc_Flower_02"
local FRAME_NAME = "LibDBIcon10_GatherSkillTooltip"

local minimapBtn
local ldbIcon
local minimapDragging
local created

local function UpdateMinimapButtonPosition()
	if not minimapBtn or ldbIcon then
		return
	end
	if minimapBtn:GetParent() ~= Minimap then
		return
	end
	local angle = math.rad(ns.db.minimapIcon.minimapPos)
	local radius = (Minimap:GetWidth() / 2) + 10
	minimapBtn:ClearAllPoints()
	minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- `showMinimapButton` is the only user-facing setting; `minimapIcon.hide` is
-- the derived field LibDBIcon reads from its db table.
local function MinimapIconDB()
	local icon = ns.db.minimapIcon
	if type(icon) ~= "table" then
		icon = {}
		ns.db.minimapIcon = icon
	end
	icon.hide = not ns.db.showMinimapButton
	return icon
end

-- Re-applies the launcher position. Used by the settings reset.
function ns.SyncMinimapIconPosition()
	if not ns.db then
		return
	end
	local icon = ns.db.minimapIcon
	if ldbIcon and ldbIcon.Refresh and icon then
		ldbIcon:Refresh(ns.TITLE, icon)
	end
	UpdateMinimapButtonPosition()
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
	if ns.db.showMinimapButton then
		minimapBtn:Show()
		UpdateMinimapButtonPosition()
	else
		minimapBtn:Hide()
	end
end

local function OnLauncherClick()
	ns.OpenSettings()
end

local function OnLauncherTooltip(tt)
	tt:AddLine(ns.DISPLAY)
	tt:AddLine(ns.L.CLICK_SETTINGS, 1, 1, 1)
end

local function StampButton(button, object, iconDB)
	if not button then
		return
	end
	button.dataObject = object
	button.db = iconDB
end

-- Optional third-party libraries: these guards are the only ones allowed.
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
			text = ns.DISPLAY,
			icon = ICON_TEXTURE,
			OnClick = OnLauncherClick,
			OnTooltipShow = OnLauncherTooltip,
		})
	end
	if not obj then
		return false
	end

	local iconDB = MinimapIconDB()
	if not icon:IsRegistered(ns.TITLE) then
		icon:Register(ns.TITLE, obj, iconDB)
	end
	ldbIcon = icon
	minimapBtn = (icon.GetMinimapButton and icon:GetMinimapButton(ns.TITLE)) or _G[FRAME_NAME]
	StampButton(minimapBtn, obj, iconDB)
	ns.UpdateMinimapButton()
	return true
end

local function OnButtonClick()
	if not minimapDragging then
		ns.OpenSettings()
	end
end

local function OnButtonEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText(ns.DISPLAY)
	GameTooltip:AddLine(ns.L.CLICK_SETTINGS, 1, 1, 1)
	GameTooltip:AddLine(ns.L.DRAG_MOVE, 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

local function OnButtonLeave()
	GameTooltip:Hide()
end

local function OnButtonDragUpdate()
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	ns.db.minimapIcon.minimapPos = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
	UpdateMinimapButtonPosition()
end

local function OnButtonDragStart(self)
	if self:GetParent() ~= Minimap then
		return
	end
	minimapDragging = true
	GameTooltip:Hide()
	self:SetScript("OnUpdate", OnButtonDragUpdate)
end

local function EndDrag()
	minimapDragging = false
end

local function OnButtonDragStop(self)
	self:SetScript("OnUpdate", nil)
	C_Timer.After(0, EndDrag)
end

local function CreateFallback()
	minimapBtn = _G[FRAME_NAME] or CreateFrame("Button", FRAME_NAME, Minimap)
	minimapBtn:SetParent(Minimap)
	minimapBtn:SetSize(31, 31)
	minimapBtn:SetFrameStrata("MEDIUM")
	minimapBtn:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
	minimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	minimapBtn:RegisterForDrag("LeftButton")

	local iconDB = MinimapIconDB()
	local object = {
		type = "launcher",
		text = ns.DISPLAY,
		icon = ICON_TEXTURE,
	}
	StampButton(minimapBtn, object, iconDB)

	if not minimapBtn.joipovInitialized then
		local bg = minimapBtn:CreateTexture(nil, "BACKGROUND")
		bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
		bg:SetSize(20, 20)
		bg:SetPoint("CENTER")

		local icon = minimapBtn:CreateTexture(nil, "ARTWORK")
		icon:SetSize(20, 20)
		icon:SetPoint("CENTER")
		icon:SetTexture(ICON_TEXTURE)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		minimapBtn.icon = icon

		local border = minimapBtn:CreateTexture(nil, "OVERLAY")
		border:SetSize(54, 54)
		border:SetPoint("TOPLEFT", -1, 1)
		border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
		minimapBtn.border = border

		minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
		minimapBtn:SetScript("OnClick", OnButtonClick)
		minimapBtn:SetScript("OnEnter", OnButtonEnter)
		minimapBtn:SetScript("OnLeave", OnButtonLeave)
		minimapBtn:SetScript("OnDragStart", OnButtonDragStart)
		minimapBtn:SetScript("OnDragStop", OnButtonDragStop)
		minimapBtn.joipovInitialized = true
	end

	ns.UpdateMinimapButton()
end

function ns.CreateMinimapButton()
	if created then
		ns.UpdateMinimapButton()
		return
	end
	created = true
	if not TryLibDBIcon() then
		CreateFallback()
	end
end
