local ADDON_NAME, ns = ...

-- The addon's single event frame, the event dispatch table, the
-- tooltip post-call registrations and the GameTooltip fallback hook. This is
-- the only file that touches the WoW API at load time.

local C_Timer = C_Timer
local GetMouseFoci = GetMouseFoci
local WorldFrame = WorldFrame
local Minimap = Minimap

local eventFrame = CreateFrame("Frame")

-- Registers or unregisters a list of events. Entries are event names or
-- { event, unit } pairs for RegisterUnitEvent.
function ns.SetEventsRegistered(events, active)
	for i = 1, #events do
		local entry = events[i]
		if type(entry) == "table" then
			if active then
				eventFrame:RegisterUnitEvent(entry[1], entry[2])
			else
				eventFrame:UnregisterEvent(entry[1])
			end
		elseif active then
			eventFrame:RegisterEvent(entry)
		else
			eventFrame:UnregisterEvent(entry)
		end
	end
end

local CORE_EVENTS = {
	"PLAYER_ENTERING_WORLD",
	"SKILL_LINES_CHANGED",
	"CHAT_MSG_SKILL",
	{ "UNIT_SPELLCAST_SENT", "player" },
	{ "UNIT_SPELLCAST_START", "player" },
	{ "UNIT_SPELLCAST_SUCCEEDED", "player" },
	{ "UNIT_SPELLCAST_INTERRUPTED", "player" },
	{ "UNIT_SPELLCAST_FAILED", "player" },
}

local handlers = {}

function handlers.ADDON_LOADED(name)
	if name ~= ADDON_NAME then
		return
	end
	_G.GatherSkillTooltipDB = ns.LoadDB(_G.GatherSkillTooltipDB)
	ns.db = _G.GatherSkillTooltipDB
	ns.ApplyCustomNodes(ns.db.customNodes)
	eventFrame:UnregisterEvent("ADDON_LOADED")
	ns.SetEventsRegistered(CORE_EVENTS, true)
	ns.UpdateLootEvents()
	ns.InitOptions()
	eventFrame:RegisterEvent("PLAYER_LOGIN")
end

function handlers.PLAYER_LOGIN()
	ns.CreateMinimapButton()
	ns.Welcome()
end

function handlers.PLAYER_ENTERING_WORLD()
	ns.RefreshSkills()
	ns.QueueTrackingCheck()
	ns.CreateMinimapButton()
end

local function OnSkillChanged()
	if not ns.NoteGatherSkill() then
		ns.RefreshSkills()
	end
	ns.QueueTrackingCheck()
end
handlers.SKILL_LINES_CHANGED = OnSkillChanged
handlers.CHAT_MSG_SKILL = OnSkillChanged

-- Registered by Warnings.lua only while the tracking warning is active.
local function OnTrackingEvent(_, _, _, event)
	ns.SetTrackingTrigger(event)
	ns.QueueTrackingCheck()
end
handlers.MINIMAP_UPDATE_TRACKING = OnTrackingEvent
handlers.PLAYER_REGEN_DISABLED = OnTrackingEvent
handlers.PLAYER_REGEN_ENABLED = OnTrackingEvent
handlers.UNIT_AURA = OnTrackingEvent

-- Registered by Learning.lua while skinning or herb/ore learning is active.
handlers.LOOT_OPENED = ns.OnLootOpened
handlers.LOOT_READY = ns.OnLootReady
handlers.LOOT_SLOT_CLEARED = ns.OnLootSlotCleared
handlers.LOOT_CLOSED = ns.OnLootClosed

function handlers.UNIT_SPELLCAST_SENT(_, target)
	ns.NoteCastTarget(target)
end

function handlers.UNIT_SPELLCAST_START(_, _, spellID)
	ns.OnGatherCastStart(spellID)
end

local function OnCastStopped(_, _, spellID)
	ns.OnGatherCastStop(spellID)
end
handlers.UNIT_SPELLCAST_INTERRUPTED = OnCastStopped
handlers.UNIT_SPELLCAST_FAILED = OnCastStopped

function handlers.UNIT_SPELLCAST_SUCCEEDED(_, _, spellID)
	if not ns.SecretBlocked(spellID) and ns.TRACKING_SPELLS[spellID] then
		ns.NoteTrackingSpell(spellID)
	end
	ns.OnGatherCastSucceeded(spellID)
	local db = ns.db
	if not db or not db.enabled or not db.warnTrain or (not db.herbalism and not db.mining and not db.skinning) then
		return
	end
	local prof = ns.ProfessionForGatherSpell(spellID)
	if prof then
		ns.CheckTrainReminder(prof)
	end
