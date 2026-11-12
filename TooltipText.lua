local ADDON_NAME, ns = ...

-- Shared helpers: secret-value guards, text stripping, colors, chat output
-- and tooltip font-string access. No game state lives here.

local issecretvalue = issecretvalue
local canaccessvalue = canaccessvalue
local issecrettable = issecrettable
local canaccesstable = canaccesstable
local UnitExists = UnitExists

local function Chat(text)
	print("|cff8b5cf6Joipov|r " .. ns.DISPLAY .. ": " .. tostring(text or ""))
end

function ns.Print(text)
	Chat(text)
end

-- Login line. Name and version come from the TOC, so they never drift.
function ns.Welcome()
	local title = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Title") or ns.DISPLAY
	local version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "?"
	print(string.format("|cff8b5cf6Joipov|r %s (|cff22d3eev%s|r). Type |cffffffff/gst|r to open settings.", title, version))
end

local function JoinArgs(...)
	local count = select("#", ...)
	local parts = {}
	for i = 1, count do
		parts[i] = tostring(select(i, ...))
	end
	return table.concat(parts, " ")
end

-- Debug output; only when `/gst debug` is on.
function ns.Debug(...)
	if ns.db and ns.db.debug then
		Chat(JoinArgs(...))
	end
end

-- Secret values (combat restrictions): never compare, index, measure or use
-- as a table key. type and truthiness on non-booleans are allowed.
function ns.SecretBlocked(value)
	return issecretvalue(value) and not canaccessvalue(value)
end
local SecretBlocked = ns.SecretBlocked

-- Non-empty, non-secret string or nil.
function ns.ReadableString(value)
	if type(value) ~= "string" or SecretBlocked(value) then
		return nil
	end
	if value == "" then
		return nil
	end
	return value
end
local ReadableString = ns.ReadableString

function ns.CanIndex(value)
	if value == nil or SecretBlocked(value) then
		return false
	end
	if issecrettable(value) and not canaccesstable(value) then
		return false
	end
	return true
end

-- Colors -------------------------------------------------------------------

local COLORS = {
	red = { 1.00, 0.10, 0.10 },
	orange = { 1.00, 0.50, 0.25 },
	yellow = { 1.00, 1.00, 0.00 },
	green = { 0.25, 0.75, 0.25 },
	grey = { 0.50, 0.50, 0.50 },
}

local function ColorPrefix(color)
	return string.format(
		"|cff%02x%02x%02x",
		math.floor(color[1] * 255 + 0.5),
		math.floor(color[2] * 255 + 0.5),
		math.floor(color[3] * 255 + 0.5)
	)
end

ns.COLOR_PREFIX = {
	red = ColorPrefix(COLORS.red),
	orange = ColorPrefix(COLORS.orange),
	yellow = ColorPrefix(COLORS.yellow),
	green = ColorPrefix(COLORS.green),
	grey = ColorPrefix(COLORS.grey),
}

function ns.ColorWrap(text, prefix)
	if not prefix then
		return text
	end
	return prefix .. text .. "|r"
end

-- Text -----------------------------------------------------------------------

