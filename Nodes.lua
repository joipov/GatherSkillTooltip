local _, ns = ...

-- Herb/ore node lookup, difficulty colors and the learned-observation model
-- (db.gather). Pure Lua apart from ns.db/ns.skills reads, so the color and
-- observation functions run under plain Lua 5.1 in tests/run.lua.

local COLOR_PREFIX = ns.COLOR_PREFIX

-- A node is treated as grey once this many misses at one skill level have
-- been recorded without a single gain.
local MISS_GREY = 20
-- Minimum observations before the gain rate overrides the table color.
local RATE_TRIES = 4

-- `orange` is the effective orange threshold (see EffectiveOrange); the
-- remaining thresholds come from the static band.
function ns.DifficultyColor(skill, node, orange)
	local yellow, green, grey = node.yellow, node.green, node.grey
	if not yellow or not green or not grey then
		return nil
	end
	if skill < (orange or node.orange) then
		return COLOR_PREFIX.red
	elseif skill < yellow then
		return COLOR_PREFIX.orange
	elseif skill < green then
		return COLOR_PREFIX.yellow
	elseif skill < grey then
		return COLOR_PREFIX.green
	end
	return COLOR_PREFIX.grey
end

-- Decorated lines (colors, textures, or a skill suffix) are parsed on every
-- minimap frame while the cursor rests on a pin. Their result depends only on
-- LOOKUP, so remember it by raw text and forget the memo whenever a locale
-- alias or custom node changes. Plain names stay uncached: a lookup is cheap.
local parseCache = {}
local parseCacheSize = 0
local PARSE_CACHE_MAX = 256

function ns.InvalidateNodeCache()
	parseCache = {}
	parseCacheSize = 0
end

-- Returns (name, node) for a known object name, or (nil, nil, cleaned) when
-- the cleaned text is unknown, or nothing for empty input.
function ns.ExactNode(text)
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
	local cached = parseCache[text]
	if cached then
		return cached.name, cached.node, cached.cleaned
	end
	local cleaned = ns.NormalizeName(text)
	if not cleaned or cleaned == "" then
		return nil
	end
	local node = lookup[cleaned]
	if parseCacheSize >= PARSE_CACHE_MAX then
		ns.InvalidateNodeCache()
	end
	parseCacheSize = parseCacheSize + 1
	parseCache[text] = { name = node and cleaned, node = node, cleaned = cleaned }
	if node then
		return cleaned, node
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

-- Observations -----------------------------------------------------------------

local function CountAt(bucket, skill)
	local n = bucket[skill]
	if type(n) ~= "number" then
		return 0
	end
	return n
end

local function GatherObs(key)
	local db = ns.db
	if not db or not key then
		return nil
	end
	return db.gather[key]
end

local function GainedAtOrAbove(obs, skill)
	return type(obs.gainedAt) == "number" and obs.gainedAt >= skill
end

-- Static orange for a learned-data key: a built-in node, a skinning band, or
-- a custom node. Used to decide whether a gain lowers orangeSeen. Not the
-- effective (already lowered) threshold.
function ns.TableOrange(key)
	local node = ns.NODE_BY_KEY[key]
	if node and type(node.orange) == "number" then
		return node.orange
	end
	if type(key) ~= "string" then
		return nil
	end
	local level = key:match("^skin:(%d+)$")
	if level and ns.SkinningOrange then
		return ns.SkinningOrange(tonumber(level))
	end
	local custom = ns.db and ns.db.customNodes and ns.db.customNodes[key]
	if type(custom) == "table" and type(custom.orange) == "number" then
		return custom.orange
	end
	return nil
end

