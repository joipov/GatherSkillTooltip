# Gather Skill Tooltip audit — 2026-10-11

Target: World of Warcraft Forever, game type `forever` (was `camelot`), `## Interface: 16001`, Lua 5.1.
References: the Atraeau Forever API dump (build 70170), Warcraft Wiki (Patch 1.60.1 API changes, Patch 12.0.0 secret values), Ketho's vscode-wow-api annotations, the sibling Joipov addons.

Scope: every `.lua`, the `.toc`, `tests/run.lua`, and the docs. `assets/`, `.release/`, and the locale files' wording are not re-audited here.

## Findings and what was done

### B1 — Secret spellcast id compared without a guard
`Learning.lua` `OnGatherCastStop` / `OnGatherCastSucceeded` compared `gatherWatch.spell == spellID`. **Fixed** — return early when `SecretBlocked(spellID)`.

### B2 — Unit tooltip data read before a table check
`Skinning.lua` `UnitFromTooltip` read `data.guid` after only a nil check. **Fixed** — `ns.CanIndex(data)` first.

### B3 — `LEARNED_NODE` missing from the non-English locales
**Not changed** — the chat line falls back to English. Adding translations without a native check would be worse than the fallback; revisit when the locales are next edited.

### B4 — Learned custom-node names show in English
`GatherSubject` returns the English key. **Not changed** — cosmetic; the learned data is correct.

### B5..B11 — Learning, skinning, and threshold edge cases
Reviewed. Left as documented behavior; no crash or data loss. `lastSkinLevel`, the loot fallback, and the cast-start skill refresh are unchanged.

### CQ-001 — Minimap position in two places
`db.minimapAngle` and `db.minimapIcon.minimapPos` could disagree, and `SyncMinimapIconPosition` re-derived one from the other. **Fixed** — one key, with a migration. `ns.DB_VERSION` is exported for the tests.

### ARCH-001 — Dead code
`ns.DB_DEFAULTS` is used by nothing. **Removed.**

### TOOL-001 — luacheck
`GetLocale` was listed but unused. **Removed.** The header comment no longer claims a fixed count of globals.

### TOC-001 — Game type
Updated to `forever` plus `## ExcludeLoadGameType: standard, classic`. Revert to `camelot` on a pre-70291 build.

## Verification

- `luacheck .` — clean.
- `luajit tests/run.lua` — 29 passed.
- LuaLS with Ketho's annotations — clean.

## In-game checklist

- Hover a herb and an ore: current and required skill both show and color correctly.
- Hover a skinnable corpse: the skinning line shows.
- The tracking warning appears when Find Herbs / Find Minerals is off.
- The trainer reminder appears at the skill cap.
- `/gst` and the compartment open settings; `/gst reset` restores defaults.
- The minimap button drags and keeps its place after `/reload`.
- The addon loads (`/dump C_AddOns.IsAddOnLoaded("GatherSkillTooltip")`).
