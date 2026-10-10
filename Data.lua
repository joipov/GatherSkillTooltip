local _, ns = ...

-- TITLE is the LibDBIcon object key. DISPLAY is the name players see.
ns.TITLE = "GatherSkillTooltip"
ns.DISPLAY = "Gather Skill Tooltip"

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

-- Green is the integer midpoint of yellow and grey. The client keeps a node
-- yellow below that skill (the trade-skill color rule).
function ns.GreenSkill(yellow, grey)
	return math.floor((yellow + grey) / 2)
end

local herb = "herb"
local mine = "mine"
local copper = Node(1, 25, 62, 100, mine)
-- Forever starter herbs share Classic bands (Lock orange 1).
local peacebloom = Node(1, 25, 62, 100, herb)
local silverleaf = Node(1, 25, 62, 100, herb)

ns.NODES = {
	["Peacebloom"] = peacebloom,
	["Wilted Peacebloom"] = peacebloom,
	["Silverleaf"] = silverleaf,
	["Stunted Silverleaf"] = silverleaf,
	["Earthroot"] = Node(15, 40, 77, 115, herb),
	["Mageroyal"] = Node(50, 75, 112, 150, herb),
	["Briarthorn"] = Node(70, 95, 132, 170, herb),
	["Stranglekelp"] = Node(85, 110, 147, 185, herb),
	["Bruiseweed"] = Node(100, 125, 162, 200, herb),
	["Wild Steelbloom"] = Node(115, 140, 177, 215, herb),
	["Grave Moss"] = Node(120, 145, 182, 220, herb),
	["Kingsblood"] = Node(125, 150, 187, 225, herb),
	["Liferoot"] = Node(150, 175, 212, 250, herb),
	["Fadeleaf"] = Node(160, 185, 222, 260, herb),
	["Goldthorn"] = Node(170, 195, 232, 270, herb),
	["Khadgar's Whisker"] = Node(185, 210, 247, 285, herb),
	["Wintersbite"] = Node(195, 220, 257, 295, herb),
	["Firebloom"] = Node(205, 230, 267, 305, herb),
	["Purple Lotus"] = Node(210, 235, 272, 310, herb),
	["Arthas' Tears"] = Node(220, 245, 282, 320, herb),
	["Sungrass"] = Node(230, 255, 292, 330, herb),
	["Blindweed"] = Node(235, 260, 297, 335, herb),
	["Ghost Mushroom"] = Node(245, 270, 307, 345, herb),
	["Gromsblood"] = Node(250, 275, 312, 350, herb),
	["Golden Sansam"] = Node(260, 285, 322, 360, herb),
	["Dreamfoil"] = Node(270, 295, 332, 370, herb),
	["Mountain Silversage"] = Node(280, 305, 342, 380, herb),
	["Plaguebloom"] = Node(285, 310, 347, 385, herb),
	["Icecap"] = Node(290, 315, 352, 390, herb),
	["Black Lotus"] = Node(300, 325, 362, 400, herb),

	["Copper Vein"] = copper,
	["Poor Copper Vein"] = copper,
	["Weak Copper Vein"] = copper,
	["Minor Copper Vein"] = copper,
	["Lesser Copper Vein"] = copper,
	["Small Copper Vein"] = copper,
	["Tin Vein"] = Node(65, 90, 127, 165, mine),
	["Silver Vein"] = Node(75, 100, 137, 175, mine),
	["Iron Deposit"] = Node(125, 150, 187, 225, mine),
	["Gold Vein"] = Node(155, 180, 217, 255, mine),
	["Mithril Deposit"] = Node(175, 200, 237, 275, mine),
	["Truesilver Deposit"] = Node(230, 255, 292, 330, mine),
	["Dark Iron Deposit"] = Node(230, 255, 292, 330, mine),
	["Small Thorium Vein"] = Node(245, 270, 307, 345, mine),
	["Rich Thorium Vein"] = Node(275, 300, 337, 375, mine),
	["Hakkari Thorium Vein"] = Node(275, 300, 337, 375, mine),
	["Incendicite Mineral Vein"] = Node(65, 90, 127, 165, mine),
	["Lesser Bloodstone Deposit"] = Node(75, 100, 137, 175, mine),
	["Indurium Mineral Vein"] = Node(150, 175, 212, 250, mine),
	["Ooze Covered Silver Vein"] = Node(75, 100, 137, 175, mine),
	["Ooze Covered Gold Vein"] = Node(155, 180, 217, 255, mine),
	["Ooze Covered Iron Deposit"] = Node(125, 150, 187, 225, mine),
	["Ooze Covered Mithril Deposit"] = Node(175, 200, 237, 275, mine),
	["Ooze Covered Truesilver Deposit"] = Node(230, 255, 292, 330, mine),
	["Ooze Covered Thorium Vein"] = Node(245, 270, 307, 345, mine),
	["Ooze Covered Rich Thorium Vein"] = Node(275, 300, 337, 375, mine),
	["Small Obsidian Chunk"] = Node(305, 330, 367, 405, mine),
	["Large Obsidian Chunk"] = Node(305, 330, 367, 405, mine),
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

-- Gathering spell id -> "herb" / "mine" / "skin". Secret ids are not used as
-- table keys (COMPAT-102). Called at event time, after TooltipText.lua has
-- defined ns.SecretBlocked.
function ns.ProfessionForGatherSpell(spellID)
	if not spellID or ns.SecretBlocked(spellID) then
		return nil
	end
	return ns.GATHER_SPELLS[spellID]
end
