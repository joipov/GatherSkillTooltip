local _, ns = ...

-- SavedVariables: defaults, one-time migrations and load-time validation.
-- Everything here is plain Lua so it can be exercised by tests/run.lua.

local defaults = {
	enabled = true,
	herbalism = true,
	mining = true,
	skinning = true,
	showCurrent = true,
	showRequired = true,
	color = true,
	learnChat = false,
	warnTracking = true,
	warnTrain = true,
	showMinimapButton = true,
	minimapAngle = 200,
	bannerFont = 20,
	bannerX = 0,
	bannerY = 80,
	debug = false,
}

-- Option keys only. Learned gather data is not in this table.
ns.defaults = defaults
ns.DB_DEFAULTS = defaults

-- Bump when a one-time migration is added to MigrateDB.
local DB_VERSION = 6

local BANNER_FONT_MIN = 10
local BANNER_FONT_MAX = 32

function ns.ClampBannerFont(size)
	if type(size) ~= "number" then
		return defaults.bannerFont
	end
	size = math.floor(size + 0.5)
	if size < BANNER_FONT_MIN then
		return BANNER_FONT_MIN
	end
	if size > BANNER_FONT_MAX then
		return BANNER_FONT_MAX
	end
	return size
end

-- Applies defaults and resets any option whose type no longer matches its
-- default (all options are booleans or numbers), so a corrupted or hand-edited
-- SavedVariables file recovers instead of erroring later (CQ-005).
local function CopyDefaults(db)
	for key, value in pairs(defaults) do
		if type(db[key]) ~= type(value) then
			db[key] = value
		end
	end
	return db
end

-- Converts legacy string keys ("71") in a count bucket to numeric keys,
-- summing when both forms exist.
local function NumericKeys(bucket)
	local fixed = {}
	for key, count in pairs(bucket) do
		local skill = tonumber(key)
		if skill and type(count) == "number" then
			fixed[skill] = (fixed[skill] or 0) + count
		end
	end
	return fixed
end

local function ValidateGather(gather)
	for key, obs in pairs(gather) do
		if type(key) ~= "string" or type(obs) ~= "table" then
			gather[key] = nil
		else
			obs.misses = type(obs.misses) == "table" and obs.misses or {}
			obs.gains = type(obs.gains) == "table" and obs.gains or {}
			if type(obs.gainedAt) ~= "number" then
				obs.gainedAt = nil
			end
			if type(obs.orangeSeen) ~= "number" then
				obs.orangeSeen = nil
			end
		end
	end
end

local function ValidateSkinIds(skinIds)
	for key, value in pairs(skinIds) do
		if type(key) ~= "number" or type(value) ~= "boolean" then
			skinIds[key] = nil
		end
	end
end

local function ValidateMinimapIcon(icon)
	if type(icon.minimapPos) ~= "number" then
		icon.minimapPos = nil
	end
	if type(icon.hide) ~= "boolean" then
		icon.hide = nil
	end
end

-- Player-learned herb/ore names from gather-after-hover. Built-in English
-- names in ns.NODES always win and are stripped if they appear here.
local function ValidateCustomNodes(customNodes)
	local nodes = ns.NODES
	for key, entry in pairs(customNodes) do
		if type(key) ~= "string" or key == "" or type(entry) ~= "table" then
			customNodes[key] = nil
		elseif nodes and nodes[key] then
			customNodes[key] = nil
		elseif type(entry.orange) ~= "number"
			or type(entry.yellow) ~= "number"
			or type(entry.green) ~= "number"
			or type(entry.grey) ~= "number"
			or (entry.prof ~= "herb" and entry.prof ~= "mine") then
			customNodes[key] = nil
		else
			if type(entry.key) ~= "string" or entry.key == "" then
				entry.key = key
			end
		end
	end
end

