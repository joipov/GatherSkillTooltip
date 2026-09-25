-- Unit tests for the pure parts of GatherSkillTooltip (TOOL-005).
-- Plain Lua 5.1 / LuaJIT, no game client:
--   luajit tests/run.lua      (from the repository root)
--   lua5.1 tests/run.lua
-- Files that touch the WoW API at load (Events.lua, Options.lua, ...) are
-- not loaded here; they are covered by the in-game checklist in CODE_AUDIT.md.

local root = (arg and arg[0] or "tests/run.lua"):match("^(.*)[/\\]tests[/\\]") or "."

-- The few globals the loaded files bind at load time.
issecretvalue = function() return false end
canaccessvalue = function() return true end
issecrettable = function() return false end
canaccesstable = function() return true end
C_Spell = {}
C_TradeSkillUI = {}

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
load("Skinning.lua")

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
	eq(copper.key, "Copper Vein", "lexically smallest name wins")
	eq(ns.NODE_BY_KEY["Copper Vein"], copper)
	eq(ns.NODE_BY_KEY["Poor Copper Vein"], nil)
	eq(ns.NODE_BY_KEY["Peacebloom"], ns.NODES["Peacebloom"])
end)

test("RegisterLocale overlays strings and adds aliases without touching NODES", function()
	eq(ns.L.EXAMPLE_HERB, "Friedensblume")
	eq(ns.LOOKUP["Friedensblume"], ns.NODES["Peacebloom"])
	eq(ns.LOOKUP["Peacebloom"], ns.NODES["Peacebloom"])
	eq(ns.NODES["Friedensblume"], nil)
end)

test("GATHER_SPELLS and TRACKING_SPELLS", function()
	eq(ns.GATHER_SPELLS[2366], "herb")
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

test("DifficultyColor thresholds", function()
	local node = ns.NODES["Earthroot"] -- 15/40/65/115
	eq(ns.DifficultyColor(14, node), P.red)
	eq(ns.DifficultyColor(15, node), P.orange)
	eq(ns.DifficultyColor(39, node), P.orange)
	eq(ns.DifficultyColor(40, node), P.yellow)
	eq(ns.DifficultyColor(65, node), P.green)
	eq(ns.DifficultyColor(115, node), P.grey)
	eq(ns.DifficultyColor(10, node, 5), P.orange, "effective orange overrides table")
	eq(ns.DifficultyColor(10, { orange = 1 }), nil, "incomplete band")
end)

test("ColorFromRate thresholds", function()
	eq(ns.ColorFromRate(1, 2), nil, "fewer than RATE_TRIES observations")
	eq(ns.ColorFromRate(0, 10), nil, "no gains")
	eq(ns.ColorFromRate(3, 1), P.orange)
	eq(ns.ColorFromRate(2, 2), P.yellow)
	eq(ns.ColorFromRate(1, 3), P.green)
end)

test("EffectiveOrange lowers the threshold from learned gains", function()
	local db = freshDB()
	local node = ns.NODES["Copper Vein"] -- orange 1
	eq(ns.EffectiveOrange(node, node.key), 1)
	local tin = ns.NODES["Tin Vein"] -- orange 65
	db.gather["Tin Vein"] = { misses = {}, gains = {}, gainedAt = 60 }
	eq(ns.EffectiveOrange(tin, "Tin Vein"), 60)
	db.gather["Tin Vein"].gainedAt = 70
	eq(ns.EffectiveOrange(tin, "Tin Vein"), 65, "never raised above the table value")
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
	eq(a.orange, 125); eq(a.yellow, 150); eq(a.green, 175); eq(a.grey, 225)
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
	eq(db.version, 2)
	eq(db.enabled, true)
	eq(db.learnChat, false)
	eq(db.minimapAngle, 200)
	eq(type(db.gather), "table"); eq(type(db.skinIds), "table"); eq(type(db.minimapIcon), "table")
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
	eq(db.version, 2)
	eq(db.minimapAngle, 200, "old default angle moved")
	eq(db.minimapIcon.minimapPos, 200, "old default band re-aligned")
	eq(db.minimapIcon.hide, nil, "non-boolean hide dropped")
	eq(db.gather["Copper Vein"].misses[71], 3, "string and numeric keys summed")
	eq(db.gather["Copper Vein"].gains[80], 1)
	eq(db.gather.bogus, nil); eq(db.gather[7], nil)
	eq(db.skinIds[299], true); eq(db.skinIds["300"], nil); eq(db.skinIds[301], nil)
	eq(db.enabled, true, "wrong type reset to default")
	-- Running again is a no-op on migrated data.
	db.minimapAngle = 220
	db.minimapIcon.minimapPos = 215
	ns.LoadDB(db)
	eq(db.minimapAngle, 220, "v2 data not migrated again")
	eq(db.minimapIcon.minimapPos, 215)
end)

-- Summary --------------------------------------------------------------------------

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	os.exit(1)
end
