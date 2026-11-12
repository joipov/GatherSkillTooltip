-- Unit tests for the pure parts of GatherSkillTooltip.
-- Plain Lua 5.1 / LuaJIT, no game client:
-- luajit tests/run.lua (from the repository root)
-- lua5.1 tests/run.lua
-- Files that touch the WoW API at load (Events.lua, Options.lua, Warnings.lua)
-- are not loaded here; they are covered by the in-game checklist in CODE_AUDIT.md.
-- Tooltip.lua and Learning.lua only bind globals at load, so they are loaded
-- below a small set of stubs.

local root = (arg and arg[0] or "tests/run.lua"):match("^(.*)[/\\]tests[/\\]") or "."

-- The few globals the loaded files bind at load time.
issecretvalue = function() return false end
canaccessvalue = function() return true end
issecrettable = function() return false end
canaccesstable = function() return true end
C_Spell = {}
C_TradeSkillUI = {}

-- The loot window is driven by the tests through this table.
local lootState = { items = {}, source = nil, sourceName = nil, info = {} }
C_Item = {
	GetItemInfoInstant = function(link)
		local info = lootState.info[link]
		if not info then
			return nil
		end
		return 1, "Item", "Type", "", 0, info.class, info.subclass
	end,
}
function GetNumLootItems()
	return #lootState.items
end
function GetLootSlotLink(slot)
	return lootState.items[slot]
end
function GetLootSourceInfo()
	return lootState.source
end
function UnitNameFromGUID()
	return lootState.sourceName
end

-- Tooltip.lua and Learning.lua capture these at load. They are not called
-- until a test invokes a cast or a tooltip.
local now = 1000
function GetTime()
	return now
end
C_Timer = {
	NewTimer = function()
		return { Cancel = function() end }
	end,
}
local professionSkill = 150
function GetProfessions()
	return 1
end
function GetProfessionInfo(index)
	if index ~= 1 then
		return
	end
	-- name, icon, skill, max, abilities, offset, skillLine, modifier
	return "Herbalism", 0, professionSkill, 225, 0, 0, 182, 0
end
function UnitExists(unit)
	return unit == "player" or unit == "target"
end

local ns = {}
local function load(file)
	local chunk, err = loadfile(root .. "/" .. file)
	assert(chunk, err)
	chunk("GatherSkillTooltip", ns)
end
load("Data.lua")
load("Locales/enUS.lua")
load("Locales/deDE.lua")
load("Locales.lua")
load("Database.lua")
load("TooltipText.lua")
load("Skills.lua")
load("Nodes.lua")
load("Tooltip.lua")
load("Skinning.lua")
load("Learning.lua")

-- Runner -----------------------------------------------------------------------

local passed, failed = 0, 0

local function eq(actual, expected, label)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label or "value", tostring(expected), tostring(actual)), 2)
	end
end

local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end

local P = ns.COLOR_PREFIX

-- Fresh database for tests that read ns.db.
local function freshDB()
	ns.db = ns.LoadDB(nil)
	return ns.db
end

-- Entries are { class, subclass } pairs; source is a loot GUID string.
local function resetLoot(entries, source, sourceName)
	lootState.items = {}
	lootState.info = {}
	for i, entry in ipairs(entries) do
		local link = "loot:" .. i
		lootState.items[i] = link
		lootState.info[link] = { class = entry[1], subclass = entry[2] }
	end
	lootState.source = source
	lootState.sourceName = sourceName
end

-- TooltipText.lua ----------------------------------------------------------------

test("StripInline removes color codes", function()
	eq(ns.StripInline("|cffff0000Peacebloom|r"), "Peacebloom")
	eq(ns.StripInline("plain"), "plain")
end)

test("NormalizeName strips colors, textures, atlases and our suffixes", function()
	eq(ns.NormalizeName("|cff40bf40Peacebloom (70/1)|r"), "Peacebloom")
	eq(ns.NormalizeName("Copper Vein (25)"), "Copper Vein")
	eq(ns.NormalizeName("|TInterface\\Icons\\x:16|tSilverleaf"), "Silverleaf")
	eq(ns.NormalizeName("|A:atlas:16:16|a Earthroot "), "Earthroot")
	eq(ns.NormalizeName(""), nil)
	eq(ns.NormalizeName(nil), nil)
end)

test("StripSkillSuffix removes the first skill suffix only", function()
	eq(ns.StripSkillSuffix("Level 12|cff40bf40 (Skinning 100/20)|r (Beast)"), "Level 12 (Beast)")
	eq(ns.StripSkillSuffix("Level 12 (Skinning 20) (Beast)"), "Level 12 (Beast)")
	eq(ns.StripSkillSuffix("Level 12 (Beast)"), "Level 12 (Beast)")
end)

test("FirstNumber", function()
	eq(ns.FirstNumber("Level 12 (Beast)"), 12)
	eq(ns.FirstNumber("Level ?? (Beast)"), nil)
	eq(ns.FirstNumber("Level 12 Elite 3"), 12, "first run of digits")
	eq(ns.FirstNumber(""), nil)
end)

test("ReadableString rejects empty and non-strings", function()
	eq(ns.ReadableString(""), nil)
	eq(ns.ReadableString(5), nil)
	eq(ns.ReadableString("x"), "x")
end)

-- Data.lua / Locales -------------------------------------------------------------

