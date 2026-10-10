-- luacheck configuration (TOOL-003), modeled on the BigWigs layout:
-- Lua 5.1 semantics, an explicit list of WoW globals this addon reads, and
-- only the five intentional globals it writes. Anything else is an error.
std = "lua51"
max_line_length = false
self = false

exclude_files = {
	".release/",
	".annotations/",
	"assets/",
}

-- Unit tests run under plain Lua 5.1 / LuaJIT and stub the few WoW globals
-- the loaded files bind at load time.
files["tests/"] = {
	std = "lua51",
	globals = {
		"issecretvalue",
		"canaccessvalue",
		"issecrettable",
		"canaccesstable",
		"C_Spell",
		"C_Timer",
		"C_TradeSkillUI",
		"GetProfessionInfo",
		"GetProfessions",
		"GetTime",
	},
}

-- Globals written on purpose.
globals = {
	"GatherSkillTooltipDB",
	"GatherSkillTooltip_OnAddonCompartmentClick",
	"SLASH_GATHERSKILLTOOLTIP1",
	"SLASH_GATHERSKILLTOOLTIP2",
	SlashCmdList = { fields = { "GATHERSKILLTOOLTIP" } },
}

-- WoW API and Blizzard UI globals read by this addon (build 70009).
read_globals = {
	-- Lua extensions and secret-value helpers
	"issecretvalue",
	"canaccessvalue",
	"issecrettable",
	"canaccesstable",

	-- Namespaces
	"C_Minimap",
	"C_Spell",
	"C_Timer",
	"C_TradeSkillUI",
	"Enum",

	-- Functions
	"CreateFrame",
	"GetCursorPosition",
	"GetLocale",
	"GetNumLootItems",
	"GetProfessionInfo",
	"GetProfessions",
	"GetTime",
	"UnitCanAttack",
	"UnitCreatureType",
	"UnitExists",
	"UnitGUID",
	"UnitIsDead",
	"UnitIsPlayer",
	"UnitIsTapDenied",
	"UnitLevel",
	"UnitName",
	"UnitPlayerControlled",
	"UnitTokenFromGUID",

	-- Frames and UI objects
	"GameTooltip",
	"Minimap",
	"UIParent",
	"Settings",
	"CreateSettingsListSectionHeaderInitializer",
	"CreateSettingsButtonInitializer",
	"MinimalSliderWithSteppersMixin",
	"TooltipDataProcessor",

	-- Global strings
	"UNIT_SKINNABLE_LEATHER",
}
