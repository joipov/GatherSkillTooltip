local _, ns = ...

local Settings = _G["Settings"]
local CreateSettingsListSectionHeaderInitializer = _G["CreateSettingsListSectionHeaderInitializer"]

local TRUE = (Settings and Settings.Default and Settings.Default.True) or true
local FALSE = (Settings and Settings.Default and Settings.Default.False) or false

function ns.OpenSettings()
	if not ns.settingsCategory and ns.InitOptions then
		ns.InitOptions()
	end
	if not ns.settingsCategory then
		print("|cff88ccff" .. ns.TITLE .. ":|r " .. ns.L.OPEN_FAILED)
		return
	end
	local id = ns.settingsCategory.GetID and ns.settingsCategory:GetID()
	if type(id) ~= "number" then
		print("|cff88ccff" .. ns.TITLE .. ":|r " .. ns.L.OPEN_FAILED)
		return
	end
	if Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(id)
		return
	end
	print("|cff88ccff" .. ns.TITLE .. ":|r " .. ns.L.OPEN_FAILED)
end

function _G.GatherSkillTooltip_OnAddonCompartmentClick()
	ns.OpenSettings()
end

function ns.InitOptions()
	if ns.settingsCategory or not Settings or not Settings.RegisterVerticalLayoutCategory then
		return
	end

	local L = ns.L
	local example = ns.ExampleHerb()
	local herbName = ns.ProfessionName(ns.HERB_SKILL_LINE, L.HERBALISM)
	local mineName = ns.ProfessionName(ns.MINE_SKILL_LINE, L.MINING)
	local skinName = ns.ProfessionName(ns.SKIN_SKILL_LINE, L.SKINNING)
	local findHerbs = ns.SpellName(ns.FIND_HERBS_SPELL, L.FIND_HERBS)
	local findMinerals = ns.SpellName(ns.FIND_MINERALS_SPELL, L.FIND_MINERALS)

	local category, layout = Settings.RegisterVerticalLayoutCategory(ns.TITLE)
	ns.settingsCategory = category

	local function AddCheckbox(key, label, tooltip, default)
		if default == nil then
			default = TRUE
		end
		local setting = Settings.RegisterAddOnSetting(
			category,
			"GATHERSKILLTOOLTIP_" .. key:upper(),
			key,
			ns.db,
			Settings.VarType.Boolean,
			label,
			default
		)
		local function OnChanged()
			ns.QueueTrackingCheck()
			ns.UpdateLootEvents()
			if key == "showMinimapButton" then
				ns.UpdateMinimapButton()
			end
			if not ns.db.enabled or not ns.db.warnTrain then
				ns.HideTrainWarning()
			end
		end
		if setting.SetValueChangedCallback then
			setting:SetValueChangedCallback(OnChanged)
		elseif Settings.SetOnValueChangedCallback and setting.GetVariable then
			Settings.SetOnValueChangedCallback(setting:GetVariable(), OnChanged)
		end
		return Settings.CreateCheckbox(category, setting, tooltip), setting
	end

	local function AddHeader(text)
		if layout and CreateSettingsListSectionHeaderInitializer then
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
		end
	end

	local enabledCheckbox, enabledSetting = AddCheckbox(
		"enabled",
		L.ENABLE:format(ns.TITLE),
		L.ENABLE_TIP
	)
	local minimapCheckbox = AddCheckbox(
		"showMinimapButton",
		L.SHOW_MINIMAP,
		L.SHOW_MINIMAP_TIP,
		FALSE
	)

	AddHeader(L.HEADER_PROFESSIONS)
	local herbCheckbox = AddCheckbox("herbalism", herbName, L.HERBALISM_TIP)
	local mineCheckbox = AddCheckbox("mining", mineName, L.MINING_TIP)
	local skinCheckbox = AddCheckbox("skinning", skinName, L.SKINNING_TIP)

	AddHeader(L.HEADER_TOOLTIP)
	local currentCheckbox = AddCheckbox("showCurrent", L.SHOW_CURRENT, L.SHOW_CURRENT_TIP:format(example))
	local requiredCheckbox = AddCheckbox("showRequired", L.SHOW_REQUIRED, L.SHOW_REQUIRED_TIP:format(example))
	local colorCheckbox = AddCheckbox("color", L.COLOR, L.COLOR_TIP)
	local learnCheckbox = AddCheckbox("learnChat", L.LEARN_CHAT, L.LEARN_CHAT_TIP, FALSE)

	AddHeader(L.HEADER_TRACKING)
	local warnCheckbox = AddCheckbox(
		"warnTracking",
		L.WARN_TRACKING,
		L.WARN_TRACKING_TIP:format(findHerbs, findMinerals)
	)

	AddHeader(L.HEADER_TRAINER)
	local trainCheckbox = AddCheckbox(
		"warnTrain",
		L.WARN_TRAIN,
		L.WARN_TRAIN_TIP:format(herbName, mineName, skinName)
	)

	Settings.RegisterAddOnCategory(category)

	if enabledCheckbox and enabledCheckbox.SetParentInitializer then
		local function MasterEnabled()
			return enabledSetting:GetValue()
		end
		for _, child in ipairs({
			herbCheckbox,
			mineCheckbox,
			skinCheckbox,
			currentCheckbox,
			requiredCheckbox,
			colorCheckbox,
			learnCheckbox,
			warnCheckbox,
			trainCheckbox,
			minimapCheckbox,
		}) do
			if child and child.SetParentInitializer then
				child:SetParentInitializer(enabledCheckbox, MasterEnabled)
			end
		end
	end
end

_G.SLASH_GATHERSKILLTOOLTIP1 = "/gst"
_G.SLASH_GATHERSKILLTOOLTIP2 = "/gatherskilltooltip"
_G.SlashCmdList.GATHERSKILLTOOLTIP = function(msg)
	msg = (msg and msg:match("^%s*(.-)%s*$") or ""):lower()
	if msg == "debug" then
		if ns.db then
			ns.db.debug = not ns.db.debug
			print("|cff88ccff" .. ns.TITLE .. ":|r debug", ns.db.debug and ns.L.DEBUG_ON or ns.L.DEBUG_OFF)
		end
		return
	end
	if msg == "stats" then
		-- Diagnostic counters (UI-001); English only, not user-facing.
		local s = ns.fallbackStats
		if s then
			print(string.format(
				"|cff88ccff%s:|r tooltip fallback: shown %d, checked %d, applied %d, retried %d",
				ns.TITLE, s.shown, s.checked, s.applied, s.retried
			))
		end
		return
	end
	ns.OpenSettings()
end