test("NODE_BY_KEY maps shared nodes to one key", function()
	local copper = ns.NODES["Copper Vein"]
	eq(ns.NODES["Poor Copper Vein"], copper, "shared table")
	eq(ns.NODES["Weak Copper Vein"], copper, "shared table")
	eq(copper.green, 65, "copper turns green at 65")
	eq(copper.key, "Copper Vein", "lexically smallest name wins")
	eq(ns.NODE_BY_KEY["Copper Vein"], copper)
	eq(ns.NODE_BY_KEY["Poor Copper Vein"], nil)
	eq(ns.NODE_BY_KEY["Peacebloom"], ns.NODES["Peacebloom"])
end)

test("RegisterLocale overlays strings and adds aliases without touching NODES", function()
	eq(ns.L.EXAMPLE_HERB, "Friedensblume")
	eq(ns.LOOKUP["Friedensblume"], ns.NODES["Peacebloom"])
	eq(ns.LOOKUP["Verwelkte Friedensblume"], ns.NODES["Peacebloom"])
	eq(ns.LOOKUP["Schwaches Kupfervorkommen"], ns.NODES["Copper Vein"])
	eq(ns.LOOKUP["Mageres Kupfervorkommen"], ns.NODES["Copper Vein"])
	eq(ns.LOOKUP["Peacebloom"], ns.NODES["Peacebloom"])
	eq(ns.NODES["Friedensblume"], nil)
end)

test("Forever starter herbs share Classic bands", function()
	eq(ns.NODES["Wilted Peacebloom"], ns.NODES["Peacebloom"], "shared table")
	eq(ns.NODES["Stunted Silverleaf"], ns.NODES["Silverleaf"], "shared table")
	eq(ns.NODES["Wilted Peacebloom"].key, "Peacebloom")
	eq(ns.NODES["Stunted Silverleaf"].key, "Silverleaf")
	local name, node = ns.ExactNode("Wilted Peacebloom")
	eq(name, "Wilted Peacebloom"); eq(node, ns.NODES["Peacebloom"])
	name, node = ns.ExactNode("Stunted Silverleaf")
	eq(name, "Stunted Silverleaf"); eq(node, ns.NODES["Silverleaf"])
end)

test("Forever nodes use the verified Wowhead Forever requirements", function()
	eq(ns.NODES["Hyjal Silphium"].orange, 1)
	eq(ns.NODES["Tomb Weed"].orange, 1)
	eq(ns.NODES["Demonsage"].orange, 300)
	eq(ns.NODES["Demonsage"].yellow, 325)
	eq(ns.NODES["Demonsage"].grey, 400)
	eq(ns.NODES["Chunk of Amber"].orange, 1)
	eq(ns.NODES["Large Chunk of Amber"].orange, 1)
	eq(ns.NODES["Khadgar's Whisker"].orange, 185)
	eq(ns.NODES["Khadgar's Whisker"].yellow, 210)
	eq(ns.NODES["Khadgar's Whisker"].green, 250)
	eq(ns.NODES["Khadgar's Whisker"].grey, 285)
end)

test("GATHER_SPELLS and TRACKING_SPELLS", function()
	eq(ns.GATHER_SPELLS[2366], "herb")
	eq(ns.ProfessionForGatherSpell(2366), "herb")
	eq(ns.ProfessionForGatherSpell(nil), nil)
	eq(ns.ProfessionForGatherSpell(1), nil, "unknown spell")
	eq(ns.GATHER_SPELLS[10248], "mine")
	eq(ns.GATHER_SPELLS[10768], "skin")
	eq(ns.TRACKING_SPELLS[2383], true)
	eq(ns.TRACKING_SPELLS[2366], nil)
end)

-- Nodes.lua ------------------------------------------------------------------------

test("ExactNode: plain, decorated, alias and unknown", function()
	local name, node, cleaned = ns.ExactNode("Peacebloom")
	eq(name, "Peacebloom"); eq(node, ns.NODES["Peacebloom"]); eq(cleaned, nil)
	name, node = ns.ExactNode("|cff40bf40Peacebloom (70/1)|r")
	eq(name, "Peacebloom"); eq(node, ns.NODES["Peacebloom"])
	name, node = ns.ExactNode("Friedensblume")
	eq(name, "Friedensblume"); eq(node, ns.NODES["Peacebloom"])
	name, node, cleaned = ns.ExactNode("Unknown Thing (3)")
	eq(name, nil); eq(node, nil); eq(cleaned, "Unknown Thing")
	eq(ns.ExactNode(""), nil)
end)

test("ExactNode memo invalidates when a custom node is learned or forgotten", function()
	freshDB()
	local raw = "|cff40bf40Cache Test (1/1)|r"
	local name, node, cleaned = ns.ExactNode(raw)
	eq(name, nil); eq(node, nil); eq(cleaned, "Cache Test")
	eq(ns.LearnCustomNode("Cache Test", "herb", 60), true)
	name, node = ns.ExactNode(raw)
	eq(name, "Cache Test"); eq(node, ns.LOOKUP["Cache Test"])
	eq(ns.ForgetCustomNode("Cache Test"), "Cache Test")
	name, node, cleaned = ns.ExactNode(raw)
	eq(name, nil); eq(node, nil); eq(cleaned, "Cache Test")
end)

test("LootKind recognises herbs and ore and ignores gems", function()
	eq(ns.LootKind({ { 7, 9 } }), "herb")
	eq(ns.LootKind({ { 7, 7 } }), "mine")
	eq(ns.LootKind({ { 7, 7 }, { 3, 0 } }), "mine", "a gem does not change the source")
	eq(ns.LootKind({ { 7, 9 }, { 7, 7 } }), nil, "mixed loot")
	eq(ns.LootKind({ { 12, 0 } }), nil, "other items cancel the source")
	eq(ns.LootKind({}), nil)
	eq(ns.LootKind(nil), nil)
end)

