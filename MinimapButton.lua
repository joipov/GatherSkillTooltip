local _, ns = ...

-- Minimap launcher: LibDBIcon when a LibDataBroker/LibDBIcon pair is present
-- (optional third-party libraries), otherwise a small built-in button.

local C_Timer = C_Timer
local GetCursorPosition = GetCursorPosition

local ICON_TEXTURE = "Interface\\Icons\\INV_Misc_Flower_02"

local minimapBtn
local ldbIcon
local minimapDragging

local function UpdateMinimapButtonPosition()
	if not minimapBtn or ldbIcon then
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
	tt:AddLine(ns.TITLE)
	tt:AddLine(ns.L.CLICK_SETTINGS, 1, 1, 1)
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
			text = ns.TITLE,
			icon = ICON_TEXTURE,
			OnClick = OnLauncherClick,
			OnTooltipShow = OnLauncherTooltip,
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

-- Built-in button scripts (one function each, no per-call closures).

local function OnButtonClick()
	if not minimapDragging then
		ns.OpenSettings()
	end
end

local function OnButtonEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText(ns.TITLE)
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
	ns.db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
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
	-- The click that ends the drag arrives in this frame; ignore it.
	C_Timer.After(0, EndDrag)
end

function ns.CreateMinimapButton()
	if minimapBtn then
		return
	end
	if TryLibDBIcon() then
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

	minimapBtn:SetScript("OnClick", OnButtonClick)
	minimapBtn:SetScript("OnEnter", OnButtonEnter)
	minimapBtn:SetScript("OnLeave", OnButtonLeave)
	minimapBtn:SetScript("OnDragStart", OnButtonDragStart)
	minimapBtn:SetScript("OnDragStop", OnButtonDragStop)

	ns.UpdateMinimapButton()
end
