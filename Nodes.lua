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
	local cleaned = ns.NormalizeName(text)
	if not cleaned or cleaned == "" then
		return nil
	end
	local node = lookup[cleaned]
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

-- The orange threshold after applying learned data: a recorded skill-up at a
-- lower skill than the table value lowers it. Returns a number, never a new
-- table (PERF-004).
function ns.EffectiveOrange(band, key)
	local obs = GatherObs(key)
	if not obs or type(obs.gainedAt) ~= "number" or obs.gainedAt >= band.orange then
		return band.orange
	end
	return obs.gainedAt
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