test("DifficultyColor thresholds", function()
	local node = ns.NODES["Earthroot"] -- 15/40/80/115
	eq(ns.DifficultyColor(14, node), P.red)
	eq(ns.DifficultyColor(15, node), P.orange)
	eq(ns.DifficultyColor(39, node), P.orange)
	eq(ns.DifficultyColor(40, node), P.yellow)
	eq(ns.DifficultyColor(65, node), P.yellow)
	eq(ns.DifficultyColor(79, node), P.yellow)
	eq(ns.DifficultyColor(80, node), P.green)
	eq(ns.DifficultyColor(115, node), P.grey)
	eq(ns.DifficultyColor(10, node, 5), P.orange, "effective orange overrides table")
	eq(ns.DifficultyColor(10, { orange = 1 }), nil, "incomplete band")
	local kingsblood = ns.NODES["Kingsblood"] -- 125/150/190/225
	eq(ns.DifficultyColor(176, kingsblood), P.yellow)
	eq(ns.DifficultyColor(189, kingsblood), P.yellow)
	eq(ns.DifficultyColor(190, kingsblood), P.green)
end)

test("ColorFromRate thresholds", function()
	eq(ns.ColorFromRate(1, 2), nil, "fewer than RATE_TRIES observations")
	eq(ns.ColorFromRate(0, 10), nil, "no gains")
	eq(ns.ColorFromRate(3, 1), P.orange)
	eq(ns.ColorFromRate(2, 2), P.yellow)
	eq(ns.ColorFromRate(1, 3), P.green)
end)

test("EffectiveOrange lowers only custom nodes, not built-in Forever data", function()
	local db = freshDB()
	local node = ns.NODES["Copper Vein"] -- orange 1
	eq(ns.EffectiveOrange(node, node.key), 1)
	local tin = ns.NODES["Tin Vein"] -- orange 65
	db.gather["Tin Vein"] = { misses = {}, gains = {}, orangeSeen = 60 }
	eq(ns.EffectiveOrange(tin, "Tin Vein"), 65, "a built-in keeps the verified requirement")
	eq(ns.LearnCustomNode("Learned Herb", "herb", 60), true)
	local custom = ns.LOOKUP["Learned Herb"]
	db.gather["Learned Herb"] = { misses = {}, gains = {}, orangeSeen = 50 }
	eq(ns.EffectiveOrange(custom, "Learned Herb"), 50, "a custom node learns a lower orange")
	db.gather["Learned Herb"].orangeSeen = 70
	eq(ns.EffectiveOrange(custom, "Learned Herb"), 60, "never raised above the learned value")
end)

test("NoteGatherResult and ObservedColor", function()
	local db = freshDB()
	local node = ns.NODES["Copper Vein"] -- 1/25/65/100
	local key = node.key
	eq(ns.ObservedColor(100, node, 1, key), P.grey, "table color without observations")
	-- 20 misses at 100 with no gain: grey (already grey here); at 70 it flips green -> grey.
	for _ = 1, 20 do ns.NoteGatherResult(key, 70, false) end
	eq(db.gather[key].misses[70], 20)
	eq(ns.ObservedColor(70, node, 1, key), P.grey, "MISS_GREY without gains")
	-- A gain at 70 lifts grey back to green and records gainedAt.
	ns.NoteGatherResult(key, 70, true)
	eq(db.gather[key].gainedAt, 70)
	eq(db.gather[key].gains[70], 1)
	eq(ns.ObservedColor(70, node, 1, key), P.green)
	-- Rate override: 3 gains / 1 miss at skill 90 -> orange.
	for _ = 1, 3 do ns.NoteGatherResult(key, 90, true) end
	ns.NoteGatherResult(key, 90, false)
	eq(ns.ObservedColor(90, node, 1, key), P.orange)
	eq(db.gather[key].gainedAt, 90, "gainedAt tracks the highest gain")
	-- Non-number skill is ignored.
	ns.NoteGatherResult(key, "x", true)
	eq(db.gather[key].gains["x"], nil)
end)

-- Skinning.lua ----------------------------------------------------------------------

test("SkinningOrange formula", function()
	eq(ns.SkinningOrange(1), 1)
	eq(ns.SkinningOrange(10), 1)
	eq(ns.SkinningOrange(11), 10)
	eq(ns.SkinningOrange(20), 100)
	eq(ns.SkinningOrange(21), 105)
	eq(ns.SkinningOrange(60), 300)
end)

test("SkinningBand is cached and carries the learned-data key", function()
	local a = ns.SkinningBand(25)
	eq(a.orange, 125); eq(a.yellow, 150); eq(a.green, 190); eq(a.grey, 225)
	eq(a.prof, "skin"); eq(a.key, "skin:25")
	eq(ns.SkinningBand(25), a, "same table on second call")
end)

test("NpcIdFromGUID on real GUID shapes", function()
	eq(ns.NpcIdFromGUID("Creature-0-4234-0-58-299-00001F2A3B"), 299)
	eq(ns.NpcIdFromGUID("Vehicle-0-4234-0-58-299-00001F2A3B"), nil, "only creatures")
	eq(ns.NpcIdFromGUID("Player-1-00000001"), nil)
	eq(ns.NpcIdFromGUID(""), nil)
	eq(ns.NpcIdFromGUID(nil), nil)
end)

-- Database.lua -----------------------------------------------------------------------

