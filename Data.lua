local _, ns = ...

ns.TITLE = "GatherSkillTooltip"

ns.HERB_SKILL_LINE = 182
ns.MINE_SKILL_LINE = 186
ns.SKIN_SKILL_LINE = 393
ns.FIND_HERBS_SPELL = 2383
ns.FIND_MINERALS_SPELL = 2580
ns.HERB_GATHER_SPELL = 2366
ns.MINE_GATHER_SPELL = 2575
ns.SKILL_CAP = 300

-- Gathering spell ranks -> profession key.
ns.GATHER_SPELLS = {
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

ns.TRACKING_SPELLS = {
	[ns.FIND_HERBS_SPELL] = true,
	[ns.FIND_MINERALS_SPELL] = true,
}

-- Locale-independent creature type IDs, the second return of
-- UnitCreatureType (COMPAT-003). Confirm in-game with
-- /dump UnitCreatureType("target") on a beast; ns.SKIN_TYPES (Locales.lua)
-- is the name fallback until that check is recorded in CODE_AUDIT.md.
ns.SKIN_TYPE_IDS = {
	[1] = true, -- Beast
	[2] = true, -- Dragonkin
}

local function Node(orange, yellow, green, grey, prof)
	return {
		orange = orange,
		yellow = yellow,
		green = green,
		grey = grey,
		prof = prof,
	}
end

local herb = "herb"
local mine = "mine"
local copper = Node(1, 25, 65, 100, mine)

ns.NODES = {
	["Peacebloom"] = Node(1, 25, 50, 100, herb),
	["Silverleaf"] = Node(1, 25, 50, 100, herb),
	["Earthroot"] = Node(15, 40, 65, 115, herb),
	["Mageroyal"] = Node(50, 75, 100, 150, herb),
	["Briarthorn"] = Node(70, 95, 120, 170, herb),
	["Stranglekelp"] = Node(85, 110, 135, 185, herb),
	["Bruiseweed"] = Node(100, 125, 150, 200, herb),
	["Wild Steelbloom"] = Node(115, 140, 165, 215, herb),
	["Grave Moss"] = Node(120, 145, 170, 220, herb),
	["Kingsblood"] = Node(125, 150, 175, 225, herb),
	["Liferoot"] = Node(150, 175, 200, 250, herb),
	["Fadeleaf"] = Node(160, 185, 210, 260, herb),
	["Goldthorn"] = Node(170, 195, 220, 270, herb),
	["Khadgar's Whisker"] = Node(185, 210, 235, 285, herb),
	["Wintersbite"] = Node(195, 220, 245, 295, herb),
	["Firebloom"] = Node(205, 230, 255, 305, herb),
	["Purple Lotus"] = Node(210, 235, 260, 310, herb),
	["Arthas' Tears"] = Node(220, 245, 270, 320, herb),
	["Sungrass"] = Node(230, 255, 280, 330, herb),
	["Blindweed"] = Node(235, 260, 285, 335, herb),
	["Ghost Mushroom"] = Node(245, 270, 295, 345, herb),
	["Gromsblood"] = Node(250, 275, 300, 350, herb),
	["Golden Sansam"] = Node(260, 285, 310, 360, herb),
	["Dreamfoil"] = Node(270, 295, 320, 370, herb),
	["Mountain Silversage"] = Node(280, 305, 330, 380, herb),
	["Plaguebloom"] = Node(285, 310, 335, 385, herb),
	["Icecap"] = Node(290, 315, 340, 390, herb),
	["Black Lotus"] = Node(300, 325, 350, 400, herb),

	["Copper Vein"] = copper,
	["Poor Copper Vein"] = copper,
	["Minor Copper Vein"] = copper,
	["Lesser Copper Vein"] = copper,
	["Small Copper Vein"] = copper,
	["Tin Vein"] = Node(65, 90, 115, 165, mine),
	["Silver Vein"] = Node(75, 100, 125, 175, mine),
	["Iron Deposit"] = Node(125, 150, 175, 225, mine),
	["Gold Vein"] = Node(155, 180, 205, 255, mine),
	["Mithril Deposit"] = Node(175, 200, 225, 275, mine),
	["Truesilver Deposit"] = Node(230, 255, 280, 330, mine),
	["Dark Iron Deposit"] = Node(230, 255, 280, 330, mine),
	["Small Thorium Vein"] = Node(245, 270, 295, 345, mine),
	["Rich Thorium Vein"] = Node(275, 300, 325, 375, mine),
	["Hakkari Thorium Vein"] = Node(275, 300, 325, 375, mine),
	["Incendicite Mineral Vein"] = Node(65, 90, 115, 165, mine),
	["Lesser Bloodstone Deposit"] = Node(75, 100, 125, 175, mine),
	["Indurium Mineral Vein"] = Node(150, 175, 200, 250, mine),
	["Ooze Covered Silver Vein"] = Node(75, 100, 125, 175, mine),
	["Ooze Covered Gold Vein"] = Node(155, 180, 205, 255, mine),
	["Ooze Covered Iron Deposit"] = Node(125, 150, 175, 225, mine),
	["Ooze Covered Mithril Deposit"] = Node(175, 200, 225, 275, mine),
	["Ooze Covered Truesilver Deposit"] = Node(230, 255, 280, 330, mine),
	["Ooze Covered Thorium Vein"] = Node(245, 270, 295, 345, mine),
	["Ooze Covered Rich Thorium Vein"] = Node(275, 300, 325, 375, mine),
	["Small Obsidian Chunk"] = Node(305, 330, 355, 405, mine),
	["Large Obsidian Chunk"] = Node(305, 330, 355, 405, mine),
}

-- Nodes sharing a table (copper variants) share one learned-data key: the
-- lexically smallest English name.
for name, node in pairs(ns.NODES) do
	if not node.key or name < node.key then
		node.key = name
	end
end

ns.NODE_BY_KEY = {}
for _, node in pairs(ns.NODES) do
	ns.NODE_BY_KEY[node.key] = node
end
