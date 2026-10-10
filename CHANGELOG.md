# Changelog

## 2.0.7

Herb and ore difficulty turns green later, matching the client.

### Fixed

- Kingsblood stays yellow through 186 and turns green at 187. The band is
  125 / 150 / 187 / 225. At 176 the tooltip was calling it green while it is
  still yellow.
- Every other herb and ore uses the same green step, the midpoint of yellow
  and grey. Copper Vein turns green at 62.
- Skinning and nodes learned in play use that midpoint. Saves that still have
  the old learned green are updated once.

## 2.0.6

Settings wording is shorter and matches the other Joipov addons.

### Changed

- **Minimap button** is sentence case.
- **Chat when you learn something**, the skinning line, text size, and reset are shorter.

## 2.0.5

The minimap button is on by default, including saves that still had it off.

### Changed

- **Minimap Button** sits under Enable and starts on. Click opens settings.
- The button uses LibDBIcon when that library is loaded, and the same frame name when it is not, so the default minimap, the addon compartment, Ellesmere, and ElvUI can all show it.

## 2.0.4

The reminder text size is a slider.

### Added

- **Text size** runs from 10 to 32 for the tracking warning and the trainer reminder. 20 is the large size it used before.

### Changed

- The addon list groups this under Joipov Tools. The list name has no Joipov prefix.

## 2.0.3

The reminder can be moved, and the addon loads on Forever again.

### Fixed

- Forever loads the addon. The game-type line was missing a colon.

### Added

- **Unlock position** shows the reminder so you can drag it. Right-click locks it. A reload locks it too. The position is saved.
- **Reset settings**, and `/gst reset`, put the checkboxes, reminder position, and minimap button back to default. Learned herbs, ores, and skinning stay.

### Changed

- Chat lines are printed by this addon. Logging in tells you `/gst`.
- The addon list name is Gather Skill Tooltip.

## 2.0.2

Copper Vein difficulty colors, and names for Forever starter nodes.

### Fixed

- Copper Vein turns green at 50. The band is 1 / 25 / 50 / 100. From 50 to 64
  the tooltip was calling it green while it is still yellow.

### Added

- **Weak Copper Vein** uses the same skill band as Copper Vein.
- Locale names for Wilted Peacebloom, Weak Copper Vein, and Poor Copper Vein.

## 2.0.1

Forever gather nodes, learning unknown herbs and ores from play, and
corrections to how those learned skill thresholds are stored.

### Added

- Forever starter herbs **Wilted Peacebloom** and **Stunted Silverleaf** share
  the Classic Peacebloom / Silverleaf skill bands (client GameObjects dump for
  build 1.60.1.70009 has no herb/ore world names; Lock matches Classic herbs).
- Unknown Object/Minimap herb and ore names hovered within 15 seconds are
  remembered; a successful gather writes them to `customNodes` in
  SavedVariables and merges them into the tooltip lookup for the session
  (orange = skill at first successful gather, then +25/+50/+100). Built-in
  names always win; re-learning keeps the lower orange.

### Fixed

- An unknown herb or ore is learned only from the name captured when the
  gather cast starts, and only when that cast had no known node. A name that
  appears only after the cast has started is not saved.
- The orange skill stored for that new node is the skill at cast start, so a
  skill-up on the same gather does not raise it.
- The lowered orange threshold is stored as `orangeSeen` and only decreases.
  `gainedAt` remains the highest skill-up and no longer erases an earlier,
  lower threshold.

### Changed

- Chat learning option also announces newly learned herb/ore nodes.
- SavedVariables move to version 3. On that load, a `gainedAt` that is still
  below the table orange is copied into `orangeSeen` once.
- Spell ids that are secret values are ignored before they are used as table
  keys.
- With `/gst debug` on, opening loot prints the mouseover GUID, the target
  GUID, and the slot count.

## 2.0.0

Result of the code quality, modernization and performance audit
(`CODE_AUDIT.md`). No new features; behavior changes are listed explicitly.
Same SavedVariables (`GatherSkillTooltipDB`); existing data is migrated in
place on first load.

### Fixed

- A gather cast is attributed to the hovered node only if the hover happened
  within the last 15 seconds; hovering an unknown object or an ambiguous
  stack of minimap pins clears the memory (CQ-001).
- "Cannot be skinned" is learned only for your own corpse after you have
  fully looted it, so the missing "Skinnable" line on an unlooted corpse no
  longer marks an NPC as unskinnable (CQ-002).
- SavedVariables are versioned and validated on load: legacy minimap angle
  and position values are migrated once, string-keyed skill counts become
  numeric, and any option with a wrong type resets to its default
  (CQ-004, CQ-005).
- The tracking warning's aura check was inert in combat on this client; the
  warning now uses the minimap tracking list only (COMPAT-002).

### Changed

- Skinnable creature types are matched by numeric creature type id first,
  with the localized name as fallback; the "Skinnable" text uses the client's
  own `UNIT_SKINNABLE_LEATHER` string (COMPAT-003, COMPAT-004).
- Tracking, loot and aura events are registered only while the feature that
  needs them is enabled; tracking checks are coalesced into one timer
  (PERF-001, ARCH-002).
- One unit/NPC resolution per hover; tooltip data lines are trusted before
  font strings are scanned; warning texts and skinning bands are cached
  (PERF-002, PERF-003, PERF-004).
- Fallbacks for other clients (`UnitIsTapped*`, `GetSpellInfo`,
  `OnTooltipSetUnit`, API existence guards) were removed; the addon targets
  the Forever client only (COMPAT-005).
- `Core.lua` was split into per-concern files (see `README.md`), with a
  dispatch table for events and a shared banner factory (ARCH-001..004).
- `/gst stats` prints diagnostic counters for the GameTooltip fallback.

### Development

- Git repository, LF line endings, `.luacheckrc`, repo-local LuaLS
  annotations, `.pkgmeta`, GitHub Actions for luacheck/tests and packaging.

## 1.9.0

Snapshot tagged `v1.9.0-baseline`. This is what that build contained. It is
not a list of features introduced in 1.9.0, because earlier releases are not
in git. Source files: `Core.lua`, `Data.lua`, `Locales.lua`, `Options.lua`.

- Herb and ore tooltips in the world and on minimap pins, including stacked
  pins, with your skill, the required skill, and difficulty colors.
- Skinning skill beside the level of a creature you can skin, and learning
  which NPCs can be skinned.
- Learned gather colors from skill-ups and misses.
- On-screen warnings when Find Herbs or Find Minerals is off, and when a
  profession needs the next trainer rank.
- Settings panel, `/gst`, a minimap button or LibDBIcon when that library is
  present, and an addon compartment button.
- Forever only (`## Interface: 16001`, `## AllowLoadGameType camelot`).

## Before v1

Alpha builds. No changelog for those.
