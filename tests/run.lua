-- Unit tests for the pure parts of GatherSkillTooltip (TOOL-005).
-- Plain Lua 5.1 / LuaJIT, no game client:
--   luajit tests/run.lua      (from the repository root)
--   lua5.1 tests/run.lua
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
function GetProfessions()
	return 1
end
function GetProfessionInfo(index)
	if index ~= 1 then
		return
	end
	-- name, icon, skill, max, abilities, offset, skillLine, modifier
	return "Herbalism", 0, 150, 225, 0, 0, 182, 0
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
	eq(copper.green, 50, "copper turns green at 50")
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
	db.gather["Tin Vein"] = { misses = {}, gains = {}, orangeSeen = 60 }
	eq(ns.EffectiveOrange(tin, "Tin Vein"), 60)
	db.gather["Tin Vein"].orangeSeen = 70
	eq(ns.EffectiveOrange(tin, "Tin Vein"), 65, "never raised above the table value")
	-- gainedAt is the highest gain and must not move the threshold.
	db.gather["Tin Vein"].orangeSeen = 60
	db.gather["Tin Vein"].gainedAt = 90
	eq(ns.EffectiveOrange(tin, "Tin Vein"), 60)
end)

test("NoteGatherResult and ObservedColor", function()
	local db = freshDB()
	local node = ns.NODES["Copper Vein"] -- 1/25/50/100
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
	eq(db.version, 4)
	eq(db.enabled, true)
	eq(db.learnChat, false)
	eq(db.minimapAngle, 200)
	eq(db.bannerFont, 20)
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
	eq(db.version, 4)
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

test("ResetSettings restores options and keeps learned data", function()
	local db = ns.LoadDB({
		enabled = false,
		learnChat = true,
		showMinimapButton = true,
		debug = true,
		bannerFont = 14,
		bannerX = 40,
		bannerY = -20,
		minimapAngle = 15,
		minimapIcon = { minimapPos = 15, hide = false },
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
	eq(db.showMinimapButton, false)
	eq(db.debug, false)
	eq(db.bannerFont, 20)
	eq(db.bannerUnlocked, false)
	eq(db.bannerX, 0)
	eq(db.bannerY, 80)
	eq(db.minimapAngle, 200)
	eq(db.minimapIcon.minimapPos, 200)
	eq(db.minimapIcon.hide, true)
	eq(db.gather["Mystery Herb"].gains[40], 1)
	eq(db.customNodes["Mystery Herb"].orange, 40)
end)

test("LoadDB migrates small text and clamps banner font", function()
	local small = ns.LoadDB({ version = 3, bannerSmall = true, bannerFont = 20 })
	eq(small.bannerFont, 12)
	eq(small.bannerSmall, nil)
	eq(small.version, 4)
	ns.LoadDB(small)
	eq(small.bannerFont, 12, "small text is not migrated twice")
	local huge = ns.LoadDB({ bannerFont = 99 })
	eq(huge.bannerFont, 32)
	local tiny = ns.LoadDB({ bannerFont = 3 })
	eq(tiny.bannerFont, 10)
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
	eq(ns.LearnCustomNode("Peacebloom", "herb", 1), false)
	eq(ns.db.customNodes["Peacebloom"], nil)
	eq(ns.LOOKUP["Peacebloom"], ns.NODES["Peacebloom"])
end)

test("NoteGatherResult keeps a lowered orange after a higher gain", function()
	local db = freshDB()
	local tin = ns.NODES["Tin Vein"] -- orange 65
	ns.NoteGatherResult("Tin Vein", 60, true)
	eq(db.gather["Tin Vein"].gainedAt, 60)
	eq(db.gather["Tin Vein"].orangeSeen, 60)
	eq(ns.EffectiveOrange(tin, "Tin Vein"), 60)
	ns.NoteGatherResult("Tin Vein", 80, true)
	eq(db.gather["Tin Vein"].gainedAt, 80, "gainedAt still tracks the highest gain")
	eq(db.gather["Tin Vein"].gains[60], 1)
	eq(db.gather["Tin Vein"].orangeSeen, 60, "higher gain does not raise orangeSeen")
	eq(ns.EffectiveOrange(tin, "Tin Vein"), 60)
end)

test("v2 gainedAt below table orange seeds orangeSeen once", function()
	local saved = {
		version = 2,
		gather = {
			["Tin Vein"] = { misses = {}, gains = {}, gainedAt = 60 },
			["Copper Vein"] = { misses = {}, gains = {}, gainedAt = 50 },
		},
	}
	local db = ns.LoadDB(saved)
	eq(db.version, 4)
	eq(db.gather["Tin Vein"].orangeSeen, 60)
	eq(db.gather["Copper Vein"].orangeSeen, nil, "gainedAt above the table orange is not a floor")
	db.gather["Tin Vein"].orangeSeen = nil
	db.gather["Tin Vein"].gainedAt = 40
	ns.LoadDB(db)
	eq(db.version, 4)
	eq(db.gather["Tin Vein"].orangeSeen, nil, "a later load does not seed again")
end)

-- Tooltip memory and cast snapshot -----------------------------------------------

local function fakeTip(text)
	return {
		TextLeft1 = {
			GetText = function()
				return text
			end,
			SetText = function() end,
			SetTextColor = function() end,
		},
		GetName = function()
			return "GameTooltip"
		end,
		NumLines = function()
			return 1
		end,
		AddLine = function() end,
	}
end

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
	ns.OnGatherCastStart(2366)
	-- Skill-up lands before success, and the tooltip moves on. Orange must
	-- stay the skill captured at start, and the name must stay Snapshot Herb.
	ns.skills.herb = 151
	ns.ApplyTooltip(fakeTip("Peacebloom"), nil, true)
	eq(ns.RecentUnknownName(), nil)
	ns.OnGatherCastSucceeded(2366)
	eq(ns.db.customNodes["Snapshot Herb"].orange, 150)
	eq(ns.LOOKUP["Snapshot Herb"].orange, 150)
	eq(ns.db.customNodes["Peacebloom"], nil)
	-- Re-learning does not raise orange (existing LearnCustomNode rule).
	eq(ns.LearnCustomNode("Snapshot Herb", "herb", 200), true)
	eq(ns.db.customNodes["Snapshot Herb"].orange, 150)
end)

-- Summary --------------------------------------------------------------------------

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	os.exit(1)
end
