local _, ns = ...

-- English strings: the base every other locale overlays (Locales/<locale>.lua).
ns.L = {
	ENABLE = "Enable %s",
	ENABLE_TIP = "Off means no tooltip changes and no screen warnings.",
	HEADER_PROFESSIONS = "Professions",
	HERBALISM = "Herbalism",
	HERBALISM_TIP = "Show skill on herbs.",
	MINING = "Mining",
	MINING_TIP = "Show skill on ores.",
	SKINNING = "Skinning",
	SKINNING_TIP = "Show your skill beside the level of a creature you can skin.",
	CREATURE_BEAST = "Beast",
	CREATURE_DRAGONKIN = "Dragonkin",
	SKINNABLE = "Skinnable",
	HEADER_TOOLTIP = "Tooltip",
	SHOW_CURRENT = "Show my skill",
	SHOW_CURRENT_TIP = "The first number. Like the 42 in %s (42/50).",
	SHOW_REQUIRED = "Show required skill",
	SHOW_REQUIRED_TIP = "The second number. Like the 50 in %s (42/50).",
	COLOR = "Color by difficulty",
	COLOR_TIP = "Red below the required skill, then orange, yellow, green, and grey.",
	LEARN_CHAT = "Chat when something is learned",
	LEARN_CHAT_TIP = "One chat line when a creature's skinning is learned, when an unknown herb or ore is learned from gathering, or when a herb, ore, or skin color changes.",
	LEARNED_SKIN_YES = "Learned: %s can be skinned.",
	LEARNED_SKIN_NO = "Learned: %s cannot be skinned.",
	LEARNED_NODE = "Learned: %s requires about %d.",
	LEARNED_COLOR = "Learned: %s is %s at %d.",
	LEARNED_LEVEL = "level %d",
	COLOR_RED = "red",
	COLOR_ORANGE = "orange",
	COLOR_YELLOW = "yellow",
	COLOR_GREEN = "green",
	COLOR_GREY = "grey",
	HEADER_TRACKING = "Tracking",
	WARN_TRACKING = "Warn if gathering tracking is off",
	WARN_TRACKING_TIP = "Message in the middle of the screen until you turn on %s or %s. One is enough.",
	TRACKING_OFF_BOTH = "No herb or mineral tracking",
	BANNER_SIZE = "Text size",
	BANNER_SIZE_TIP = "Point size of the tracking warning and the trainer reminder. 20 is the large size.",
	BANNER_UNLOCK = "Unlock position",
	BANNER_UNLOCK_TIP = "Shows the reminder so you can drag it. Right-click it to lock.",
	BANNER_DRAG_HINT = "Right click when finished dragging",
	RESET_SETTINGS = "Reset settings",
	RESET = "Reset",
	RESET_TIP = "Checkboxes, text size, reminder position, and minimap button go back to default. Learned herbs, ores, and skinning stay. /gst reset does this too.",
	RESET_DONE = "Settings reset.",
	HEADER_TRAINER = "Trainer",
	WARN_TRAIN = "Remind me to train the next rank",
	WARN_TRAIN_TIP = "A short message in the middle of the screen when you gather while %s, %s, or %s is capped and a trainer still has a higher rank.",
	TRAIN_NEXT = "Train the next %s rank.",
	SHOW_MINIMAP = "Minimap Button",
	SHOW_MINIMAP_TIP = "Button on the minimap. Opens settings. Ellesmere puts it with the other addon buttons.",
	OPEN_FAILED = "couldn't open settings.",
	DEBUG_ON = "on",
	DEBUG_OFF = "off",
	SPELL_OFF = "%s is off",
	CLICK_SETTINGS = "Click for settings.",
	DRAG_MOVE = "Drag to move.",
	FIND_HERBS = "Find Herbs",
	FIND_MINERALS = "Find Minerals",
	EXAMPLE_HERB = "Peacebloom",
}

-- Tooltip name -> node (ARCH-004): English names from ns.NODES; each
-- locale file adds its aliases. A separate table, ns.NODES is not mutated.
local lookup = {}
for name, node in pairs(ns.NODES) do
	lookup[name] = node
end
ns.LOOKUP = lookup

-- Called by Locales/<locale>.lua, which the TOC loads only on that client
-- locale ([AllowLoadTextLocale], ARCH-005/PERF-005): overlays UI strings and
-- registers localized object names.
function ns.RegisterLocale(strings, aliases)
	local L = ns.L
	for key, value in pairs(strings) do
		L[key] = value
	end
	local nodes = ns.NODES
	for locName, enName in pairs(aliases) do
		local node = nodes[enName]
		if node then
			lookup[locName] = node
		end
	end
end