test("LoadDB applies defaults and versions a fresh table", function()
	local db = ns.LoadDB(nil)
	eq(db.version, ns.DB_VERSION)
	eq(db.enabled, true)
	eq(db.learnChat, false)
	eq(db.minimapIcon.minimapPos, 200)
	eq(db.bannerFont, 18)
	eq(db.bannerX, 0)
	eq(db.bannerY, 80)
	eq(db.bannerUnlocked, false)
	eq(type(db.gather), "table"); eq(type(db.skinIds), "table"); eq(type(db.minimapIcon), "table")
	eq(type(db.customNodes), "table")
end)

test("LoadDB migrates 1.x data once", function()
	local saved = {
		minimapAngle = 220,
		minimapIcon = { minimapPos = 215, hide = "no" },
		gather = {
			["Copper Vein"] = { misses = { ["71"] = 2, [71] = 1 }, gains = { ["80"] = 1 } },
			bogus = "text",
			[7] = { misses = {}, gains = {} },
		},
		skinIds = { [299] = true, ["300"] = true, [301] = "yes" },
		enabled = "true",
	}
	local db = ns.LoadDB(saved)
	eq(db, saved, "same table")
	eq(db.version, ns.DB_VERSION)
	eq(db.minimapAngle, nil, "old key removed")
	eq(db.minimapIcon.minimapPos, 200, "old default band re-aligned")
	eq(db.minimapIcon.hide, nil, "non-boolean hide dropped")
	eq(db.gather["Copper Vein"].misses[71], 3, "string and numeric keys summed")
	eq(db.gather["Copper Vein"].gains[80], 1)
	eq(db.gather.bogus, nil); eq(db.gather[7], nil)
	eq(db.skinIds[299], true); eq(db.skinIds["300"], nil); eq(db.skinIds[301], nil)
	eq(db.enabled, true, "wrong type reset to default")
	-- Running again is a no-op on migrated data.
	db.minimapIcon.minimapPos = 215
	ns.LoadDB(db)
	eq(db.minimapIcon.minimapPos, 215, "already-migrated data stays put")
end)

test("ResetSettings restores options and keeps learned data", function()
	local db = ns.LoadDB({
		enabled = false,
		learnChat = true,
		showMinimapButton = false,
		debug = true,
		bannerFont = 14,
		bannerX = 40,
		bannerY = -20,
		minimapAngle = 15,
		minimapIcon = { minimapPos = 15, hide = true },
		gather = {
			["Mystery Herb"] = { misses = {}, gains = { [40] = 1 } },
		},
		customNodes = {
			["Mystery Herb"] = { orange = 40, yellow = 65, green = 90, grey = 140, prof = "herb" },
		},
	})
	db.bannerUnlocked = true
	ns.ResetSettings(db)
	eq(db.enabled, true)
	eq(db.learnChat, false)
	eq(db.showMinimapButton, true)
	eq(db.debug, false)
	eq(db.bannerFont, 18)
	eq(db.bannerUnlocked, false)
	eq(db.bannerX, 0)
	eq(db.bannerY, 80)
	eq(db.minimapAngle, nil, "old key removed")
	eq(db.minimapIcon.minimapPos, 200)
	eq(db.minimapIcon.hide, false)
	eq(db.gather["Mystery Herb"].gains[40], 1)
	eq(db.customNodes["Mystery Herb"].orange, 40)
end)

test("LoadDB migrates small text and clamps banner font", function()
	local small = ns.LoadDB({ version = 3, bannerSmall = true, bannerFont = 20 })
	eq(small.bannerFont, 12)
	eq(small.bannerSmall, nil)
	eq(small.version, ns.DB_VERSION)
	ns.LoadDB(small)
	eq(small.bannerFont, 12, "small text is not migrated twice")
	local huge = ns.LoadDB({ bannerFont = 99 })
	eq(huge.bannerFont, 32)
	local tiny = ns.LoadDB({ bannerFont = 3 })
	eq(tiny.bannerFont, 10)
end)

test("v8 default banner size shrinks once to the new default", function()
	local db = ns.LoadDB({ version = 8, bannerFont = 20 })
	eq(db.bannerFont, 18)
	ns.LoadDB(db)
	eq(db.bannerFont, 18, "not migrated twice")
	local chosen = ns.LoadDB({ version = 8, bannerFont = 22 })
	eq(chosen.bannerFont, 22, "a chosen size stays")
end)

test("LoadDB keeps banner position and locks the anchor", function()
	local db = ns.LoadDB({
		bannerUnlocked = true,
		bannerFont = 14,
		bannerX = 40,
		bannerY = -20,
	})
	eq(db.bannerUnlocked, false, "anchor does not stay unlocked across loads")
	eq(db.bannerFont, 14)
	eq(db.bannerX, 40)
	eq(db.bannerY, -20)
end)