end

eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
	local handler = handlers[event]
	if handler then
		handler(arg1, arg2, arg3, event)
	end
end)
eventFrame:RegisterEvent("ADDON_LOADED")

-- Tooltip post-calls ---------------------------------------------------------------

-- Node tooltips belong to the world and to minimap pins. Anything owned by a
-- UI frame (the guild roster, bags, action bars, unit frames, chat links) must
-- never be rewritten, even when its first line equals a learned node name.
-- The client's mouse-focus API is GetMouseFoci; over the open world the list
-- may be empty, which also counts as world. Click-through overlays propagate
-- input and do not take the tooltip away from the world.
local function NodeTooltipContext(tooltip)
	-- The tooltip owner is the frame the tooltip is anchored to. The client's
	-- own world objects and minimap pins use UIParent/WorldFrame (or a frame
	-- under the minimap); the guild roster, party/raid frames, bags and action
	-- bars use themselves, so their text is never rewritten.
	if not ns.TooltipOwnerIsWorld(tooltip) then
		return false
	end
	if not GetMouseFoci then
		return true
	end
	local foci = GetMouseFoci()
	local focus = type(foci) == "table" and foci[1] or nil
	if not focus or focus == WorldFrame then
		return true
	end
	if Minimap and ns.FrameIsUnder(focus, Minimap) then
		return true
	end
	if focus.CanPropagateMouseMotion and focus:CanPropagateMouseMotion() then
		return true
	end
	if focus.CanPropagateMouseClicks and focus:CanPropagateMouseClicks() then
		return true
	end
	return false
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.MinimapMouseover, ns.OnObjectTooltip)
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, function(tooltip, data)
	if NodeTooltipContext(tooltip) then
		ns.OnObjectTooltip(tooltip, data)
	end
end)
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, ns.OnUnitTooltip)
-- Dead NPCs arrive as Unit tooltips. Corpse is kept until an in-game
-- check confirms it never carries a resolvable unit (then remove this line).
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Corpse, ns.OnUnitTooltip)

-- Fallback for GameTooltip shows that carry no tooltip data. Typed
-- tooltips (Object, MinimapMouseover, Unit,...) are handled by the post-calls
-- above. This only runs while the cursor is over the world: UI tooltips (the
-- guild roster, bags, action bars) are skipped, so they are never rewritten.
-- It is instrumented: `/gst stats` reports shown/checked/applied/skipped.
ns.fallbackStats = { shown = 0, checked = 0, applied = 0, skipped = 0, retried = 0 }
do
	local stats = ns.fallbackStats
	local retryPending = false
	local SecretBlocked = ns.SecretBlocked

	local function TooltipLineReady(tooltip)
		local fs = ns.FontStringByIndex(tooltip, 1)
		if not fs then
			return false
		end
		local text = fs:GetText()
		if SecretBlocked(text) then
			return true
		end
		return type(text) == "string" and text ~= ""
	end

	local function FallbackApply(tooltip, data)
		stats.checked = stats.checked + 1
		if not NodeTooltipContext(tooltip) or ns.TooltipHasUnit(tooltip) then
			stats.skipped = stats.skipped + 1
			return
		end
		if ns.ApplyTooltip(tooltip, data, true) then
			stats.applied = stats.applied + 1
			-- Outside a post-call the tooltip does not re-layout by itself.
			tooltip:Show()
		end
	end

	local function RetryFallback()
		retryPending = false
		local tooltip = GameTooltip
		if not tooltip:IsShown() or not ns.db or not ns.db.enabled then
			return
		end
		local data = ns.PrimaryTooltipData(tooltip)
		if data and data.type ~= nil then
			return
		end
		FallbackApply(tooltip, data)
	end

	GameTooltip:HookScript("OnShow", function(tooltip)
		if not ns.db or not ns.db.enabled then
			return
		end
		stats.shown = stats.shown + 1
		local data = ns.PrimaryTooltipData(tooltip)
		if data and data.type ~= nil then
			return
		end
		if TooltipLineReady(tooltip) then
			FallbackApply(tooltip, data)
			return
		end
		if retryPending then
			return
		end
		retryPending = true
		stats.retried = stats.retried + 1
		C_Timer.After(0, RetryFallback)
	end)
end
