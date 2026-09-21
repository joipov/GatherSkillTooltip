local ADDON_NAME, ns = ...

ns.TITLE = "GatherSkillTooltip"

ns.defaults = {
	enabled = true,
	herbalism = true,
	mining = true,
	showCurrent = true,
	showRequired = true,
	color = true,
	warnTracking = true,
	showMinimapButton = true,
	minimapAngle = 220,
	debug = false,
}

ns.skills = {
	herb = nil,
	mine = nil,
}

local COLORS = {
	red = { 1.00, 0.10, 0.10 },
	orange = { 1.00, 0.50, 0.25 },
	yellow = { 1.00, 1.00, 0.00 },
	green = { 0.25, 0.75, 0.25 },
	grey = { 0.50, 0.50, 0.50 },
}

local warningFrame
local warningText
local trackingTimer
local lastWarningKey
local minimapBtn
local minimapDragging
local lastDebugText

local function CopyDefaults(db)
	for key, value in pairs(ns.defaults) do
		if db[key] == nil then
			db[key] = value
		end
	end
	return db
end

local function CopyTable(src)
	local dest = {}
	for key, value in pairs(src) do
		if type(value) == "table" then
			dest[key] = CopyTable(value)
		else
			dest[key] = value
		end
	end
	return dest
end

local function CacheProfession(index)
	if not index then
		return
	end
	local _, _, skillLevel, _, _, _, skillLine, skillModifier = GetProfessionInfo(index)
	local rank = (skillLevel or 0) + (skillModifier or 0)
	if skillLine == ns.HERB_SKILL_LINE then
		ns.skills.herb = rank
	elseif skillLine == ns.MINE_SKILL_LINE then
		ns.skills.mine = rank
	end
end

function ns.RefreshSkills()
	ns.skills.herb = nil
	ns.skills.mine = nil
	if not GetProfessions or not GetProfessionInfo then
		return
	end
	local prof1, prof2 = GetProfessions()
	CacheProfession(prof1)
	CacheProfession(prof2)
end

local function DifficultyColor(skill, node)
	if skill < node.orange then
		return COLORS.red
	elseif skill < node.yellow then
		return COLORS.orange
	elseif skill < node.green then
		return COLORS.yellow
	elseif skill < node.grey then
		return COLORS.green
	end
	return COLORS.grey
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

