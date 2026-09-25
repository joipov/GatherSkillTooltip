# Changelog

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

Baseline as shipped before the audit (git tag `v1.9.0-baseline`).