-- The orange threshold after applying learned data. orangeSeen is the lowest
-- skill-up recorded below the table orange and only ever decreases.
-- gainedAt is the highest gain and is not used here. Returns a number, never
-- a new table.
function ns.EffectiveOrange(band, key)
	-- Built-in nodes use the verified Forever table. Learned lowering is only
	-- for names the table does not know (custom nodes and skinning bands).
	if ns.NODES[key] then
		return band.orange
	end
	local obs = GatherObs(key)
	local seen = obs and obs.orangeSeen
	if type(seen) ~= "number" or seen >= band.orange then
		return band.orange
	end
	return seen
end

function ns.ColorFromRate(gains, misses)
	local total = gains + misses
	if total < RATE_TRIES or gains <= 0 then
		return nil
	end
	local rate = gains / total
	if rate >= 0.75 then
		return COLOR_PREFIX.orange
	end
	if rate >= 0.4 then
		return COLOR_PREFIX.yellow
	end
	return COLOR_PREFIX.green
end

function ns.ObservedColor(skill, band, orange, key)
	-- A built-in node cannot be gathered below its verified requirement, so
	-- learned observations must not turn that red into another color.
	if ns.NODES[key] and skill < band.orange then
		return COLOR_PREFIX.red
	end
	local color = ns.DifficultyColor(skill, band, orange)
	local obs = GatherObs(key)
	if not obs then
		return color
	end
	local gains = CountAt(obs.gains, skill)
	local misses = CountAt(obs.misses, skill)
	local rated = ns.ColorFromRate(gains, misses)
	if rated then
		color = rated
	end
	if misses >= MISS_GREY and gains == 0 and not GainedAtOrAbove(obs, skill) then
		color = COLOR_PREFIX.grey
	end
	if GainedAtOrAbove(obs, skill) and color == COLOR_PREFIX.grey then
		color = COLOR_PREFIX.green
	end
	return color
end

-- Records one gather attempt at `skill` for `key` (node key or "skin:N").
function ns.NoteGatherResult(key, skill, gained)
	local db = ns.db
	if not db or not key or type(skill) ~= "number" then
		return
	end
	-- Observations below a built-in node's verified requirement cannot be real
	-- for that node (a stale hover or a misattributed gather). Ignore them so
	-- they cannot lower the requirement or recolor the node.
	local builtin = ns.NODES[key]
	if builtin and type(builtin.orange) == "number" and skill < builtin.orange then
		return
	end
	local obs = db.gather[key]
	if not obs then
		obs = { misses = {}, gains = {} }
		db.gather[key] = obs
	end
	if gained then
		obs.gains[skill] = CountAt(obs.gains, skill) + 1
		if not obs.gainedAt or skill > obs.gainedAt then
			obs.gainedAt = skill
		end
		local orange = ns.TableOrange(key)
		if type(orange) == "number" and skill < orange
			and (type(obs.orangeSeen) ~= "number" or skill < obs.orangeSeen) then
			obs.orangeSeen = skill
		end
		return
	end
	obs.misses[skill] = CountAt(obs.misses, skill) + 1
end

-- Returns (title, colorPrefix) for a known node, or nil when the node's
-- profession is disabled, unknown to the player or nothing would be shown.
function ns.FormatNode(name, node)
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
	ns.EnsureSkills()
	local skill = ns.skills[node.prof]
	if type(skill) ~= "number" then
		return nil
	end
	local orange = ns.EffectiveOrange(node, node.key)
	return TitleLine(name, skill, orange), ns.ObservedColor(skill, node, orange, node.key)
end

-- Custom nodes (learned from gather-after-hover) --------------------------------