test("customNodes validate, merge, and never overwrite builtins", function()
	local db = ns.LoadDB({
		customNodes = {
			["Mystery Herb"] = { orange = 40, yellow = 65, green = 90, grey = 140, prof = "herb", key = "Mystery Herb" },
			["Peacebloom"] = { orange = 99, yellow = 100, green = 101, grey = 102, prof = "herb", key = "Peacebloom" },
			bad = "nope",
			["Broken"] = { orange = 1, prof = "herb" },
			[12] = { orange = 1, yellow = 2, green = 3, grey = 4, prof = "mine" },
		},
	})
	eq(db.customNodes["Mystery Herb"].orange, 40)
	eq(db.customNodes["Mystery Herb"].green, 105, "old orange+50 green moves to the 65 percent step")
	eq(db.customNodes["Peacebloom"], nil, "builtin stripped from customNodes")
	eq(db.customNodes.bad, nil)
	eq(db.customNodes["Broken"], nil)
	eq(db.customNodes[12], nil)

	ns.ApplyCustomNodes(db.customNodes)
	local name, node = ns.ExactNode("Mystery Herb")
	eq(name, "Mystery Herb"); eq(node.orange, 40); eq(node.prof, "herb")
	eq(ns.ExactNode("Peacebloom"), "Peacebloom")
	eq(ns.LOOKUP["Peacebloom"], ns.NODES["Peacebloom"], "builtin LOOKUP untouched")

	-- LearnCustomNode: new name, then ratchet keeps lower orange; builtin blocked.
	freshDB()
	eq(ns.LearnCustomNode("Beta Ore", "mine", 80), true)
	eq(ns.db.customNodes["Beta Ore"].orange, 80)
	eq(ns.LOOKUP["Beta Ore"].orange, 80)
	eq(ns.LearnCustomNode("Beta Ore", "mine", 100), true)
	eq(ns.db.customNodes["Beta Ore"].orange, 80, "orange never raised on re-learn")
	eq(ns.LearnCustomNode("Beta Ore", "mine", 50), true)
	eq(ns.db.customNodes["Beta Ore"].orange, 50, "lower orange kept")
	eq(ns.LOOKUP["Beta Ore"].orange, 50)
	eq(ns.db.customNodes["Beta Ore"].green, 115, "learned green is the 65 percent step")
	eq(ns.LearnCustomNode("Peacebloom", "herb", 1), false)
	eq(ns.db.customNodes["Peacebloom"], nil)
	eq(ns.LOOKUP["Peacebloom"], ns.NODES["Peacebloom"])
end)

test("LoadDB moves a midpoint green to the 65 percent step", function()
	local db = ns.LoadDB({
		version = 6,
		customNodes = {
			["Midpoint Herb"] = { orange = 40, yellow = 65, green = 102, grey = 140, prof = "herb", key = "Midpoint Herb" },
		},
	})
	eq(db.version, ns.DB_VERSION)
	eq(db.customNodes["Midpoint Herb"].green, 105)
	ns.LoadDB(db)
	eq(db.customNodes["Midpoint Herb"].green, 105, "not migrated twice")
end)

test("NoteGatherResult keeps a lowered orange for a custom node", function()
	local db = freshDB()
	eq(ns.LearnCustomNode("Learned Herb", "herb", 60), true)
	local custom = ns.LOOKUP["Learned Herb"]
	ns.NoteGatherResult("Learned Herb", 50, true)
	eq(db.gather["Learned Herb"].gainedAt, 50)
	eq(db.gather["Learned Herb"].orangeSeen, 50)
	eq(ns.EffectiveOrange(custom, "Learned Herb"), 50)
	ns.NoteGatherResult("Learned Herb", 80, true)
	eq(db.gather["Learned Herb"].gainedAt, 80, "gainedAt still tracks the highest gain")
	eq(db.gather["Learned Herb"].gains[50], 1)
	eq(db.gather["Learned Herb"].orangeSeen, 50, "higher gain does not raise orangeSeen")
	eq(ns.EffectiveOrange(custom, "Learned Herb"), 50)
end)

test("built-in nodes ignore observations below the verified requirement", function()
	local db = freshDB()
	local khadgar = ns.NODES["Khadgar's Whisker"] -- 185
	ns.NoteGatherResult("Khadgar's Whisker", 125, true)
	eq(db.gather["Khadgar's Whisker"], nil, "a gain below 185 is not recorded")
	eq(ns.EffectiveOrange(khadgar, "Khadgar's Whisker"), 185)
	eq(ns.ObservedColor(125, khadgar, 185, "Khadgar's Whisker"), P.red)
	-- A real gain at the requirement is still recorded for the color.
	ns.NoteGatherResult("Khadgar's Whisker", 185, true)
	eq(db.gather["Khadgar's Whisker"].gains[185], 1)
	eq(db.gather["Khadgar's Whisker"].orangeSeen, nil)
end)

test("Khadgar's Whisker shows 185 and red at 125 even with stale learned data", function()
	local db = freshDB()
	db.gather["Khadgar's Whisker"] = {
		misses = { [125] = 5 },
		gains = { [125] = 3 },
		orangeSeen = 125,
		gainedAt = 125,
	}
	ns.RefreshSkills()
	ns.skills.herb = 125
	local title, color = ns.FormatNode("Khadgar's Whisker", ns.NODES["Khadgar's Whisker"])
	eq(title, "Khadgar's Whisker (125/185)")
	eq(color, P.red)
	db.gather["Khadgar's Whisker"] = nil
end)

test("v2 gainedAt below table orange seeds orangeSeen once", function()
	local saved = {
		version = 2,
		gather = {
			["skin:25"] = { misses = {}, gains = {}, gainedAt = 10 },
			["Copper Vein"] = { misses = {}, gains = {}, gainedAt = 50 },
		},
	}
	local db = ns.LoadDB(saved)
	eq(db.version, ns.DB_VERSION)
	eq(db.gather["skin:25"].orangeSeen, 10)
	eq(db.gather["Copper Vein"].orangeSeen, nil, "gainedAt above the table orange is not a floor")
	db.gather["skin:25"].orangeSeen = nil
	db.gather["skin:25"].gainedAt = 5
	ns.LoadDB(db)
	eq(db.version, ns.DB_VERSION)
	eq(db.gather["skin:25"].orangeSeen, nil, "a later load does not seed again")
end)