local function FindNode(text)
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
	local bestNode, bestLen
	for name, data in pairs(lookup) do
		if cleaned:find(name, 1, true) and (not bestLen or #name > bestLen) then
			bestNode, bestLen = data, #name
		end
	end
	if bestNode then
		return cleaned, bestNode
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
	if ns.skills.herb == nil and ns.skills.mine == nil then
		ns.RefreshSkills()
	end
	local skill = ns.skills[node.prof] or 0
	return TitleLine(name, skill, node.orange), DifficultyColor(skill, node)
end

local function TooltipFontString(tooltip)
	return tooltip.TextLeft1 or _G[tooltip:GetName() .. "TextLeft1"]
end

local function FirstLine(tooltip, data)
	local fs = TooltipFontString(tooltip)
	local visible = fs and fs:GetText()
	if visible and visible ~= "" then
		return visible, fs
	end
	if data and data.lines and data.lines[1] and data.lines[1].leftText then
		return data.lines[1].leftText, fs
	end
	return nil, fs
end

local function ApplyTooltip(tooltip, data)
	local db = ns.db
	if not db or not db.enabled or not tooltip or not tooltip.GetName then
		return false
	end
	if not data and tooltip.GetTooltipData then
		data = tooltip:GetTooltipData()
	end

	local raw, fs = FirstLine(tooltip, data)
	if not raw or not fs then
		return false
	end

	local name, node, cleaned = FindNode(raw)
	if not node then
		if db.debug and cleaned and cleaned ~= lastDebugText and #cleaned < 60 then
			lastDebugText = cleaned
			print("|cff88ccff" .. ns.TITLE .. ":|r unmatched", string.format("%q", raw))
		end
		return false
	end

	local title, color = FormatNode(name, node)
	if not title then
		return false
	end

	if fs:GetText() ~= title then
		fs:SetText(title)
	end
	if db.color and color then
		fs:SetTextColor(color[1], color[2], color[3])
	elseif HIGHLIGHT_FONT_COLOR then
		fs:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
	end
	return true
end

local function EnsureWarningFrame()
	if warningFrame then
		return
	end
	warningFrame = CreateFrame("Frame", "GatherSkillTooltipWarningFrame", UIParent)
	warningFrame:SetFrameStrata("HIGH")
	warningFrame:SetSize(700, 64)
	warningFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	warningFrame:EnableMouse(false)
	warningFrame:Hide()
	warningText = warningFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	warningText:SetPoint("CENTER")
	warningText:SetJustifyH("CENTER")
end

local function HideWarning()
	lastWarningKey = nil
	if warningFrame then
		warningFrame:Hide()
	end
end

local function ShowWarning(message)
	EnsureWarningFrame()
	if warningText:GetText() ~= message then
		warningText:SetText(message)
	end
	warningFrame:Show()
end

local function IsTrackingSpell(spellID)
	if not C_Minimap or not C_Minimap.GetNumTrackingTypes or not C_Minimap.GetTrackingInfo then
		return false
	end
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		local info = C_Minimap.GetTrackingInfo(i)
		if type(info) == "table" and info.spellID == spellID and info.active then
			return true
		end
	end
	return false
end

function ns.CheckTracking()
	local db = ns.db
	if not db or not db.enabled or not db.warnTracking then
		HideWarning()
		return
	end

	local L = ns.L
	local needHerb = db.herbalism and ns.skills.herb
	local needMine = db.mining and ns.skills.mine
	if not needHerb and not needMine then
		HideWarning()
		return
	end

	local herbOn = IsTrackingSpell(ns.FIND_HERBS_SPELL)
	local mineOn = IsTrackingSpell(ns.FIND_MINERALS_SPELL)
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

function ns.QueueTrackingCheck()
	if trackingTimer then
		trackingTimer:Cancel()
	end
	trackingTimer = C_Timer.NewTimer(0.5, function()
		trackingTimer = nil
		ns.CheckTracking()
	end)
end

local ICON_TEXTURE = "Interface\\Icons\\INV_Misc_Flower_02"

local function UpdateMinimapButtonPosition()
	if not minimapBtn or not Minimap or ns.ldbIcon then
		return
	end
	if minimapBtn:GetParent() ~= Minimap then
		return
	end
	local angle = math.rad(ns.db and ns.db.minimapAngle or 220)
	local radius = (Minimap:GetWidth() / 2) + 10
	minimapBtn:ClearAllPoints()
	minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function ns.UpdateMinimapButton()
	if ns.ldbIcon then
		ns.db.minimapIcon = ns.db.minimapIcon or {}
		ns.db.minimapIcon.hide = not (ns.db and ns.db.showMinimapButton)
		if ns.db.minimapIcon.hide then
			ns.ldbIcon:Hide(ns.TITLE)
		else
			ns.ldbIcon:Show(ns.TITLE)
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

	ns.db.minimapIcon = ns.db.minimapIcon or {}
	ns.db.minimapIcon.hide = ns.db.showMinimapButton == false
	if ns.db.minimapAngle and ns.db.minimapIcon.minimapPos == nil then
		ns.db.minimapIcon.minimapPos = ns.db.minimapAngle
	end
	if not icon:IsRegistered(ns.TITLE) then
		icon:Register(ns.TITLE, obj, ns.db.minimapIcon)
	end
	ns.ldbIcon = icon
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

	minimapBtn = CreateFrame("Button", "GatherSkillTooltipMinimapButton", Minimap)
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

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		local db = GatherSkillTooltipDB
		if (not db or not next(db)) and GatherSkillToolTipDB then
			db = CopyTable(GatherSkillToolTipDB)
		end
		if (not db or not next(db)) and GatherSkillTipDB then
			db = CopyTable(GatherSkillTipDB)
		end
		GatherSkillTooltipDB = CopyDefaults(db or {})
		ns.db = GatherSkillTooltipDB
		eventFrame:UnregisterEvent("ADDON_LOADED")
		eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
		eventFrame:RegisterEvent("SKILL_LINES_CHANGED")
		eventFrame:RegisterEvent("CHAT_MSG_SKILL")
		eventFrame:RegisterEvent("MINIMAP_UPDATE_TRACKING")
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
		ns.RefreshSkills()
		ns.QueueTrackingCheck()
		if not minimapBtn then
			CreateMinimapButton()
		end
		return
	end

	if event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
		ns.RefreshSkills()
		ns.QueueTrackingCheck()
		return
	end

	if event == "MINIMAP_UPDATE_TRACKING" then
		ns.QueueTrackingCheck()
	end
end)

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
	if Enum.TooltipDataType.MinimapMouseover then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.MinimapMouseover, ApplyTooltip)
	end
	if Enum.TooltipDataType.Object then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, ApplyTooltip)
	end
end

if GameTooltip then
	local minimapType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.MinimapMouseover
	local objectType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object
	GameTooltip:HookScript("OnShow", function(tooltip)
		local data = tooltip.GetTooltipData and tooltip:GetTooltipData()
		if minimapType and objectType then
			local tooltipType = data and data.type
			if tooltipType ~= nil and tooltipType ~= minimapType and tooltipType ~= objectType then
				return
			end
		end
		if ApplyTooltip(tooltip, data) then
			return
		end
		C_Timer.After(0, function()
			if tooltip:IsShown() then
				ApplyTooltip(tooltip)
			end
		end)
	end)
end
