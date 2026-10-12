local _, ns = ...

local Settings = Settings
local CreateSettingsListSectionHeaderInitializer = CreateSettingsListSectionHeaderInitializer
local CreateSettingsButtonInitializer = CreateSettingsButtonInitializer

local optionSettings = {}

function ns.OpenSettings()
	if not ns.settingsCategory then
		ns.InitOptions()
	end
	if not ns.settingsCategory then
		ns.Print(ns.L.OPEN_FAILED)
		return
	end
	Settings.OpenToCategory(ns.settingsCategory:GetID())
end

function _G.GatherSkillTooltip_OnAddonCompartmentClick()
	ns.OpenSettings()
end

function _G.GatherSkillTooltip_OnAddonCompartmentEnter(_, owner)
	if not GameTooltip then
		return
	end
	GameTooltip:SetOwner(owner or UIParent, "ANCHOR_LEFT")
	GameTooltip:AddLine(ns.DISPLAY)
	GameTooltip:AddLine(ns.L.CLICK_SETTINGS, 1, 1, 1)
	GameTooltip:Show()
end

function _G.GatherSkillTooltip_OnAddonCompartmentLeave()
	if GameTooltip then
		GameTooltip:Hide()
	end
end

function ns.InitOptions()
	if ns.settingsCategory then
		return
	end

	local L = ns.L
	local example = ns.ExampleHerb()
	local herbName = ns.ProfessionName(ns.HERB_SKILL_LINE, L.HERBALISM)
	local mineName = ns.ProfessionName(ns.MINE_SKILL_LINE, L.MINING)
	local skinName = ns.ProfessionName(ns.SKIN_SKILL_LINE, L.SKINNING)
	local findHerbs = ns.SpellName(ns.FIND_HERBS_SPELL, L.FIND_HERBS)
	local findMinerals = ns.SpellName(ns.FIND_MINERALS_SPELL, L.FIND_MINERALS)

	local category, layout = Settings.RegisterVerticalLayoutCategory(ns.DISPLAY)
	ns.settingsCategory = category

	local function AddCheckbox(key, label, tooltip, default)
		if default == nil then
			default = true
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
			if key == "enabled" or key == "bannerUnlocked" then
				ns.ApplyBannerLayout()
			end
		end
		setting:SetValueChangedCallback(OnChanged)
		optionSettings[key] = setting
		return Settings.CreateCheckbox(category, setting, tooltip), setting
	end

	local function AddHeader(text)
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
	end

	local enabledCheckbox, enabledSetting = AddCheckbox(
		"enabled",
		L.ENABLE:format(ns.DISPLAY),
		L.ENABLE_TIP
	)
	local minimapCheckbox = AddCheckbox(
		"showMinimapButton",
		L.SHOW_MINIMAP,
		L.SHOW_MINIMAP_TIP
	)

	AddHeader(L.HEADER_PROFESSIONS)
	local herbCheckbox = AddCheckbox("herbalism", herbName, L.HERBALISM_TIP)
	local mineCheckbox = AddCheckbox("mining", mineName, L.MINING_TIP)
	local skinCheckbox = AddCheckbox("skinning", skinName, L.SKINNING_TIP)

	AddHeader(L.HEADER_TOOLTIP)
	local currentCheckbox = AddCheckbox("showCurrent", L.SHOW_CURRENT, L.SHOW_CURRENT_TIP:format(example))
	local requiredCheckbox = AddCheckbox("showRequired", L.SHOW_REQUIRED, L.SHOW_REQUIRED_TIP:format(example))
	local colorCheckbox = AddCheckbox("color", L.COLOR, L.COLOR_TIP)
	local learnCheckbox = AddCheckbox("learnChat", L.LEARN_CHAT, L.LEARN_CHAT_TIP, false)

	AddHeader(L.HEADER_TRACKING)
	local warnCheckbox = AddCheckbox(
		"warnTracking",
		L.WARN_TRACKING,
		L.WARN_TRACKING_TIP:format(findHerbs, findMinerals)
	)
	local bannerFontSlider
	if Settings.CreateSliderOptions and Settings.CreateSlider then
		local fontSetting = Settings.RegisterAddOnSetting(
			category,
			"GATHERSKILLTOOLTIP_BANNERFONT",
			"bannerFont",
			ns.db,
			Settings.VarType.Number,
			L.BANNER_SIZE,
			ns.defaults.bannerFont
		)
		fontSetting:SetValueChangedCallback(function()
			ns.db.bannerFont = ns.ClampBannerFont(ns.db.bannerFont)
			ns.ApplyBannerLayout()
		end)
		optionSettings.bannerFont = fontSetting
		local fontOpts = Settings.CreateSliderOptions(10, 32, 1)
		if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
			fontOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
				return tostring(math.floor(value + 0.5))
			end)
		end
		bannerFontSlider = Settings.CreateSlider(category, fontSetting, fontOpts, L.BANNER_SIZE_TIP)
	end
	local bannerUnlockCheckbox, bannerUnlockSetting = AddCheckbox(
		"bannerUnlocked",
		L.BANNER_UNLOCK,
		L.BANNER_UNLOCK_TIP,
		false
	)
	ns.bannerUnlockSetting = bannerUnlockSetting

	AddHeader(L.HEADER_TRAINER)
	local trainCheckbox = AddCheckbox(
		"warnTrain",
		L.WARN_TRAIN,
		L.WARN_TRAIN_TIP:format(herbName, mineName, skinName)
	)

	if CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsButtonInitializer(
			L.RESET_SETTINGS,
			L.RESET,
			ns.ResetAllSettings,
			L.RESET_TIP,
			true
		))
	end

	Settings.RegisterAddOnCategory(category)

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
		bannerUnlockCheckbox,
		trainCheckbox,
		minimapCheckbox,
	}) do
		child:SetParentInitializer(enabledCheckbox, MasterEnabled)
	end
	if bannerFontSlider then
		bannerFontSlider:SetParentInitializer(enabledCheckbox, MasterEnabled)
	end