test("v10 drops built-in observations below the verified requirement", function()
	local saved = {
		version = 9,
		gather = {
			["Khadgar's Whisker"] = {
				misses = { [125] = 3, [200] = 1 },
				gains = { [125] = 1, [190] = 2 },
				orangeSeen = 125,
				gainedAt = 190,
			},
			["Mystery Herb"] = {
				misses = { [10] = 1 },
				gains = { [10] = 1 },
				orangeSeen = 10,
				gainedAt = 10,
			},
		},
		customNodes = {
			["Mystery Herb"] = { orange = 40, yellow = 65, green = 90, grey = 140, prof = "herb", key = "Mystery Herb" },
		},
	}
	local db = ns.LoadDB(saved)
	eq(db.version, ns.DB_VERSION)
	eq(db.gather["Khadgar's Whisker"].misses[125], nil)
	eq(db.gather["Khadgar's Whisker"].gains[125], nil)
	eq(db.gather["Khadgar's Whisker"].misses[200], 1)
	eq(db.gather["Khadgar's Whisker"].gains[190], 2)
	eq(db.gather["Khadgar's Whisker"].orangeSeen, nil)
	eq(db.gather["Khadgar's Whisker"].gainedAt, 190)
	eq(db.gather["Mystery Herb"].gains[10], 1, "custom observations stay")
	eq(db.gather["Mystery Herb"].orangeSeen, 10)
end)

-- Tooltip memory and cast snapshot -----------------------------------------------

local function fakeTip(text, store)
	return {
		TextLeft1 = {
			GetText = function()
				return store and store.text or text
			end,
			SetText = function(_, value)
				if store then
					store.text = value
				end
			end,
			SetTextColor = function() end,
		},
		GetName = function()
			return "GameTooltip"
		end,
		NumLines = function()
			return 1
		end,
		AddLine = function() end,
		IsShown = function()
			return true
		end,
		Show = function()
			if store then
				store.shows = (store.shows or 0) + 1
			end
		end,
	}
end

test("TooltipShowsName sees names through colors, our suffix and stacks", function()
	eq(ns.TooltipShowsName(fakeTip("Naxia Jera (86/83)"), "Naxia Jera"), true)
	eq(ns.TooltipShowsName(fakeTip("|cff40bf40Peacebloom|r"), "Peacebloom"), true)
	eq(ns.TooltipShowsName(fakeTip("Peacebloom (70/1)"), "Peacebloom"), true)
	eq(ns.TooltipShowsName(fakeTip("Peacebloom"), "Silverleaf"), false)
	eq(ns.TooltipShowsName(fakeTip("Peacebloom"), ""), false)
	eq(ns.TooltipShowsName(nil, "Peacebloom"), false)

	local hidden = fakeTip("Peacebloom")
	hidden.IsShown = function()
		return false
	end
	eq(ns.TooltipShowsName(hidden, "Peacebloom"), false, "hidden tooltips keep stale text")

	local stacked = fakeTip("Peacebloom")
	stacked.TextLeft2 = { GetText = function() return "Silverleaf" end }
	stacked.NumLines = function() return 2 end
	eq(ns.TooltipShowsName(stacked, "Silverleaf"), true, "stacked pins")
end)

test("stacked pins separated by |n are split and rewritten", function()
	freshDB()
	ns.RefreshSkills()
	local store = {}
	eq(ns.ApplyTooltip(fakeTip("Peacebloom|nSilverleaf", store), nil, true), true)
	eq(type(store.text), "string")
	eq(store.text:find("Peacebloom", 1, true) ~= nil, true)
	eq(store.text:find("Silverleaf", 1, true) ~= nil, true)
	eq(store.text:find("\n", 1, true) ~= nil, true)
	eq((store.shows or 0) > 0, true, "the tooltip reflows after a rewrite")
end)

test("TooltipShowsNode matches locale aliases to the same key", function()
	eq(ns.TooltipShowsNode(fakeTip("Friedensblume"), "Peacebloom"), true)
	eq(ns.TooltipShowsNode(fakeTip("Peacebloom (70/1)"), "Peacebloom"), true)
	eq(ns.TooltipShowsNode(fakeTip(ns.NODE_DISPLAY["Kingsblood"]), "Khadgar's Whisker"), false)
	eq(ns.TooltipShowsNode(fakeTip(ns.NODE_DISPLAY["Khadgar's Whisker"]), "Khadgar's Whisker"), true)
	eq(ns.TooltipShowsNode(nil, "Peacebloom"), false)
end)

test("FrameIsUnder walks parents without IsDescendantOf", function()
	local parent = {}
	local child = { GetParent = function() return parent end }
	eq(ns.FrameIsUnder(child, parent), true)
	eq(ns.FrameIsUnder(parent, parent), true)
	eq(ns.FrameIsUnder(child, {}), false)
	eq(ns.FrameIsUnder({}, {}), false)
	local noParent = { GetParent = function() return nil end }
	eq(ns.FrameIsUnder(noParent, parent), false)
end)

test("TooltipHasUnit tells units from world objects", function()
	local tip = fakeTip("Peacebloom")
	eq(ns.TooltipHasUnit(tip), false)
	tip.GetUnit = function()
		return "Player", "player"
	end
	eq(ns.TooltipHasUnit(tip), true)
	tip.GetUnit = function()
		return nil, "mouseover"
	end
	eq(ns.TooltipHasUnit(tip), false, "a mouseover token with no unit")
end)