-- Inserts or replaces a LOOKUP entry from a validated customNodes record.
-- Built-in English names and locale aliases that point at ns.NODES always win.
function ns.RegisterCustomNode(name, entry)
	if type(name) ~= "string" or name == "" or type(entry) ~= "table" then
		return false
	end
	if ns.NODES[name] then
		return false
	end
	-- A unit name is never a node. This also keeps a stale custom node that
	-- was learned from a player name from registering again on load.
	if ns.UnitNameExists(name) then
		return false
	end
	local lookup = ns.LOOKUP
	if not lookup then
		return false
	end
	local existing = lookup[name]
	if existing and ns.NODES[existing.key] then
		return false
	end
	if type(entry.orange) ~= "number"
		or type(entry.yellow) ~= "number"
		or type(entry.green) ~= "number"
		or type(entry.grey) ~= "number"
		or (entry.prof ~= "herb" and entry.prof ~= "mine") then
		return false
	end
	lookup[name] = {
		orange = entry.orange,
		yellow = entry.yellow,
		green = entry.green,
		grey = entry.grey,
		prof = entry.prof,
		key = (type(entry.key) == "string" and entry.key ~= "" and entry.key) or name,
	}
	ns.InvalidateNodeCache()
	return true
end

-- Merges SavedVariables customNodes into LOOKUP after built-ins and locale
-- aliases so static Forever seeds always win over a custom overwrite.
function ns.ApplyCustomNodes(customNodes)
	if type(customNodes) ~= "table" then
		return
	end
	for name, entry in pairs(customNodes) do
		ns.RegisterCustomNode(name, entry)
	end
end

-- Removes a learned node by name (case-insensitive) and its gather
-- observations. Built-in names and locale aliases are never removed.
-- Returns the stored name when something was removed.
function ns.ForgetCustomNode(name)
	if type(name) ~= "string" then
		return nil
	end
	local wanted = name:match("^%s*(.-)%s*$")
	if wanted == "" then
		return nil
	end
	local db = ns.db
	if not db or type(db.customNodes) ~= "table" then
		return nil
	end
	local lower = wanted:lower()
	local key
	for candidate in pairs(db.customNodes) do
		if type(candidate) == "string" and candidate:lower() == lower then
			key = candidate
			break
		end
	end
	if not key then
		return nil
	end
	if ns.NODES and ns.NODES[key] then
		return nil
	end
	local node = ns.LOOKUP and ns.LOOKUP[key]
	local aliased = node and ns.NODES and ns.NODES[node.key]
	db.customNodes[key] = nil
	if ns.LOOKUP and not aliased then
		ns.LOOKUP[key] = nil
	end
	if type(db.gather) == "table" and not aliased then
		db.gather[key] = nil
	end
	ns.InvalidateNodeCache()
	return key
end

-- Persists a newly gathered unknown herb/ore and merges it into LOOKUP.
-- Keeps the lower orange if the name was already learned. Returns true when
-- LOOKUP was updated.
function ns.LearnCustomNode(name, prof, skill)
	if type(name) ~= "string" or name == "" then
		return false
	end
	if prof ~= "herb" and prof ~= "mine" then
		return false
	end
	if type(skill) ~= "number" then
		return false
	end
	if ns.NODES[name] then
		return false
	end
	if ns.UnitNameExists(name) then
		return false
	end
	local lookup = ns.LOOKUP
	local existing = lookup and lookup[name]
	if existing and ns.NODES[existing.key] then
		return false
	end
	local db = ns.db
	if not db then
		return false
	end
	db.customNodes = type(db.customNodes) == "table" and db.customNodes or {}
	local prev = db.customNodes[name]
	local orange = skill
	if prev and type(prev.orange) == "number" and prev.orange < orange then
		orange = prev.orange
	end
	if existing and type(existing.orange) == "number" and existing.orange < orange then
		orange = existing.orange
	end
	local yellow = orange + 25
	local grey = orange + 100
	local entry = {
		orange = orange,
		yellow = yellow,
		green = ns.GreenSkill(yellow, grey),
		grey = grey,
		prof = prof,
		key = name,
	}
	db.customNodes[name] = entry
	if not ns.RegisterCustomNode(name, entry) then
		return false
	end
	local L = ns.L
	if ns.LearnChat and L and L.LEARNED_NODE then
		ns.LearnChat(L.LEARNED_NODE:format(name, orange))
	end
	return true
end
