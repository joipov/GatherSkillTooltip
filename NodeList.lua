local _, ns = ...

-- The minimap list. A yellow dot's name is a secret value on this client, so
-- the node under the cursor cannot be identified. While such a dot is hovered
-- this frame lists the herbs and ores around the player's skill with their
-- requirement and difficulty color, so the name the game draws can be looked
-- up by eye. The frame is created on first use, never at load.

local GetTime = GetTime

-- How long the list stays after the hover ends, so the cursor can reach it to
-- scroll. It also stays while the cursor is over it.
local LINGER_SECONDS = 1.5

local ROWS_MIN = 5
local ROWS_MAX = 25
local ROWS_DEFAULT = 12

function ns.ClampListRows(count)
	if type(count) ~= "number" then
		return ROWS_DEFAULT
	end
	count = math.floor(count + 0.5)
	if count < ROWS_MIN then
		return ROWS_MIN
	end
	if count > ROWS_MAX then
		return ROWS_MAX
	end
	return count
end

-- Rows (pure) ------------------------------------------------------------------

local function ByRequirement(a, b)
	if a.orange ~= b.orange then
		return a.orange < b.orange
	end
	return a.name < b.name
end

-- Every herb or ore of `prof`, one row per skill-band key, sorted by the
-- required skill. Built-in nodes use the client-language name; learned nodes
-- are added under the name they were learned with.
function ns.NodeListRows(prof)
	local rows = {}
	local seen = {}
	local display = ns.NODE_DISPLAY
	for key, node in pairs(ns.NODE_BY_KEY) do
		if node.prof == prof then
			seen[key] = true
			rows[#rows + 1] = {
				key = key,
				name = display and display[key] or key,
				node = node,
				orange = ns.EffectiveOrange(node, key),
			}
		end
	end
	local custom = ns.db and ns.db.customNodes
	local lookup = ns.LOOKUP
	if type(custom) == "table" and lookup then
		for name in pairs(custom) do
			local node = lookup[name]
			if type(node) == "table" and node.prof == prof and node.key and not seen[node.key] then
				seen[node.key] = true
				rows[#rows + 1] = {
					key = node.key,
					name = name,
					node = node,
					orange = ns.EffectiveOrange(node, node.key),
				}
			end
		end
	end
	table.sort(rows, ByRequirement)
	return rows
end

-- First visible row for a window of `visible` rows. Without `wanted` the
-- window is centered on the last node the player can gather; `wanted` is a
-- scrolled position and is only clamped. Returns (start, lastStart).
function ns.NodeListStart(rows, skill, visible, wanted)
	local lastStart = #rows - visible + 1
	if lastStart < 1 then
		lastStart = 1
	end
	local start = wanted
	if type(start) ~= "number" then
		local reachable = 0
		for i = 1, #rows do
			if rows[i].orange <= skill then
				reachable = i
			else
				break
			end
		end
		start = reachable - math.floor(visible / 2) + 1
	end
	if start < 1 then
		start = 1
	elseif start > lastStart then
		start = lastStart
	end
	return start, lastStart
end

-- (name, requirement) texts for one row, colored when the option is on.
function ns.NodeListRowText(row, skill)
	local db = ns.db
	local name = row.name
	local required = tostring(row.orange)
	if db and db.color then
		local prefix = ns.ObservedColor(skill, row.node, row.orange, row.key)
		return ns.ColorWrap(name, prefix), ns.ColorWrap(required, prefix)
	end
	return name, required
end

-- Frame --------------------------------------------------------------------------

local PADDING = 10
local ROW_HEIGHT = 14
local HEADER_HEIGHT = 18
local SECTION_GAP = 8
local COLUMN_GAP = 16
local MIN_WIDTH = 150

local BACKDROP = {
	bgFile = "Interface/Tooltips/UI-Tooltip-Background",
	edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
	tile = true,
	tileSize = 16,
	edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local PROFESSIONS = {
	{ prof = "herb", option = "herbalism", skillLine = ns.HERB_SKILL_LINE, label = "HERBALISM" },
	{ prof = "mine", option = "mining", skillLine = ns.MINE_SKILL_LINE, label = "MINING" },
}

local frame
local sections = {}
local hovering = false
local lastHover = 0
local shownSignature
-- Last readable skill per profession. Skill values are secret in combat; the
-- list keeps the number it last saw instead of going empty.
local lastSkill = {}

local Render

local function Unlocked()
	local db = ns.db
	return db and db.enabled and db.listUnlocked or false
end

local function Skill(prof)
	ns.EnsureSkills()
	local skill = ns.skills[prof]
	if type(skill) == "number" then
		lastSkill[prof] = skill
	end
	return lastSkill[prof]
end

local function Place()
	if not frame or frame.isMoving then
		return
	end
	local db = ns.db
	frame:ClearAllPoints()
	if db and type(db.listX) == "number" and type(db.listY) == "number" then
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.listX, db.listY)
	elseif Minimap then
		frame:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -16, 0)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
