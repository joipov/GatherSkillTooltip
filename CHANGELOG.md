# Changelog

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

## Before 1.9.0

Those releases are not in version control. The only older version named in
the repository is 1.8.0: the 1.9.0 audit calls persisting "cannot be skinned"
on an NPC id a 1.8.0 feature. No other version numbers or release notes exist
in the repo.