test("TooltipOwnerIsWorld tells world and minimap from UI frames", function()
	local tip = fakeTip("Peacebloom")
	eq(ns.TooltipOwnerIsWorld(tip), true, "an unowned tooltip is world")
	tip.GetOwner = function()
		return {}
	end
	eq(ns.TooltipOwnerIsWorld(tip), false, "a UI frame is not world")
	local minimap = {}
	_G.Minimap = minimap
	tip.GetOwner = function()
		return minimap
	end
	eq(ns.TooltipOwnerIsWorld(tip), true, "the minimap is world")
	tip.GetOwner = function()
		return { GetParent = function() return minimap end }
	end
	eq(ns.TooltipOwnerIsWorld(tip), true, "a frame under the minimap is world")
	tip.GetOwner = function()
		return { IsForbidden = function() return true end }
	end
	eq(ns.TooltipOwnerIsWorld(tip), false, "a forbidden owner is never world")
	_G.Minimap = nil
end)

test("a unit name is never decorated or learned as a node", function()
	freshDB()
	ns.ForgetUnknownName()
	local node = { orange = 1, yellow = 26, green = 51, grey = 101, prof = "mine", key = "player" }
	ns.LOOKUP["player"] = node
	eq(ns.UnitNameExists("player"), true)
	eq(ns.ApplyTooltip(fakeTip("player"), nil, true), false, "a player name is not a node")
	eq(ns.RecentUnknownName(), nil, "a player name is not remembered")
	eq(ns.RegisterCustomNode("player", node), false)
	eq(ns.LearnCustomNode("player", "mine", 100), false)
	ns.LOOKUP["player"] = nil
end)

test("a node tooltip owned by a UI frame is skipped", function()
	freshDB()
	local tip = fakeTip("Peacebloom")
	tip.GetOwner = function()
		return {}
	end
	eq(ns.OnObjectTooltip(tip, nil), false)
end)

test("a unit tooltip owned by a UI frame is not skinned", function()
	freshDB()
	local calls = 0
	local tip = {
		GetOwner = function()
			return {}
		end,
		GetUnit = function()
			calls = calls + 1
			return "Player", "player"
		end,
	}
	ns.OnUnitTooltip(tip, nil)
	eq(calls, 0, "a UI-owned unit tooltip is skipped")
end)

test("ApplyTooltip skips frames that are not game tooltips", function()
	freshDB()
	local tip = {
		GetName = function() return "ShoppingTooltip1" end,
		NumLines = function() return 1 end,
	}
	local data = { lines = { { leftText = "Peacebloom" } } }
	eq(ns.ApplyTooltip(tip, data, true), false, "a frame without AddLine is skipped")
	eq(ns.RecentNodeKey("herb"), nil, "a skipped frame is not remembered")
end)

test("OnUnitTooltip skips frames without GetUnit", function()
	freshDB()
	ns.OnUnitTooltip({}, nil)
	eq(ns.RecentNodeKey("skin"), nil, "a frame without GetUnit is skipped")
end)

test("hovered node memory expires after 15 seconds", function()
	freshDB()
	now = 10000
	ns.ApplyTooltip(fakeTip("Peacebloom"), nil, true)
	eq(ns.RecentNodeKey("herb"), "Peacebloom")
	now = 10015
	eq(ns.RecentNodeKey("herb"), "Peacebloom", "exactly 15 seconds is still inside the window")
	now = 10016
	eq(ns.RecentNodeKey("herb"), nil)
	ns.ApplyTooltip(fakeTip("Solid Chest"), nil, true)
	eq(ns.RecentUnknownName(), "Solid Chest")
	now = now + 16
	eq(ns.RecentUnknownName(), nil)
end)

test("a known node cast does not save an earlier unmatched name", function()
	freshDB()
	now = 20000
	ns.ApplyTooltip(fakeTip("Solid Chest"), nil, true)
	eq(ns.RecentUnknownName(), "Solid Chest")
	ns.ApplyTooltip(fakeTip("Peacebloom"), nil, true)
	eq(ns.RecentUnknownName(), nil)
	eq(ns.RecentNodeKey("herb"), "Peacebloom")
	ns.OnGatherCastStart(2366)
	ns.OnGatherCastSucceeded(2366)
	eq(ns.db.customNodes["Solid Chest"], nil)
end)

test("unknown name is learned from the cast-start snapshot", function()
	freshDB()
	now = 30000
	ns.ApplyTooltip(fakeTip("Snapshot Herb"), nil, true)
	_G.GameTooltip = fakeTip("Snapshot Herb")
	ns.OnGatherCastStart(2366)
	-- Skill-up lands before success, and the tooltip moves on. Orange must
	-- stay the skill captured at start, and the name must stay Snapshot Herb.
	ns.skills.herb = 151
	ns.ApplyTooltip(fakeTip("Peacebloom"), nil, true)
	_G.GameTooltip = fakeTip("Peacebloom")
	eq(ns.RecentUnknownName(), nil)
	ns.OnGatherCastSucceeded(2366)
	eq(ns.db.customNodes["Snapshot Herb"].orange, 150)
	eq(ns.LOOKUP["Snapshot Herb"].orange, 150)
	eq(ns.db.customNodes["Peacebloom"], nil)
	-- Re-learning does not raise orange (existing LearnCustomNode rule).
	eq(ns.LearnCustomNode("Snapshot Herb", "herb", 200), true)
	eq(ns.db.customNodes["Snapshot Herb"].orange, 150)
end)