end

local function SavePosition()
	frame:StopMovingOrSizing()
	frame.isMoving = nil
	local left, top = frame:GetLeft(), frame:GetTop()
	if left and top and ns.db then
		ns.db.listX = left
		ns.db.listY = top
	end
	Place()
end

local function OnMouseDown(self, button)
	if not Unlocked() then
		return
	end
	if button == "LeftButton" then
		self.isMoving = true
		self:StartMoving()
	elseif button == "RightButton" then
		if self.isMoving then
			SavePosition()
		end
		ns.LockNodeList()
	end
end

local function OnMouseUp(self)
	if self.isMoving then
		SavePosition()
	end
end

local function OnSectionWheel(self, delta)
	-- The highest requirement is at the top, so wheel up moves to higher rows.
	local current = self.shownStart or 1
	self.start = current + delta
	shownSignature = nil
	Render()
end

local function SectionRow(section, index)
	local row = section.rows[index]
	if row then
		return row
	end
	row = {
		left = section:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
		right = section:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
	}
	local y = -HEADER_HEIGHT - (index - 1) * ROW_HEIGHT
	row.left:SetPoint("TOPLEFT", section, "TOPLEFT", 0, y)
	row.left:SetJustifyH("LEFT")
	row.right:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, y)
	row.right:SetJustifyH("RIGHT")
	section.rows[index] = row
	return row
end

local function CreateSection(parent)
	local section = CreateFrame("Frame", nil, parent)
	section.rows = {}
	section.header = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	section.header:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
	section.header:SetJustifyH("LEFT")
	section.range = section:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	section.range:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, -2)
	section.range:SetJustifyH("RIGHT")
	section:EnableMouseWheel(true)
	section:SetScript("OnMouseWheel", OnSectionWheel)
	section:Hide()
	return section
end

local function OnUpdate(self)
	if Unlocked() then
		return
	end
	local now = GetTime()
	if hovering then
		if GameTooltip:IsShown() then
			lastHover = now
			return
		end
		hovering = false
	end
	if self:IsMouseOver() then
		lastHover = now
		return
	end
	if now - lastHover > LINGER_SECONDS then
		ns.HideNodeList()
	end
end

local function EnsureFrame()
	if frame then
		return
	end
	frame = CreateFrame("Frame", "GatherSkillTooltipNodeList", UIParent, "BackdropTemplate")
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame:Hide()
	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetPoint("TOP", frame, "TOP", 0, -PADDING)
	frame.title:Hide()
	frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.hint:SetPoint("BOTTOM", frame, "BOTTOM", 0, PADDING)
	frame.hint:Hide()
	for i = 1, #PROFESSIONS do
		sections[i] = CreateSection(frame)
	end
	frame:SetScript("OnMouseDown", OnMouseDown)
	frame:SetScript("OnMouseUp", OnMouseUp)
	frame:SetScript("OnUpdate", OnUpdate)
	-- The hover ends when the game takes its tooltip away.
	GameTooltip:HookScript("OnHide", function()
		hovering = false
	end)
end

