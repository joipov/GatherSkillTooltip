local _, ns = ...

-- Shared helpers: secret-value guards, text stripping, colors, chat output
-- and tooltip font-string access. No game state lives here.

local issecretvalue = issecretvalue
local canaccessvalue = canaccessvalue
local issecrettable = issecrettable
local canaccesstable = canaccesstable

ns.PRINT_PREFIX = "|cff88ccff" .. ns.TITLE .. ":|r"

function ns.Print(text)
	print(ns.PRINT_PREFIX .. " " .. text)
end

function ns.PrintLoginHint()
	ns.Print(ns.L.LOGIN_HINT or "Type |cffffffff/gst|r to open settings.")
end

-- Debug output; only when `/gst debug` is on.
function ns.Debug(...)
	if ns.db and ns.db.debug then
		print(ns.PRINT_PREFIX, ...)
	end
end

-- Secret values (combat restrictions): never compare, index, measure or use
-- as a table key. type() and truthiness on non-booleans are allowed.
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

-- Removes |cAARRGGBB ... |r color codes (ARCH-003: the one strip helper).
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
-- "to be deprecated" alias (TooltipDataHandlerMixin, COMPAT-001).
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
