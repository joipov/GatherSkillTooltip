local _, ns = ...

-- Object and minimap-pin tooltips: rewrite the first line with the player's
-- skill and the node's requirement, and remember the hovered node so a
-- following gather cast can be attributed to it.

local GetTime = GetTime

local SecretBlocked = ns.SecretBlocked
local ReadableString = ns.ReadableString

local lastDebugText
local lastNodeKey
local lastNodeProf
local lastNodeTime = 0
local lastUnknownName
local lastUnknownTime = 0
-- A hovered node is only attributed to a gather cast that starts within this
-- window (CQ-001). Hovering an unknown object or an ambiguous pin stack clears it.
local NODE_KEY_SECONDS = 15

local function ShowUnmatched(raw, cleaned)
	local db = ns.db
	if db.debug and cleaned and cleaned ~= lastDebugText and #cleaned < 60 then
		lastDebugText = cleaned
		ns.Debug("unmatched", string.format("%q", raw))
	end
end

local function ApplyDisplay(tooltip, fs, display)
	local current = fs and fs:GetText()
	if fs and not SecretBlocked(current) then
		if ReadableString(current) ~= display then
			fs:SetText(display)
		end
		fs:SetTextColor(1, 1, 1)
		return true
	end
	if ns.LastLineText(tooltip) == display then
		return true
	end
	tooltip:AddLine(display)
	return true
end

local function ApplyLine(db, line)
	local name, node, cleaned = ns.ExactNode(line)
	if not node then
		return line, false, nil, cleaned
	end
	local title, prefix = ns.FormatNode(name, node)
	if not title then
		return line, false, node, cleaned
	end
	if db.color then
		return ns.ColorWrap(title, prefix), true, node, cleaned
	end
	return title, true, node, cleaned
end

local function ForgetNode()
	lastNodeKey = nil
	lastNodeProf = nil
	lastNodeTime = 0
end

local function ForgetUnknown()
	lastUnknownName = nil
	lastUnknownTime = 0
end

-- Records the node under the cursor so a following gather cast can be
-- attributed to it. `node` is nil when the hovered object is unknown; the
-- previous node is then forgotten so it cannot be misattributed (CQ-001).
local function RememberNode(node)
	if node and node.key and (node.prof == "herb" or node.prof == "mine") then
		lastNodeKey = node.key
		lastNodeProf = node.prof
		lastNodeTime = GetTime()
		return
	end
	ForgetNode()
end

local function RememberUnknown(cleaned)
	if cleaned and cleaned ~= "" then
		lastUnknownName = cleaned
		lastUnknownTime = GetTime()
		return
	end
	ForgetUnknown()
end

-- The key of the node hovered within the last NODE_KEY_SECONDS for `prof`,
-- or nil (and the memory is cleared once it has expired).
function ns.RecentNodeKey(prof)
	if not lastNodeKey or lastNodeProf ~= prof then
		return nil
	end
	if GetTime() - lastNodeTime > NODE_KEY_SECONDS then
		ForgetNode()
		return nil
	end
	return lastNodeKey
end

-- Cleaned object name hovered within NODE_KEY_SECONDS that had no ExactNode
-- match (used to learn Forever-only herbs/ores on a successful gather).
function ns.RecentUnknownName()
	if not lastUnknownName then
		return nil
	end
	if GetTime() - lastUnknownTime > NODE_KEY_SECONDS then
		ForgetUnknown()
		return nil
	end
	return lastUnknownName
end

function ns.ForgetUnknownName()
	ForgetUnknown()
end

-- `trackNode` is true only for Object and MinimapMouseover tooltips, where
-- the first line names the world object the player is about to interact with.
function ns.ApplyTooltip(tooltip, data, trackNode)
	local db = ns.db
	if not db or not db.enabled or not tooltip then
		return false
	end
	if not data then
		data = ns.PrimaryTooltipData(tooltip)
	end

	local raw, fs = ns.FirstLine(tooltip, data)
	if not raw then
		return false
	end

	if not raw:find("\n", 1, true) then
		local line, matched, node, cleaned = ApplyLine(db, raw)
		if trackNode then
			if node then
				RememberNode(node)
				ForgetUnknown()
			elseif cleaned then
				RememberUnknown(cleaned)
				ForgetNode()
			else
				ForgetNode()
				ForgetUnknown()
			end
		end
		if not matched then
			if not node then
				ShowUnmatched(raw, cleaned)
			end
			return false
		end
		return ApplyDisplay(tooltip, fs, line)
	end

	-- Stacked minimap pins: several object names separated by newlines.
	local matched = false
	local known = false
	local firstCleaned
	local parts = {}
	local index = 0
	local nodeCount = 0
	local singleNode
	local unknownCount = 0
	local singleUnknown
	for line in (raw .. "\n"):gmatch("(.-)\n") do
		index = index + 1
		local nextLine, lineMatched, node, cleaned = ApplyLine(db, line)
		if index == 1 then
			firstCleaned = cleaned
		end
		if node then
			known = true
			nodeCount = nodeCount + 1
			singleNode = node
		elseif cleaned and cleaned ~= "" then
			unknownCount = unknownCount + 1
			singleUnknown = cleaned
		end
		if lineMatched then
			matched = true
		end
		parts[#parts + 1] = nextLine
	end
	if trackNode then
		-- Only an unambiguous stack is remembered (CQ-001).
		if nodeCount == 1 then
			RememberNode(singleNode)
			ForgetUnknown()
		elseif nodeCount == 0 and unknownCount == 1 then
			ForgetNode()
			RememberUnknown(singleUnknown)
		else
			ForgetNode()
			ForgetUnknown()
		end
	end

	if not matched then
		if not known then
			ShowUnmatched(raw, firstCleaned)
		end
		return false
	end

	return ApplyDisplay(tooltip, fs, table.concat(parts, "\n"))
end

function ns.OnObjectTooltip(tooltip, data)
	return ns.ApplyTooltip(tooltip, data, true)
end