test("a stale name is not learned when the tooltip shows another object", function()
	freshDB()
	now = 40000
	-- A player on the minimap or a campfire was hovered last: remembered.
	ns.ApplyTooltip(fakeTip("Naxia Jera"), nil, true)
	eq(ns.RecentUnknownName(), "Naxia Jera")
	-- The gather cast starts with a different object under the cursor.
	_G.GameTooltip = fakeTip("Peacebloom")
	ns.OnGatherCastStart(2366)
	ns.OnGatherCastSucceeded(2366)
	eq(ns.db.customNodes["Naxia Jera"], nil)
	eq(ns.RecentUnknownName(), nil, "the stale name is forgotten")
end)

test("a stale known node is not attributed to a later gather", function()
	freshDB()
	now = 50000
	-- Hover Khadgar's Whisker, then move to a Kingsblood node and gather it.
	local display = ns.NODE_DISPLAY["Khadgar's Whisker"]
	ns.ApplyTooltip(fakeTip(display), nil, true)
	eq(ns.RecentNodeKey("herb"), "Khadgar's Whisker")
	_G.GameTooltip = fakeTip(ns.NODE_DISPLAY["Kingsblood"])
	ns.OnGatherCastStart(2366)
	ns.OnGatherCastSucceeded(2366)
	ns.skills.herb = 126
	eq(ns.NoteGatherSkill(), false, "the watch was not armed for the stale node")
	eq(ns.db.gather["Khadgar's Whisker"], nil)
end)

test("a known node is attributed when its name is still on the tooltip", function()
	freshDB()
	now = 60000
	professionSkill = 185
	local display = ns.NODE_DISPLAY["Khadgar's Whisker"]
	ns.ApplyTooltip(fakeTip(display), nil, true)
	_G.GameTooltip = fakeTip(display)
	ns.OnGatherCastStart(2366)
	ns.OnGatherCastSucceeded(2366)
	professionSkill = 186
	eq(ns.NoteGatherSkill(), true)
	eq(ns.db.gather["Khadgar's Whisker"].gains[185], 1)
	eq(ns.db.gather["Khadgar's Whisker"].orangeSeen, nil)
	professionSkill = 150
end)

-- Runs the cast events for one herb gather with `targetName` as the SENT
-- target (nil simulates a cast with no readable target).
local function armLootCast(targetName)
	ns.ForgetUnknownName()
	ns.NoteCastTarget(targetName)
	ns.OnGatherCastStart(2366)
	ns.OnGatherCastSucceeded(2366)
end

test("loot learning learns a node from the loot source name", function()
	freshDB()
	now = 100000
	professionSkill = 150
	ns.RefreshSkills()
	armLootCast(nil)
	resetLoot({ { 7, 9 } }, "GameObject-0-1-2", "Source Only Herb")
	ns.OnLootReady()
	eq(ns.db.customNodes["Source Only Herb"].orange, 150)
	eq(ns.LOOKUP["Source Only Herb"].prof, "herb")
end)

test("loot learning falls back to the cast target name", function()
	freshDB()
	now = 101000
	armLootCast("Cast Target Herb")
	resetLoot({ { 7, 9 } }, "GameObject-0-1-3", nil)
	ns.OnLootReady()
	eq(ns.db.customNodes["Cast Target Herb"].orange, 150)
end)

test("loot learning prefers the source name over the cast target", function()
	freshDB()
	now = 102000
	armLootCast("Wrong Cast Name")
	resetLoot({ { 7, 9 } }, "GameObject-0-1-4", "Right Source Name")
	ns.OnLootReady()
	eq(ns.db.customNodes["Right Source Name"].orange, 150)
	eq(ns.db.customNodes["Wrong Cast Name"], nil)
end)

test("loot learning ignores another profession's loot", function()
	freshDB()
	now = 103000
	armLootCast("Herb From Ore")
	resetLoot({ { 7, 7 } }, "GameObject-0-1-5", "Herb From Ore")
	ns.OnLootReady()
	eq(ns.db.customNodes["Herb From Ore"], nil)
end)

test("loot learning ignores a source that is not a game object", function()
	freshDB()
	now = 104000
	armLootCast("Chest Herb")
	resetLoot({ { 7, 9 } }, "Item-0-1-6", "Chest Herb")
	ns.OnLootReady()
	eq(ns.db.customNodes["Chest Herb"], nil)
end)

test("loot learning expires before an unrelated loot window", function()
	freshDB()
	now = 105000
	armLootCast(nil)
	now = now + 4
	resetLoot({ { 7, 9 } }, "GameObject-0-1-7", "Late Herb")
	ns.OnLootReady()
	eq(ns.db.customNodes["Late Herb"], nil)
end)

test("ForgetCustomNode removes a learned node and its observations", function()
	local db = freshDB()
	eq(ns.LearnCustomNode("Naxia Jera", "mine", 83), true)
	db.gather["Naxia Jera"] = { misses = {}, gains = {} }
	eq(ns.ExactNode("Naxia Jera") ~= nil, true)
	eq(ns.ForgetCustomNode("naxia jera"), "Naxia Jera")
	eq(db.customNodes["Naxia Jera"], nil)
	eq(ns.LOOKUP["Naxia Jera"], nil)
	eq(db.gather["Naxia Jera"], nil)
	eq(ns.ForgetCustomNode("Naxia Jera"), nil)
	eq(ns.ForgetCustomNode("Peacebloom"), nil, "a builtin is never removed")
	eq(ns.LOOKUP["Peacebloom"], ns.NODES["Peacebloom"])
end)

-- Summary --------------------------------------------------------------------------

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	os.exit(1)
end