end

function ns.ResetAllSettings()
	local db = ns.db
	local defaults = ns.defaults
	if not db or not defaults then
		return
	end
	for key, setting in pairs(optionSettings) do
		local value = defaults[key]
		if key == "bannerUnlocked" then
			value = false
		end
		if value ~= nil and setting:GetValue() ~= value then
			setting:SetValue(value)
		end
	end
	ns.ResetSettings(db)
	ns.UpdateMinimapButton()
	ns.ApplyBannerLayout()
	ns.QueueTrackingCheck()
	ns.UpdateLootEvents()
	if not db.warnTrain then
		ns.HideTrainWarning()
	end
	ns.Print(ns.L.RESET_DONE)
end

_G.SLASH_GATHERSKILLTOOLTIP1 = "/gst"
_G.SLASH_GATHERSKILLTOOLTIP2 = "/gatherskilltooltip"
_G.SlashCmdList.GATHERSKILLTOOLTIP = function(msg)
	msg = (msg and msg:match("^%s*(.-)%s*$") or ""):lower()
	if msg == "reset" then
		ns.ResetAllSettings()
		return
	end
	if msg == "debug" then
		if ns.db then
			ns.db.debug = not ns.db.debug
			ns.Print("debug " .. (ns.db.debug and ns.L.DEBUG_ON or ns.L.DEBUG_OFF))
		end
		return
	end
	if msg == "stats" then
		-- Diagnostic counters. English only, not user-facing.
		local s = ns.fallbackStats
		if s then
			ns.Print(string.format(
				"tooltip fallback: shown %d, checked %d, applied %d, retried %d",
				s.shown, s.checked, s.applied, s.retried
			))
		end
		return
	end
	ns.OpenSettings()
end