-- Removes |cAARRGGBB... |r color codes (the one strip helper).
function ns.StripInline(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Object name as it appears in a tooltip, without colors, textures, atlases
-- or a trailing " (skill)" / " (skill/required)" suffix we added earlier.
function ns.NormalizeName(text)
	if not text or text == "" then
		return nil
	end
	text = ns.StripInline(text)
	text = text:gsub("|T.-|t", ""):gsub("|A:.-|a", "")
	text = text:gsub(" %(%d+/%d+%)$", ""):gsub(" %(%d+%)$", "")
	return text:match("^%s*(.-)%s*$")
end

-- Removes the first " (Label 12/34)" or " (Label 12)" suffix from a line.
function ns.StripSkillSuffix(text)
	text = ns.StripInline(text)
	text = text:gsub(" %([^%d%)]*%d+/%d+%)", "", 1)
	return (text:gsub(" %([^%d%)]*%d+%)", "", 1))
end

function ns.FirstNumber(text)
	local digits = text:match("%f[%d](%d+)%f[%D]")
	if not digits then
		return nil
	end
	return tonumber(digits)
end

-- Tooltip access --------------------------------------------------------------

function ns.FontStringByIndex(tooltip, index)
	if SecretBlocked(index) then
		return nil
	end
	-- Lines 1-2 have parentKeys; later lines only exist as named globals.
	local fs = tooltip["TextLeft" .. index]
	if fs then
		return fs
	end
	local name = ReadableString(tooltip:GetName())
	if not name then
		return nil
	end
	return _G[name .. "TextLeft" .. index]
end

function ns.RightFontStringByIndex(tooltip, index)
	local fs = tooltip["TextRight" .. index]
	if fs then
		return fs
	end
	local name = ReadableString(tooltip:GetName())
	if not name then
		return nil
	end
	return _G[name .. "TextRight" .. index]
end

-- GetPrimaryTooltipData is the current accessor; GetTooltipData is the
-- "to be deprecated" alias (TooltipDataHandlerMixin).
function ns.PrimaryTooltipData(tooltip)
	if tooltip.GetPrimaryTooltipData then
		return tooltip:GetPrimaryTooltipData()
	end
	if tooltip.GetTooltipData then
		return tooltip:GetTooltipData()
	end
	return nil
end

function ns.LastLineText(tooltip)
	local count = tooltip:NumLines()
	if SecretBlocked(count) or type(count) ~= "number" or count < 1 then
		return nil
	end
	local fs = ns.FontStringByIndex(tooltip, count)
	return fs and ReadableString(fs:GetText())
end

-- True when `frame` is `ancestor` or one of its descendants. Walks GetParent
-- because not every frame in the Forever client has IsDescendantOf (Questie's
-- map-icon buttons are one example).
function ns.FrameIsUnder(frame, ancestor)
	local current = frame
	for _ = 1, 10 do
		if current == ancestor then
			return true
		end
		if not current or type(current.GetParent) ~= "function" then
			return false
		end
		current = current:GetParent()
	end
	return false
end

-- True when the tooltip belongs to the world (or the minimap) rather than to a
-- UI window. The guild roster, party/raid frames, bags, action bars and chat
-- links all set themselves as the tooltip owner, so their lines must never be
-- treated as world object names. An unowned tooltip is a world tooltip.
function ns.TooltipOwnerIsWorld(tooltip)
	if not tooltip or type(tooltip.GetOwner) ~= "function" then
		return true
	end
	local owner = tooltip:GetOwner()
	if not owner or owner == UIParent or owner == WorldFrame then
		return true
	end
	-- A forbidden owner (a nameplate aura button, for example) cannot be
	-- inspected from addon code; treat it as a UI window, never as world.
	if type(owner.IsForbidden) == "function" and owner:IsForbidden() then
		return false
	end
	-- The owner can be the minimap, one of its children (a pin) or the cluster
	-- frame it lives in.
	if Minimap and (ns.FrameIsUnder(owner, Minimap) or ns.FrameIsUnder(Minimap, owner)) then
		return true
	end
	return false
end

-- True when a cleaned tooltip line is a unit token, such as a group member's
-- name or "target". A learned name that is a unit must not be decorated as a
-- herb or ore (for example a player name hovered on the minimap).
function ns.UnitNameExists(name)
	if not name or name == "" then
		return false
	end
	local exists = UnitExists(name)
	if SecretBlocked(exists) then
		return true
	end
	return exists and true or false
end

-- True when the tooltip was built for a unit rather than a world object.
-- Secret tokens count as a unit: leave them alone.
function ns.TooltipHasUnit(tooltip)
	if not tooltip or not tooltip.GetUnit then
		return false
	end
	local _, unit = tooltip:GetUnit()
	if unit == nil then
		return false
	end
	if type(unit) ~= "string" or SecretBlocked(unit) then
		return true
	end
	local exists = UnitExists(unit)
	if SecretBlocked(exists) then
		return true
	end
	return exists and true or false
end

-- True when the visible tooltip has a line carrying `name`, once colors and a
-- skill suffix this addon added are stripped. Used before learning an unknown
-- node so a name remembered from an earlier hover cannot be attributed to a
-- later gather on a different object.
function ns.TooltipShowsName(tooltip, name)
	if not tooltip or type(name) ~= "string" or name == "" then
		return false
	end
	if tooltip.IsShown and not tooltip:IsShown() then
		return false
	end
	local count = tooltip:NumLines()
	if SecretBlocked(count) or type(count) ~= "number" then
		return false
	end
	for i = 1, count do
		local fs = ns.FontStringByIndex(tooltip, i)
		local text = fs and ReadableString(fs:GetText())
		if text and ns.NormalizeName(ns.StripSkillSuffix(text)) == name then
			return true
		end
	end
	return false
end

-- True when the visible tooltip has a line whose cleaned name maps to the
-- same node key. Handles locale aliases and stacked pins, so a remembered
-- node is checked against the name the client actually shows.
function ns.TooltipShowsNode(tooltip, key)
	if not tooltip or type(key) ~= "string" or key == "" then
		return false
	end
	if tooltip.IsShown and not tooltip:IsShown() then
		return false
	end
	local count = tooltip:NumLines()
	if SecretBlocked(count) or type(count) ~= "number" then
		return false
	end
	local lookup = ns.LOOKUP
	if not lookup then
		return false
	end
	for i = 1, count do
		local fs = ns.FontStringByIndex(tooltip, i)
		local text = fs and ReadableString(fs:GetText())
		if text then
			local cleaned = ns.NormalizeName(ns.StripSkillSuffix(text))
			local node = cleaned and lookup[cleaned]
			if node and node.key == key then
				return true
			end
		end
	end
	return false
end

local function DataLeftText(data)
	if not ns.CanIndex(data) then
		return nil
	end
	local lines = data.lines
	if not ns.CanIndex(lines) then
		return nil
	end
	local line = lines[1]
	if not ns.CanIndex(line) then
		return nil
	end
	return ReadableString(line.leftText)
end

-- First line text (data preferred, font string as fallback) and the first
-- left font string.
function ns.FirstLine(tooltip, data)
	local fs = ns.FontStringByIndex(tooltip, 1)
	local fromData = DataLeftText(data)
	if fromData then
		return fromData, fs
	end
	return fs and ReadableString(fs:GetText()), fs
end