-- Fills one profession section. Returns its (width, height).
local function FillSection(section, def, skill, visible)
	local rows = ns.NodeListRows(def.prof)
	local start, lastStart = ns.NodeListStart(rows, skill, visible, section.start)
	local count = #rows - start + 1
	if count > visible then
		count = visible
	end
	section.shownStart = start
	section.header:SetText(ns.ProfessionName(def.skillLine, ns.L[def.label]) .. " " .. skill)
	if lastStart > 1 then
		section.range:SetText(start .. "-" .. (start + count - 1) .. " / " .. #rows)
	else
		section.range:SetText("")
	end
	local width = section.header:GetStringWidth() + COLUMN_GAP + section.range:GetStringWidth()
	for i = 1, count do
		local row = SectionRow(section, i)
		-- Highest requirement first: what is still out of reach sits at the
		-- top, what the player has outgrown at the bottom.
		local name, required = ns.NodeListRowText(rows[start + count - i], skill)
		row.left:SetText(name)
		row.right:SetText(required)
		row.left:Show()
		row.right:Show()
		local rowWidth = row.left:GetStringWidth() + COLUMN_GAP + row.right:GetStringWidth()
		if rowWidth > width then
			width = rowWidth
		end
	end
	for i = count + 1, #section.rows do
		section.rows[i].left:Hide()
		section.rows[i].right:Hide()
	end
	return width, HEADER_HEIGHT + count * ROW_HEIGHT
end

-- Lays the frame out. Returns true when at least one profession is listed.
Render = function()
	local db = ns.db
	if not frame or not db then
		return false
	end
	local visible = ns.ClampListRows(db.listRows)
	local width = MIN_WIDTH
	local y = PADDING
	local listed = 0
	for i = 1, #PROFESSIONS do
		local def = PROFESSIONS[i]
		local section = sections[i]
		local skill = db[def.option] and Skill(def.prof) or nil
		if skill then
			if listed > 0 then
				y = y + SECTION_GAP
			end
			local sectionWidth, sectionHeight = FillSection(section, def, skill, visible)
			if sectionWidth > width then
				width = sectionWidth
			end
			section.offsetY = y
			section.height = sectionHeight
			section:Show()
			y = y + sectionHeight
			listed = listed + 1
		else
			section:Hide()
		end
	end
	for i = 1, #PROFESSIONS do
		local section = sections[i]
		if section:IsShown() then
			section:ClearAllPoints()
			section:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -section.offsetY)
			section:SetSize(width, section.height)
		end
	end
	if listed == 0 then
		-- Nothing to list (no gathering profession). The title keeps the
		-- frame visible while it is unlocked for dragging.
		frame.title:SetText(ns.DISPLAY)
		frame.title:Show()
		y = y + HEADER_HEIGHT
		local titleWidth = frame.title:GetStringWidth()
		if titleWidth > width then
			width = titleWidth
		end
	else
		frame.title:Hide()
	end
	-- Plain text while it is in use. The box only marks the drag area.
	if Unlocked() then
		frame:SetBackdrop(BACKDROP)
		frame:SetBackdropColor(0, 0, 0, 0.8)
		frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
		frame.hint:SetText(ns.L.BANNER_DRAG_HINT)
		frame.hint:Show()
		local hintWidth = frame.hint:GetStringWidth()
		if hintWidth > width then
			width = hintWidth
		end
		y = y + 4 + frame.hint:GetStringHeight()
	else
		frame:SetBackdrop(nil)
		frame.hint:Hide()
	end
	frame:SetSize(width + PADDING * 2, y + PADDING)
	return listed > 0
end

local function Signature()
	local db = ns.db
	return table.concat({
		tostring(db.herbalism and Skill("herb") or nil),
		tostring(db.mining and Skill("mine") or nil),
		tostring(db.listRows),
		tostring(db.color),
	}, ":")
end

-- Public ---------------------------------------------------------------------------

function ns.HideNodeList()
	hovering = false
	shownSignature = nil
	if not frame then
		return
	end
	if Unlocked() then
		return
	end
	for i = 1, #sections do
		sections[i].start = nil
	end
	frame:Hide()
end

-- Called while a minimap dot whose name cannot be read is under the cursor.
-- The minimap can rebuild its tooltip every frame, so an unchanged list is
-- not laid out again.
function ns.ShowNodeList()
	local db = ns.db
	if not db or not db.enabled or not db.showList then
		return
	end
	EnsureFrame()
	hovering = true
	lastHover = GetTime()
	local signature = Signature()
	if frame:IsShown() and signature == shownSignature then
		return
	end
	shownSignature = signature
	if Render() then
		Place()
		frame:Show()
	elseif not Unlocked() then
		frame:Hide()
	end
end

-- The cursor moved from a hidden dot to something that is not one. The list
-- still lingers so it can be reached and scrolled.
function ns.EndNodeListHover()
	hovering = false
end

-- Applies the options: the unlock state, the row count and the on/off switch.
function ns.ApplyNodeListLayout()
	local db = ns.db
	if not db then
		return
	end
	if Unlocked() then
		EnsureFrame()
		frame:EnableMouse(true)
		shownSignature = nil
		Render()
		Place()
		frame:Show()
		return
	end
	if not frame then
		return
	end
	if frame.isMoving then
		SavePosition()
	end
	frame:EnableMouse(false)
	shownSignature = nil
	if not db.enabled or not db.showList or not frame:IsShown() then
		ns.HideNodeList()
		return
	end
	if Render() then
		Place()
		lastHover = GetTime()
	else
		ns.HideNodeList()
	end
end

function ns.LockNodeList()
	local setting = ns.listUnlockSetting
	if setting and setting:GetValue() then
		setting:SetValue(false)
		return
	end
	if ns.db then
		ns.db.listUnlocked = false
	end
	ns.ApplyNodeListLayout()
end

function ns.ToggleNodeListUnlock()
	local db = ns.db
	if not db then
		return
	end
	local setting = ns.listUnlockSetting
	if setting then
		setting:SetValue(not setting:GetValue())
		return
	end
	db.listUnlocked = not db.listUnlocked
	ns.ApplyNodeListLayout()
end