-- One-time migrations keyed on db.version (CQ-004, ARCH-006). Runs before
-- validation so legacy shapes are converted rather than discarded.
local function MigrateDB(db)
	local version = type(db.version) == "number" and db.version or 1
	if version < 2 then
		-- 1.x: the default fallback-button angle moved from 220 to 200.
		if db.minimapAngle == 220 then
			db.minimapAngle = 200
		end
		-- 1.x: LibDBIcon positions in the old 210-220 default band were
		-- re-aligned with minimapAngle on every load; do it once here.
		if type(db.minimapIcon) == "table" then
			local pos = db.minimapIcon.minimapPos
			if type(pos) == "number" and pos >= 210 and pos <= 220 then
				db.minimapIcon.minimapPos = db.minimapAngle
			end
		end
		-- 1.x: early builds stored skill counts under string keys.
		if type(db.gather) == "table" then
			for _, obs in pairs(db.gather) do
				if type(obs) == "table" then
					if type(obs.misses) == "table" then
						obs.misses = NumericKeys(obs.misses)
					end
					if type(obs.gains) == "table" then
						obs.gains = NumericKeys(obs.gains)
					end
				end
			end
		end
	end
	if version < 3 then
		-- 2.0.x stored the lowered orange threshold in gainedAt, which is also
		-- the highest gain. Seed orangeSeen once from a gainedAt that is still
		-- below the table orange (CQ-102). A later load does not seed again.
		if type(db.gather) == "table" and ns.TableOrange then
			for key, obs in pairs(db.gather) do
				if type(obs) == "table" and type(obs.orangeSeen) ~= "number" then
					local orange = ns.TableOrange(key)
					if type(obs.gainedAt) == "number" and type(orange) == "number" and obs.gainedAt < orange then
						obs.orangeSeen = obs.gainedAt
					end
				end
			end
		end
	end
	if version < 4 then
		-- The short-lived small-text checkbox. 12 is GameFontNormal.
		if db.bannerSmall == true then
			db.bannerFont = 12
		end
		db.bannerSmall = nil
	end
	if version < 5 then
		-- The button used to default off, and that false was written into
		-- saved variables. Turn it on once. A later choice stays put.
		db.showMinimapButton = true
	end
	if version < 6 then
		-- Learned nodes stored green as orange + 50. The client turns a node
		-- green at the midpoint of yellow and grey.
		if type(db.customNodes) == "table" and ns.GreenSkill then
			for _, entry in pairs(db.customNodes) do
				if type(entry) == "table"
					and type(entry.orange) == "number"
					and entry.yellow == entry.orange + 25
					and entry.green == entry.orange + 50
					and entry.grey == entry.orange + 100 then
					entry.green = ns.GreenSkill(entry.yellow, entry.grey)
				end
			end
		end
	end
	db.version = DB_VERSION
end

-- Puts option keys back to default. Learned herbs, ores, and skinning stay.
function ns.ResetSettings(db)
	if type(db) ~= "table" then
		return
	end
	for key, value in pairs(defaults) do
		db[key] = value
	end
	db.bannerUnlocked = false
	if type(db.minimapIcon) == "table" then
		db.minimapIcon.minimapPos = db.minimapAngle
		db.minimapIcon.hide = not db.showMinimapButton
	end
end

-- Returns the validated, migrated database table for `saved` (the raw
-- SavedVariables value, possibly nil).
function ns.LoadDB(saved)
	local db = type(saved) == "table" and saved or {}
	MigrateDB(db)
	CopyDefaults(db)
	db.bannerFont = ns.ClampBannerFont(db.bannerFont)
	-- The unlock checkbox is session-only, same as LootRollMover's anchor.
	-- A reload locks the banner; bannerX and bannerY are what persist.
	db.bannerUnlocked = false
	for _, key in ipairs({ "gather", "skinIds", "minimapIcon", "customNodes" }) do
		if type(db[key]) ~= "table" then
			db[key] = {}
		end
	end
	ValidateGather(db.gather)
	ValidateSkinIds(db.skinIds)
	ValidateMinimapIcon(db.minimapIcon)
	ValidateCustomNodes(db.customNodes)
	return db
end
