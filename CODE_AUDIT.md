<!-- 2.0.1 audit, 2026-09-26. Forever / camelot, Interface 16001. The 2.0.0 record is Appendix A and Appendix B. -->

# GatherSkillTooltip audit (2.0.1)

Target: World of Warcraft Forever, game type `camelot`, `## Interface: 16001` (same TOC version as HealPerMana on this client). Forever uses the mainline UI family, including Midnight secret values ([Wowhead, Forever addon API](https://www.wowhead.com/news/wow-forever-will-have-addon-changes-from-midnight-382921)). Lua runtime is 5.1.

Phase 1 is implemented. Phase 2 deletions were not made: no in-game session was available, and this plan forbids those edits without one. Both outcomes are in Appendix C.

## Coverage

Read in full: `GatherSkillTooltip.toc`, `Data.lua`, `Database.lua`, `Locales/enUS.lua`, `Locales/deDE.lua`, `Locales.lua`, `TooltipText.lua`, `Skills.lua`, `Nodes.lua`, `Tooltip.lua`, `Skinning.lua`, `Learning.lua`, `Warnings.lua`, `MinimapButton.lua`, `Events.lua`, `Options.lua`, `tests/run.lua`, `.luacheckrc`, `.luarc.json`, `.pkgmeta`, both GitHub workflows, README, CHANGELOG, `.annotations/GatherSkillTooltip_Globals.lua`, and the open-verification list in Appendix B.

Other locale files (`esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `zhCN`, `zhTW`): not read line by line. A repo-wide search shows `LEARNED_NODE` exists only in enUS, and no locale file aliases `Wilted Peacebloom`, `Stunted Silverleaf`, or the copper-variant English names.

Not reviewed, and why: `.release/` (packager output), SavedVariables (player data), Blizzard interface source (not extracted from CASC). The LuaLS library path in `.luarc.json` (`C:/Users/rubin/.cursor/extensions/ketho.wow-api/Annotations/Core`) is not present on disk here, so Ketho annotations were not opened. API signatures below come from Warcraft Wiki (current mainline pages) and from this client's own addon usage.

External references actually used:

- [UNIT_SPELLCAST_SUCCEEDED](https://warcraft.wiki.gg/wiki/UNIT_SPELLCAST_SUCCEEDED): payload is `unitTarget, castGUID, spellID, castBarID` (`castBarID` added in 12.0.0). The handlers in `Events.lua` take the third argument as `spellID`. That matches.
- [Secret values](https://warcraft.wiki.gg/wiki/Secret_Values): `SecretWhenUnitSpellCastRestricted` applies when the unit is not the player or their pet. This addon registers spellcast events with `RegisterUnitEvent(..., "player")`, the same filter `EllesmereUIQuickdraw.lua` uses before it reads `spellID`.
- [GetProfessionInfo](https://warcraft.wiki.gg/wiki/API_GetProfessionInfo) and [C_Spell.GetSpellName](https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellName): return order and names match `Skills.lua` and `Locales.lua`. `GetSpellName` is not documented as a secret return.
- Tooltip post-calls match the pattern already used on this client by EllesmereUI and RaiderIO (`TooltipDataProcessor.AddTooltipPostCall`). Settings checkboxes match HealPerMana's `Settings.RegisterAddOnSetting` usage. `.luacheckrc` already follows the BigWigs style the file header describes (Lua 5.1, explicit read globals, a short write-globals list).

## Part 1 — Executive summary

The 2.0.0 structure should stay. One addon namespace (`ns`), TOC load order, saved-variable validation in `Database.lua`, secret-value guards in `TooltipText.lua`, lazy frames, and a single event frame with a dispatch table are the right size for this addon. There is no accidental global write beyond the five names `.luacheckrc` allows. There are no protected-function calls, no secure templates, and no `pcall` that hides errors. Frame creation during combat (the tracking banner) is on an unprotected frame and is allowed.

What is not in good shape is the 2.0.1 "learn an unknown herb or ore from the last hovered name" path, and one field in the older learning model:

- A successful herbalism or mining cast persists whatever unmatched object name was hovered in the last 15 seconds. A chest, quest object, or a localized node name that has no alias becomes a permanent `customNodes` entry whose orange skill is the player's skill at that cast, not the node's real band.
- `gainedAt` stores the highest skill that ever granted a point. `EffectiveOrange` treats that same number as a lowered orange threshold. A later skill-up at or above the table orange throws away the earlier, lower observation. The displayed required skill jumps back up.

Several items from Appendix B were never closed: `UNIT_AURA` is still registered, the GameTooltip `OnShow` fallback is still installed, the Corpse tooltip post-call is still registered, and creature-type ids are still an in-game check. Those are not new defects. They should not be deleted without the session Appendix B already described.

No CPU or memory number was measured. Nothing below promises a percentage improvement.

## Part 2 — Findings register

### CQ-101 — Unmatched hover names are saved as nodes

- Category: Correctness
- Severity: High. One gather writes SavedVariables. The entry then wins future tooltips and can crowd out the real band.
- Location: `Learning.lua` `OnGatherCastSucceeded`; `Tooltip.lua` `RememberUnknown` / `RecentUnknownName`; `Nodes.lua` `LearnCustomNode`.
- Evidence: On cast success, any herb or mine spell calls `RecentUnknownName()` and, if a name is stored, `LearnCustomNode`. Known-node memory and unknown-name memory are cleared together, but the unknown name is not captured at cast start. Any Object or Minimap line that `ExactNode` misses (chest, door, quest object, or a real node whose client name is not in `LOOKUP`) is eligible for 15 seconds. `LearnCustomNode` does not check that the cast was the one started on that object.
- Problem: False names persist for the account. A real Forever or localized name that should share Peacebloom's band is stored with `orange = current skill`, then `+25/+50/+100`, so the tooltip requirement is wrong until a later gather happens to be at a lower skill.
- Recommendation: At `OnGatherCastStart`, snapshot the unknown name the same way the node key is snapshotted. On success, learn only that snapshot, and only when the snapshot cast had no known node key. Do not call `RecentUnknownName()` again at success. Leave the remaining hole documented: if the herb tooltip never replaces a previous unmatched name before the cast starts, that older name can still be learned. Do not add a denylist of object words.
- Risk: A gather whose tooltip appears only after the cast starts would no longer learn. That is the safer direction.
- Verification: Unit-test the snapshot (chest name, then a known node cast, must not save the chest; unknown name snapshotted at start must save even if the tooltip changes before success). In game, hover a chest, gather Peacebloom within 15 seconds with the Peacebloom tooltip showing first, and confirm `customNodes` has no chest entry. `/gst debug` should still print unmatched real node names so aliases can be added.

### CQ-102 — Highest gain overwrites a lowered orange threshold

- Category: Correctness
- Severity: High for the displayed requirement. The per-skill gain and miss counts are kept; only the threshold number and `EffectiveOrange` are wrong after the second gain.
- Location: `Nodes.lua` `NoteGatherResult` and `EffectiveOrange`. The test in `tests/run.lua` locks in "gainedAt tracks the highest gain" and never runs the two-step sequence.
- Evidence: A gain sets `gainedAt` when `skill > obs.gainedAt`. `EffectiveOrange` returns `gainedAt` only while it stays below `band.orange`; otherwise it returns the table value. Tin Vein is orange at 65. A gain at 60 lowers the requirement to 60. A later gain at 80 sets `gainedAt` to 80 and the requirement returns to 65. The skill-up at 60 is still in `obs.gains[60]`.
- Problem: The 2.0.0 changelog behavior ("a skill-up below the table orange lowers it") does not survive normal play, because the next skill-up is usually higher.
- Recommendation: Store the lowered threshold separately and only decrease it (`orangeSeen`): set it when a gain's skill is below the table orange and below the stored value. Keep `gainedAt` as the highest gain so `GainedAtOrAbove` stays as it is. Add a test: gain at 60 then gain at 80 on Tin Vein leaves `EffectiveOrange` at 60. Existing saved `gainedAt` values can seed `orangeSeen` once, when `gainedAt` is below the table orange, in a version-3 migration.
- Risk: Nodes that already lost the low threshold stay at the table value until the next low skill-up. No tooltip color formula changes besides the orange number.
- Verification: The new unit test, plus one in-game Tin or Silverleaf gather below orange, then another above orange, with the `(skill/required)` number staying at the lower skill.

### CQ-103 — Looted-corpse GUID can be the target, not the corpse

- Category: Correctness
- Severity: Medium. Wrong `skinIds[npcID] = false` is permanent and suppresses the skinning line.
- Location: `Learning.lua` `OnLootOpened`, consumed by `CorpseLooted` and `Skinning.lua` `LearnSkin`.
- Evidence: `pendingLootGuid = DeadUnitGUID("mouseover") or DeadUnitGUID("target")`. If mouseover is already clear and the target is a different dead NPC, that other GUID is marked fully looted when the slot counter hits zero. `LearnSkin` will then treat a missing "Skinnable" line on that NPC as negative evidence.
- Problem: Vanilla loot has no looted-unit argument on `LOOT_OPENED`, so this fallback was a reasonable guess. It can condemn the wrong NPC.
- Recommendation: Do not change the fallback until one debug session shows whether mouseover is still the corpse when `LOOT_OPENED` fires. If mouseover is reliable, delete the target fallback. If mouseover is often nil, keep target only when it equals the last unit tooltip NPC, not any dead target.
- Risk: Dropping the fallback too early stops negative learning ("cannot be skinned") whenever mouseover has already cleared.
- Verification: `/gst debug` line on `LOOT_OPENED` with mouseover GUID, target GUID, and slot count. Confirm an unlooted second corpse is not written to `skinIds`.

### CQ-104 — New strings and Forever names are English-only

- Category: Compatibility
- Severity: Medium. Combined with CQ-101, a non-English object name becomes a custom node instead of an alias.
- Location: `LEARNED_NODE` and the updated `LEARN_CHAT_TIP` are only in `Locales/enUS.lua`. No file under `Locales/` maps Wilted Peacebloom, Stunted Silverleaf, or Poor/Minor/Lesser/Small Copper Vein. deDE was read in full and confirms the classic aliases are present and those names are absent. `RegisterLocale` keeps the English string when a key is omitted, so the chat line is English inside a translated addon rather than a nil crash.
- Evidence: Repo search for `LEARNED_NODE` and `Wilted Peacebloom` outside enUS and `Data.lua`.
- Problem: Settings help and the learn chat line drift. A client name that is not the English table key is learned as a new node (CQ-101) with the wrong orange.
- Recommendation: After CQ-101, collect unmatched names from `/gst debug` on the client locale in use and add those aliases to the matching locale file, pointing at the English `ns.NODES` key. Add `LEARNED_NODE` (and the herb/ore clause of `LEARN_CHAT_TIP`) to each locale. Do not invent Forever object translations that `/gst debug` has not shown.
- Risk: A wrong alias attaches a node to the wrong band. Only add names the client actually displays.
- Verification: On that locale, Wilted Peacebloom or its real client name tooltips as the Peacebloom band, and the learn chat line is in that language.

### CQ-105 — Custom-node orange can be the post-skill-up value

- Category: Correctness
- Severity: Low. Off by one skill point on the first learn.
- Location: `Learning.lua` `OnGatherCastSucceeded` calls `RefreshSkills` immediately before `LearnCustomNode`.
- Evidence: If `SKILL_LINES_CHANGED` has already raised the base skill, the orange stored for a brand-new name is the new skill, not the skill the gather started at.
- Recommendation: Pass the skill snapshotted at cast start. Fold this into the CQ-101 snapshot so there is one cast record.
- Risk: None if the snapshot is the pre-cast skill.
- Verification: Learn a new name on a gather that also skills up; orange equals the skill before the point, not after.

### COMPAT-101 — UNIT_AURA is still a tracking trigger

- Category: Compatibility / performance
- Severity: Medium only if the event is useless. The handler is cheap when a timer is already pending. Not a confirmed bug.
- Location: `Warnings.lua` `TRACKING_EVENTS`; handler in `Events.lua`. Appendix B already says to remove it if debug never shows `after UNIT_AURA`.
- Evidence: Tracking state is read only from `C_Minimap.GetTrackingInfo`. `UNIT_AURA` does not change that answer. It still schedules `QueueTrackingCheck`.
- Recommendation: Leave it until a `/gst debug` session. If the warning only changes after `MINIMAP_UPDATE_TRACKING`, `PLAYER_REGEN_ENABLED`, or `watchdog/other`, delete the unit-event entry and the handler line.
- Risk: If some tracking changes on this client are delivered only as auras, the banner would wait up to the 1 second watchdog.
- Verification: One play session with the warning toggling. Record which trigger string appears.

### COMPAT-102 — Spell id is used as a table key without a secret check

- Category: Security
- Severity: Low. Not a confirmed defect.
- Location: `ProfessionForGatherSpell`; `Events.lua` `TRACKING_SPELLS[spellID]`.
- Evidence: Warcraft Wiki marks unit spellcast data secret when the unit is not the player or pet, with a per-spell override that can force secrecy. These events are player-only. Indexing with a secret key throws. Every other combat value in this addon goes through `SecretBlocked` first.
- Recommendation: If `ns.SecretBlocked(spellID)` then return before the table index. One guard in `ProfessionForGatherSpell` and one before the tracking-spell lookup.
- Risk: An always-secret gather spell would stop learning for that cast instead of erroring. That is the right failure.
- Verification: Gather in combat (or while flagged) and confirm no secret-value error and that the node still records.

### UI-101 — GameTooltip OnShow fallback is still on every typeless tooltip

- Category: UI
- Severity: Medium as ongoing work, not as a measured cost. `stats.shown` increments for every GameTooltip show while the addon is enabled; typed tooltips return immediately.
- Location: `Events.lua` fallback block. Calling `tooltip:Show()` from `OnShow` does not re-enter `OnShow` on an already-shown frame, so this is not an infinite loop.
- Recommendation: Keep until `/gst stats` after a full session. If `applied` is 0, delete the hook, the stats table, and the `/gst stats` command. If `applied` is non-zero, keep the hook and note which tooltip it was.
- Risk: Removing it blindly drops nodes that never get a `TooltipDataType`.
- Verification: `/gst stats` numbers from a session that included world nodes, minimap pins, items, and spells.

### UI-102 — Corpse and Unit post-calls both run

- Category: UI
- Severity: Low. `LearnSkin` is idempotent (`previous ~= true`). The second pass strips and rewrites the level line.
- Location: `Events.lua` Unit and Corpse `AddTooltipPostCall` lines. Appendix B already says the Corpse registration can go once a dead NPC is shown to arrive as Unit.
- Recommendation: Remove the Corpse line only after a dead, skinnable NPC shows the skinning line with that line deleted on a test copy, or after debug shows the Unit post-call is what drew it.
- Risk: A corpse that is not a Unit tooltip would lose the skinning line.
- Verification: Dead beast, own loot, skinning suffix present.

### ARCH-101 — Gather-spell lookup lives in the warning module

- Category: Architecture
- Severity: Low. Works because `Events.lua` loads last and the call is at event time, not file-load time.
- Location: `ns.ProfessionForGatherSpell` in `Warnings.lua`, called from `Learning.lua`.
- Recommendation: Move the function next to `ns.GATHER_SPELLS` in `Data.lua` when CQ-101 is edited. No other split.
- Risk: None if the function body stays a `GATHER_SPELLS` lookup plus the secret guard.
- Verification: Existing `GATHER_SPELLS` unit test, plus a gather still records.

### ARCH-102 — Checkbox defaults are a second copy of Database defaults

- Category: Architecture
- Severity: Low. `LoadDB` runs before `InitOptions`, so the Settings default is unused as long as every key is filled.
- Location: `defaults` in `Database.lua` and the `default` argument in `Options.lua` `AddCheckbox`.
- Recommendation: Pass `defaults[key]` into `AddCheckbox` instead of a separate literal. Do this only while already editing `Options.lua`. Not scheduled: phase 1 does not edit that file.
- Risk: A key missing from `defaults` would error. That is desirable.
- Verification: Fresh SavedVariables still open with herbalism on and minimap button off.

### TOOL-101 — LuaLS WoW library path does not resolve here

- Category: Tooling
- Severity: Medium for the editor, not for the game.
- Location: `.luarc.json` `workspace.library` absolute path. CI runs luacheck and `lua 5.1.5 tests/run.lua` only, which is appropriate.
- Recommendation: Keep luacheck as the CI gate. Point `workspace.library` at a repo-relative annotations checkout, or install the Ketho extension so the absolute path resolves. Do not add a new linter. The repo-local `.annotations/GatherSkillTooltip_Globals.lua` stays; it covers Settings and `TooltipDataProcessor`, which Ketho Core does not define for this addon.
- Risk: A wrong library version would flag real Forever APIs as undefined.
- Verification: LuaLS `undefined-global` clean on `Events.lua` with the library actually loaded.

### TOOL-102 — Tests never load the tooltip memory or the gather watch

- Category: Tooling
- Severity: Medium. CQ-101 and CQ-102 are both untested paths. `Tooltip.lua` only captures `GetTime`; it does not call the client at file load, so the test harness can load it once `GetTime` is stubbed. Do not load `Events.lua`, `Options.lua`, or `Warnings.lua` under plain Lua.
- Recommendation: Extend `tests/run.lua` for: unknown-name snapshot versus known-node cast, 15 second expiry, Tin Vein gain-at-60 then gain-at-80, and custom-node orange not rising.
- Risk: None for the game client.
- Verification: `lua 5.1 tests/run.lua` exits 0.

### Rejected as changes

- Caching `FormatNode` strings. Tooltip hovers are not per-frame, and the string depends on skill, options, and learned color.
- Unregistering the four player spellcast events while the addon is disabled. The handler returns on the first table lookup. No profile shows this matters.
- Replacing `GetProfessions` / `GetProfessionInfo`. The wiki signature matches the destructure in `Skills.lua`. Vanilla rules are two primary professions; herb, mine, and skin are those professions.
- Removing secret-value checks. Forever runs Midnight's secret rules.
- Rewriting modules, adding a library, or embedding LibDBIcon. OptionalDeps plus the built-in button is the right split.

## Part 3 — Remediation roadmap

Phase 1, correctness:

- CQ-101 snapshot-at-cast-start. Benefit: stops false `customNodes`. Complexity: Small. Regression: a node whose tooltip appears only after the cast may not learn until the next hover-then-gather. Accept when a chest hover followed by a Peacebloom gather does not create a chest entry, and a genuine unknown name still creates one.
- CQ-102 separate orange floor, plus a one-time seed from an existing low `gainedAt`. Benefit: required skill stays lowered. Complexity: Small. Regression: grey-versus-green behavior must stay on `gainedAt` and the per-skill counters. Accept when the Tin Vein test passes and an in-game second gather does not raise the number.
- CQ-105 fold into the same cast snapshot. Complexity: Small.
- ARCH-101 move `ProfessionForGatherSpell` in the same edit. Complexity: Small.
- COMPAT-102 secret guard before spell-id indexing. Complexity: Small. Included in phase 1; it does not change successful player casts.
- TOOL-102 tests for the above. Complexity: Small. This is the acceptance gate before any in-game pass.

Phase 2, only after an in-game session (do not code these from the audit alone):

- CQ-103 loot GUID, after the debug print says mouseover is or is not valid. Complexity: Small.
- COMPAT-101 drop `UNIT_AURA` only if the debug trigger never names it. Complexity: Small.
- UI-101 delete the OnShow fallback only if `applied == 0`. Complexity: Small.
- UI-102 drop the Corpse post-call only if Unit already draws the line. Complexity: Small.
- CQ-104 add aliases and `LEARNED_NODE` from names the client actually shows. Complexity: Small per locale, blocked on those names.

Not scheduled: ARCH-102 (no `Options.lua` edit in phase 1), performance micro-opts from the reject list, any further file split, embedding libraries.

## Part 4 — Performance

Supported by code, worth doing only after the existing counters say so:

- `UNIT_AURA` on the player while the tracking warning feature is on (COMPAT-101). High event rate, coalesced to one 0.5 second timer, so the cost is a Lua call per aura, not a tracking scan per aura. Remove only with the debug evidence.
- GameTooltip `OnShow` fallback (UI-101). Runs for every typeless tooltip show, then returns when `data.type` is set. Removal is a complexity win more than a frame-time win. Decide from `/gst stats`.

Hypotheses, do not implement: string garbage in `FormatNode` and stacked-pin `table.concat`; `RefreshSkills` twice when a skill event arrives during a pending watch; `lootedCorpses` retained until the next loot close (pruned at 600 seconds, bounded by corpses looted). None of these is on a per-frame path. The only `OnUpdate` scripts are the 1 Hz warning watchdog while that banner is shown, and the minimap button while it is being dragged.

In-game procedure when a profile is needed, no numbers invented: `/console scriptProfile 1`, reload, hover a node, open and close the warning, skin one corpse, then `/console scriptProfile 0` and read the script profiler for `ApplyTooltip`, `OnUnitTooltip`, `CheckTracking`, and the `OnShow` hook. Baseline is the current build. Compare only after a phase 2 removal, same route. The 2.0.0 measurement snippets in Appendix A are still unfilled.

## Part 5 — Standards for this repository

These match the code that is already there. They are the bar for later edits.

- Lua 5.1 only. No `goto`, no bitwise operators, no `<const>`.
- Locals by default. New globals require a `.luacheckrc` entry and a reason. The allowed writes are `GatherSkillTooltipDB`, the two slash strings, `SlashCmdList.GATHERSKILLTOOLTIP`, and `GatherSkillTooltip_OnAddonCompartmentClick`.
- Shared state goes on `ns`. Cross-file calls happen at event time. Files must not depend on a later TOC file at load time.
- WoW API calls at file load stay in `Events.lua`. Frames are created on first use.
- Combat values go through `SecretBlocked` / `ReadableString` / `CanIndex` before compare, length, concat, or table key use. Player spell ids get the same guard.
- Events are registered while the feature is on. Tracking checks stay on the one shared timer. No new always-on `OnUpdate`.
- SavedVariables go through `LoadDB`. New persistent shapes bump `DB_VERSION` and migrate once.
- Difficulty colors and orange math stay in `Nodes.lua` and keep a unit test when the rule changes.
- Do not add a library for a problem the current file can handle. LibDataBroker and LibDBIcon stay optional.
- CI stays luacheck plus Lua 5.1 tests. In-game checks stay the list in Part 6. LuaLS is editor-only and must see a real API library plus `.annotations`.

## Part 6 — Checklist for a later implementation session

1. This file is the audit. Appendix A and Appendix B stay so the 2.0.0 IDs still resolve.
2. Phase 1 code: cast snapshot, orange floor, migration, secret guard, move `ProfessionForGatherSpell`, tests.
3. Run `lua 5.1 tests/run.lua` (or LuaJIT) and `luacheck .`.
4. In game, enUS: Peacebloom and Copper Vein in the world and on a stacked minimap pin; an unknown object still does not rewrite the tooltip; chest hover then herb gather does not add a custom node; a real unknown name still learns; Tin or equivalent stays at the lowered requirement after a higher skill-up; skinning line on a looted beast; no line on a living humanoid; tracking banner in and out of combat; `/gst` opens settings; BugSack clean.
5. Record `/gst stats` and, with `/gst debug`, the tracking trigger, the new loot-open line, and `UnitCreatureType` ids. Only then schedule phase 2 deletions.
6. One non-enUS client, or a locale test that the new alias is in `LOOKUP` and `LEARNED_NODE` is not the English sentence.
7. No profiler comparison until a phase 2 deletion exists to compare.

---

# GatherSkillTooltip: Code Quality, Modernization and Performance Audit (2.0.0)

## 0. Scope, method and evidence

**Repository**: `c:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\GatherSkillTooltip` (v1.9.0). Not a git repository.

**Files inspected (100% coverage, every line read)**:
- `GatherSkillTooltip.toc` (25 lines)
- `Core.lua` (1613 lines): skills cache, node tooltip rewrite, skinning tooltip line, learning/observation system, tracking warning, trainer reminder, minimap button, event dispatch, tooltip hooks
- `Data.lua` (89 lines): skill line / spell constants, node difficulty bands
- `Locales.lua` (1087 lines): UI strings for 11 locales, localized node aliases for 9 locales, `ns.SpellName`, `ns.ProfessionName`, `ns.SKIN_TYPES`
- `Options.lua` (159 lines): Settings panel, slash commands, compartment click
- `.luarc.json` (LuaLS config)
- Also inspected: live SavedVariables `WTF\Account\...\SavedVariables\GatherSkillTooltip.lua` (real DB shape), `!BugGrabber`/`BugSack` saved variables (no recorded Lua errors from this addon), client `.build.info`/`.flavor.info`.

**Unreviewed**: none. **Gaps**: no in-game profiling data exists yet; no version history exists to compare against.

**Target client (confirmed)**: `wow_classic_beta`, build 1.60.1.70009, game type `camelot` (WoW: Forever). Per Blizzard's UI team (via Wowhead, Sep 2026) Forever shares Mainline's 12.1.5-era UI architecture including secret values. The TOC restricts loading to this single flavor (`## Interface: 16001`, `## AllowLoadGameType camelot`), so multi-client hedging in code buys nothing.

**Authoritative references used (verified, not assumed)**:
- Blizzard UI source, Gethe/wow-ui-source branch `forever`, HEAD commit `bd2470a` titled "1.60.1 (70009)" (identical to installed build): `Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua`, `Blizzard_GameTooltip/Mainline/GameTooltip.lua`, `Blizzard_Settings_Shared/Blizzard_Settings.lua`, `Blizzard_Setting.lua`, `Blizzard_SettingControls.lua`, `Blizzard_APIDocumentationGenerated/{Unit,UnitAura,TooltipInfo,Minimap,Spell,FrameScript,SecretPredicates,AddOnProfiler}Documentation.lua`, `Blizzard_Minimap/Mainline/AddonCompartment.lua`
- Ketho WoW API annotations (installed extension `ketho.wow-api` 0.22.3, `Annotations/Core`)
- warcraft.wiki.gg: Secret Values, TOC format (`AllowLoadGameType`, `AllowLoadTextLocale`, `Category`)
- BigWigs `.luacheckrc` (WoW luacheck conventions), LibDBIcon-1.0 minor 56 (local copy in BigWigs\Libs)

---

## Part 1: Executive summary

**Overall condition**: This is a small, disciplined, single-purpose addon. Global hygiene is excellent (a scan found zero accidental globals; only 5 intentional globals: the SavedVariables table, the compartment callback, two `SLASH_` strings and one `SlashCmdList` entry). API bindings are cached as file locals. The secret-value handling follows the documented rules (no comparisons/arithmetic/length on secrets, `type()` checks first, concatenation only). Event registration uses `RegisterUnitEvent` for player-only unit events. The `OnUpdate` watchdog is scoped (only while the warning is visible). Every API used exists in build 70009 with the signature the code assumes (`Settings.RegisterAddOnSetting(categoryTbl, variable, variableKey, variableTbl, variableType, name, defaultValue)`, `SettingMixin:SetValueChangedCallback`, `TooltipDataProcessor.AddTooltipPostCall`, `C_Minimap.GetTrackingInfo` returning `{active, spellID}`, `UnitCreatureType` returning `(name, id)`, `UnitTokenFromGUID`, `C_UnitAuras.GetPlayerAuraBySpellID`, `C_TradeSkillUI.GetProfessionInfoBySkillLineID`, `C_Spell.GetSpellName`, `issecretvalue`/`canaccessvalue`/`issecrettable`/`canaccesstable`).

**Major risks found** (details in Part 2):
1. **Learned-data misattribution** (CQ-001): `lastNodeKey` has no staleness/reset, so gathering an unrecognized node after hovering a recognized one records the gain/miss against the wrong node.
2. **Skinning false negatives** (CQ-002, needs in-game confirmation): an own-kill corpse hovered before looting has no "Skinnable" line and is recorded as "cannot be skinned" (self-corrects later, but emits a wrong chat line and temporarily hides the skill line).
3. **Deprecated tooltip accessor** (COMPAT-001): `tooltip:GetTooltipData()` is annotated "to be deprecated" in this build's `TooltipDataHandler.lua`; `GetPrimaryTooltipData()` is the current name.
4. **Aura path is inert in combat** (COMPAT-002): `C_UnitAuras.GetPlayerAuraBySpellID` is flagged `RequiresNonSecretAura` in build 70009, i.e. it returns nothing under combat aura restrictions. The "combat fix" from 2026-09-23 therefore works because of the minimap fallback and the 1 s watchdog, not the aura check.
5. **No version control / no repeatable tooling** (TOOL-001..003): the only copy of the code lives in the game folder; LuaLS config depends on a hand-placed file inside the extension directory that an extension update will delete.
6. **Maintainability**: `Core.lua` (1613 lines) mixes seven concerns; roughly 80 to 120 lines are multi-client fallbacks that are dead on this client (`UnitIsTapped`, `GetSpellInfo`, `OnTooltipSetUnit`, `Settings.SetOnValueChangedCallback`, existence guards on core APIs).

**Performance**: no demonstrated bottleneck; this addon is human-paced (tooltip hovers, casts). The two measurable hot spots are (a) `UNIT_AURA(player)` handling that cancels and recreates a `C_Timer` plus a closure on every player aura change, even when the tracking warning feature is disabled, and (b) the `GameTooltip:OnShow` fallback that runs node lookup on every non-data tooltip in the UI. Both are cheap per call but are the only paths that run at high frequency.

**Requires in-game verification** (cannot be settled from source alone): whether the `OnShow` fallback ever produces a match on this client; `Enum.TooltipDataType` of dead NPCs (Unit vs Corpse); creature type IDs for Beast/Dragonkin; `UNIT_SKINNABLE_LEATHER` presence; whether `GameTooltip.TextLeft1` keys or `GameTooltipTextLeft1` globals are the live path; the loot-before-"Skinnable" behavior.

---

## Part 2: Findings register

Severity rationale: Critical = breaks the addon or corrupts user data broadly; High = wrong behavior users will hit, or blocks safe development; Medium = incorrect in realistic edge cases, or measurable waste; Low = maintainability/cleanliness with negligible runtime effect.

### Correctness

- **CQ-001** | Correctness | **Medium**
  - Location: `Core.lua` `ApplyLine` (L422-439), `GatherKey` (L983-995), `ArmGatherWatch` (L997-1023)
  - Evidence: `lastNodeKey`/`lastNodeProf` are set whenever any recognized herb/ore tooltip is shown (world or minimap pin) and never cleared. `ArmGatherWatch` uses them at `UNIT_SPELLCAST_START` with only a profession check.
  - Problem: Hover "Copper Vein", then gather a node whose name is not in `ns.LOOKUP` (new Forever node, alias gap, secret/blocked text). The gain/miss is written to `db.gather["Copper Vein"]`. In the multi-pin minimap path (L466-484) `lastNodeKey` ends as the last matched line, not the node the player walks to. Learned data silently drifts.
  - Recommendation: (1) In `ApplyTooltip`, when an Object/Minimap tooltip is shown whose first line is not a known node, clear `lastNodeKey`. (2) Record `lastNodeTime = GetTime()` and reject keys older than a short window (e.g. 15 s) in `GatherKey`. (3) For multi-line pins, only set `lastNodeKey` when exactly one node matched.
  - Risk: Slightly fewer observations recorded (only where attribution was uncertain). No display change.
  - Verification: Debug print of `(key, spellID)` in `ArmGatherWatch`; hover a known node, then gather an unknown one; confirm no observation is recorded.

- **CQ-002** | Correctness | **Medium** (pending in-game confirmation)
  - Location: `Core.lua` `LearnSkin` (L1367-1401)
  - Evidence: If `TooltipHasSkinnable` is false and `CorpseIsOurs(unit)` and `previous ~= false`, the NPC id is stored as `false` and `LEARNED_SKIN_NO` is printed. Live DB shows 17 `false` entries.
  - Problem: In Classic-rules clients the "Skinnable" tooltip line only appears once the corpse has been looted. Hovering your own unlooted beast corpse yields a false "cannot be skinned" record and chat line; the skill line is hidden until a later hover with the line present flips it back (L1387-1392).
  - Recommendation: Only learn `false` when there is corroborating evidence, e.g. (a) the corpse GUID was seen in `LOOT_CLOSED` (track last looted GUID via `LOOT_OPENED` + `UnitGUID("target")`), or (b) require the negative to be observed on N distinct corpses before persisting, or (c) never persist `false`, only `true`, and keep Beast/Dragonkin as the fallback for unknowns (simplest; loses the Greater Fleshripper suppression).
  - Risk: Option (c) regresses the 1.8.0 feature; options (a)/(b) add a little state.
  - Verification: Kill a beast, hover before looting with `learnChat` on; today a wrong "cannot be skinned" line should appear. After the fix it must not.

- **CQ-003** | Correctness | **Low**
  - Location: `Core.lua` `HasTrackingBuff` (L511-516)
  - Evidence: `return C_UnitAuras.GetPlayerAuraBySpellID(spellID) ~= nil`. Build 70009 marks this API `SecretWhenUnitAuraRestricted = true`.
  - Problem: `~=` is a comparison. If the API ever returns a secret table instead of nothing, the comparison raises. The wiki allows boolean tests on non-boolean secrets but not comparisons.
  - Recommendation: `local aura = ...; return aura and true or false` (truthiness test only). See COMPAT-002 for whether the path should exist at all.
  - Risk: none. Verification: LuaLS clean; in-combat cast of Find Herbs with warning shown produces no error.

- **CQ-004** | Correctness | **Low**
  - Location: `Core.lua` `TryLibDBIcon` (L835-838), ADDON_LOADED handler (L1047-1049)
  - Evidence: `if not pos or (pos >= 210 and pos <= 220) then minimapPos = minimapAngle end` and `if minimapAngle == 220 then minimapAngle = 200 end`.
  - Problem: One-off migration heuristics run on every load and permanently override any user drag into the 210-220 degree band (chat 2026-09-24 confirms these were introduced as a default change from 220 to 200).
  - Recommendation: Add `db.version` (number). Run migrations once in ADDON_LOADED gated on `db.version < N`, then set `db.version = N`. Remove the band check.
  - Risk: none for existing users (their `minimapPos` 200 is preserved). Verification: drag icon to ~215, `/reload`, position must persist.

- **CQ-005** | Correctness | **Low**
  - Location: `Core.lua` `NoteGatherResult` (L920-941), `CountAt` (L213-225)
  - Evidence: `obs = { misses = {} }` immediately followed by `obs.misses = obs.misses or {}`; `CountAt` falls back to `bucket[tostring(skill)]`.
  - Problem: Redundant statement; the string-key fallback is compatibility with an older DB shape. Live DB has only numeric keys.
  - Recommendation: Fold into the versioned migration (CQ-004): convert any string keys once, then drop the fallback and the redundant line.
  - Risk: none. Verification: existing SavedVariables load and counts are unchanged.

### Compatibility (verified against build 70009 source)

- **COMPAT-001** | Compatibility | **Medium**
  - Location: `Core.lua` L446-448, L1587, L1605
  - Evidence: `TooltipDataHandler.lua` (forever): `-- to be deprecated  function TooltipDataHandlerMixin:GetTooltipData() return self:GetPrimaryTooltipData() end`.
  - Problem: Future removal breaks the `OnShow` fallback and the `data == nil` path.
  - Recommendation: Prefer `tooltip.GetPrimaryTooltipData`, keep `GetTooltipData` only as a one-line fallback if the fallback hook survives CQ-007.
  - Risk: none. Verification: hover minimap pin and world node; tooltip still rewritten.

- **COMPAT-002** | Compatibility | **Medium**
  - Location: `Core.lua` `HasTrackingBuff`, `TrackingState` (L511-549); event registration L1056
  - Evidence: `UnitAuraDocumentation.lua` (forever): `GetPlayerAuraBySpellID` has `SecretWhenUnitAuraRestricted = true, RequiresNonSecretAura = true`. Wiki: `RequiresNonSecretAura` "does not raise a blocked action error - instead, protected APIs will return no values." `C_Minimap.GetTrackingInfo` has no secret flags.
  - Problem: In combat (the exact case the 09-23 fix targeted) the aura check returns nil and the code falls through to the minimap loop anyway. The aura path adds an API call and an extra permanent `UNIT_AURA` registration for no benefit in the restricted case; out of combat the minimap loop alone is authoritative.
  - Recommendation: Verify in-game (`/dump C_Minimap.GetTrackingInfo(i)` for each i with Find Herbs on, in and out of combat). If minimap data is reliable in both states, remove `HasTrackingBuff`, the `UNIT_AURA` registration and `TRACKING_QUEUE_EVENTS.UNIT_AURA`; keep `MINIMAP_UPDATE_TRACKING`, `UNIT_SPELLCAST_SUCCEEDED` (tracking spells), `PLAYER_REGEN_ENABLED` and the watchdog.
  - Risk: If `MINIMAP_UPDATE_TRACKING` does not fire in combat, detection relies on the watchdog (1 s) and cast events, which is the current effective behavior anyway.
  - Verification: Toggle Find Herbs in and out of combat with the warning shown; it must clear within ~1 s.

- **COMPAT-003** | Compatibility | **Low**
  - Location: `Locales.lua` `ns.SKIN_TYPES` (L1026-1031); `Core.lua` `CanSkinUnit` L1251-1254
  - Evidence: `UnitCreatureType` returns `(name cstring, id number)` in build 70009. Code compares the localized `name` against hand-translated strings (`CREATURE_BEAST`, `CREATURE_DRAGONKIN`) in 11 locales.
  - Problem: Any translation mismatch silently disables the type fallback for that locale.
  - Recommendation: Use the numeric `id` (expected Beast=1, Dragonkin=2; confirm with `/dump UnitCreatureType("target")`). Delete the 22 translated creature-type strings.
  - Risk: IDs must be confirmed once. Verification: target a beast and a dragonkin on any locale.

- **COMPAT-004** | Compatibility | **Low**
  - Location: `Core.lua` `TextHasSkinnable` (L1295-1302) with `L.SKINNABLE` in 11 locales
  - Evidence: The client ships the global string `UNIT_SKINNABLE_LEATHER` ("Skinnable") plus `UNIT_SKINNABLE_HERB/ROCK/BOLTS` for herbalism/mining/engineering "skinnable" mobs.
  - Recommendation: Match against `_G.UNIT_SKINNABLE_LEATHER` (fallback to `L.SKINNABLE` if nil). Optionally also treat `UNIT_SKINNABLE_HERB/ROCK` as skinnable-by-other-profession (out of scope unless wanted).
  - Risk: none. Verification: `/dump UNIT_SKINNABLE_LEATHER` on this client; hover a skinnable corpse.

- **COMPAT-005** | Compatibility / dead code | **Medium** (maintainability)
  - Location: `Core.lua` L1342-1356 (`UnitIsTapped`/`UnitIsTappedByPlayer`), L1543-1545 (`OnTooltipSetUnit` hook), L140-142, L965, L1220, L1279, L1286, L1386 (existence guards on `GetProfessions`, `UnitExists`, `UnitGUID`, `tooltip.GetUnit`, `UnitTokenFromGUID`, `UnitName`); `Locales.lua` L1065-1072 (`GetSpellInfo`); `Options.lua` L74-75 (`Settings.SetOnValueChangedCallback` branch), L6-7 (`Settings.Default` indirection)
  - Evidence: `UnitIsTapped`/`UnitIsTappedByPlayer` are absent from forever `UnitDocumentation.lua`; global `GetSpellInfo` is not in Mainline since 11.0 (only `C_Spell.GetSpellInfo` exists); `OnTooltipSetUnit` was removed in 10.0.2; `SettingMixin:SetValueChangedCallback` exists in this build (`Blizzard_Setting.lua` L265); `Settings.Default.True` is literally `true`.
  - Problem: ~100 lines of unreachable branches obscure the real logic and imply support the TOC does not claim.
  - Recommendation: Remove branches for APIs confirmed present/absent in 70009. Keep guards only for genuinely optional components: LibStub/LibDBIcon, `Settings` (loads before addons, but cheap to keep one guard in `InitOptions`).
  - Risk: none on the declared client. Verification: LuaLS `undefined-global` stays clean; full smoke test (Part 6).

### Architecture and maintainability

- **ARCH-001** | Architecture | **Medium**
  - Location: `Core.lua` (1613 lines)
  - Evidence: One file holds skill caching, node lookup/formatting, secret-safe tooltip reading, node tooltip rewrite, skinning line, learning/observation persistence, tracking warning + watchdog, trainer reminder, minimap button (two implementations), event dispatch, and two hook strategies.
  - Problem: Hard to test in isolation, hard to review diffs, forward-declared locals (`CheckTracking`, `ReportGatherLearn`) exist only to satisfy file order.
  - Recommendation: Split along existing seams into TOC-ordered files sharing the `ns` table (no framework, no libraries): `Skills.lua` (skill cache), `TooltipText.lua` (secret-safe readers: `SecretBlocked`, `ReadableString`, `CanIndex`, `FontStringByIndex`, `LastLineText`), `Nodes.lua` (herb/ore tooltip), `Skinning.lua` (unit tooltip), `Learning.lua` (observations + gather watch), `Warnings.lua` (tracking + trainer), `MinimapButton.lua`, `Events.lua` (dispatch table + hook registration). Pure functions (`NormalizeName`, `ExactNode`, `DifficultyColor`, `ColorFromRate`, `ObservedColor`, `SkinningOrange`, `NpcIdFromGUID`, `StripSkillSuffix`, `FirstNumber`, `ApplyObservation`) should not touch WoW APIs at load so they can run under plain Lua 5.1 for tests (TOOL-005).
  - Risk: Load-order mistakes; mitigated by keeping cross-file access to `ns.*` functions only and by the smoke test.
  - Verification: Behavior-identical smoke test; LuaLS clean; each file under ~400 lines.

- **ARCH-002** | Architecture | **Low**
  - Location: `Core.lua` event handler (L1038-1130)
  - Evidence: if-chain over event names; `UNIT_AURA` traverses 4 string comparisons before matching.
  - Recommendation: `local EVENTS = {}` keyed by event name, `OnEvent = function(_, event, ...) EVENTS[event](...) end`. Register tracking-related events only while `db.enabled and db.warnTracking` and at least one gathering skill is known (re-evaluate in `RefreshSkills` and the settings callback).
  - Risk: none. Verification: toggling settings adds/removes registrations (`/dump eventFrame:IsEventRegistered("MINIMAP_UPDATE_TRACKING")` via a debug command).

- **ARCH-003** | Architecture | **Low**
  - Location: `Core.lua` `EnsureWarningFrame`/`EnsureTrainFrame` (L495-509, L668-680); `NormalizeName`/`StripInline` (L165-173, L1132-1134)
  - Evidence: Two near-identical frame factories (700x64, `GameFontNormalHuge`, centered); two implementations of color-code stripping.
  - Recommendation: One `CreateBannerFrame()` factory returning `(frame, fontString)`; one `StripColorCodes(text)` used by both paths.
  - Risk: none. Verification: both banners render identically.

- **ARCH-004** | Architecture | **Low**
  - Location: `Core.lua` `GATHER_SPELLS`/`TRACKING_SPELLS` (L642-660) vs `Data.lua` constants; `Locales.lua` L1058-1087 (`ns.SpellName`, `ns.ProfessionName`, `ns.ExampleHerb`); `Locales.lua` L1043 `ns.LOOKUP = ns.NODES`
  - Evidence: Spell-rank tables live in Core while other IDs live in Data; API helper functions live in the locale file; `ns.LOOKUP` aliases the same table as `ns.NODES`, so localized alias keys are written into `ns.NODES` (works only because `Data.lua` assigned `node.key` earlier).
  - Recommendation: Move all IDs/tables to `Data.lua`; move `SpellName`/`ProfessionName` to `Skills.lua`; make `ns.LOOKUP` a distinct table (`{}` copied from NODES then aliases added) or rename to make the aliasing explicit; inline `ExampleHerb`. Add `ns.NODE_BY_KEY` built once in Data.lua to replace the linear `NodeByKey` scan.
  - Risk: none. Verification: LuaLS clean; localized client hover still matches.

- **ARCH-005** | Architecture | **Low**
  - Location: `Locales.lua` (1087 lines, 10 locale UI tables + 9 alias tables constructed at load then `nil`ed)
  - Evidence: TOC format wiki: per-file directive `[AllowLoadTextLocale deDE] Locales/deDE.lua` (files since 11.2.0). Same pattern as BigWigs/Ace locale files (one file per locale, early return).
  - Recommendation: Split into `Locales/enUS.lua` (always) plus one file per locale gated in the TOC with `[AllowLoadTextLocale xxYY]`. Non-matching locales are never parsed. Keep `CopyTable(EN)` + overlay semantics.
  - Risk: TOC directive must be spelled exactly; fallback (if unrecognized, file loads) is safe. Verification: `/dump ns.L.HERBALISM` on enUS and one other locale.

- **ARCH-006** | Architecture | **Low**
  - Location: `Core.lua` `CopyDefaults` (L97-104); `ns.UpdateMinimapButton` (L781-801)
  - Evidence: Shallow defaults only; `showMinimapButton` and `minimapIcon.hide` are two sources of truth kept in sync by hand.
  - Recommendation: Add `db.version`; validate types of `gather`, `skinIds`, `minimapIcon` once at load (replace malformed with `{}`); derive `minimapIcon.hide` from `showMinimapButton` in one place.
  - Risk: none. Verification: load with a hand-corrupted SavedVariables file; addon recovers without error.

### UI and frame management

- **UI-001** | UI / Performance | **Medium**
  - Location: `Core.lua` `GameTooltip:HookScript("OnShow", ...)` block (L1547-1613)
  - Evidence: In build 70009 world objects reach the tooltip via `GameTooltipDataMixin:SetWorldCursor` -> `ProcessInfo` -> `ProcessTooltipPostCalls(tooltipData.type, ...)` (`GameTooltip.lua` L982-1015, `TooltipDataHandler.lua` L245-306), i.e. the same post-call path the addon already registers for `Object` and `MinimapMouseover`. The fallback only proceeds when `data.type == nil`, which on this client means tooltips built with `SetText`/`AddLine` (UI buttons, other addons, our own minimap button tooltip). For every such show it calls `GetTooltipData`, reads TextLeft1, runs `ExactNode` (two `find`s and a table lookup), and may schedule a `C_Timer.After(0)` closure.
  - Problem: Work on every UI tooltip with no evidence it ever matches on this client; plus deprecated accessor (COMPAT-001) and ~65 lines of complexity.
  - Recommendation: Instrument first (debug counter of fallback invocations vs matches, printed via `/gst debug`). Play a session covering world nodes, minimap pins, stacked pins. If matches are 0, delete the block. If it matches, keep but gate on `data == nil` only and drop the retry.
  - Risk: If some world-node tooltip path bypasses post-calls, node rewrite would stop; the instrumentation step removes that uncertainty.
  - Verification: counter output; smoke test on world nodes and pins.

- **UI-002** | UI | **Low**
  - Location: `Core.lua` registration L1538-1540 (`Enum.TooltipDataType.Corpse`)
  - Evidence: `TooltipUtil.GetDisplayedUnit` only resolves `Unit` type; `Corpse` (3) is the player-corpse tooltip. Dead NPCs remain `Unit` tooltips with a `mouseover` token.
  - Recommendation: Verify with a debug print of `data.type` on a dead mob; if always 2, drop the Corpse registration.
  - Risk: none. Verification: skinning line still appears on dead mobs.

- **UI-003** | UI | **Low**
  - Location: `Core.lua` `ApplyDisplay` (L406-420)
  - Evidence: `fs:SetText(display)` lengthens the first line; Blizzard calls `self:Show()` after post-calls (`TooltipDataHandler.lua` L300) which re-lays out, so the post-call path is fine. The `OnShow` fallback path edits during `OnShow` with no subsequent `Show()`.
  - Recommendation: Resolved by UI-001 (removal) or, if kept, call `tooltip:Show()` after editing in the fallback path only.
  - Verification: long node name plus " (300/300)" is not clipped.

### Performance (ranked in Part 4)

- **PERF-001** | Performance | **Medium**
  - Location: `Core.lua` `ns.QueueTrackingCheck` (L625-633); registrations L1054-1056
  - Evidence: Every `UNIT_AURA(player)`, `MINIMAP_UPDATE_TRACKING`, `PLAYER_REGEN_ENABLED`, `SKILL_LINES_CHANGED`, `CHAT_MSG_SKILL` calls `trackingTimer:Cancel()` then `C_Timer.NewTimer(0.5, closure)`: one timer object and one closure allocated per event. `UNIT_AURA` for the player fires on every buff/debuff change (many per second in combat). All three tracking events stay registered even when `warnTracking == false` or the player has no gathering skill.
  - Recommendation: Coalesce instead of debounce: `if trackingTimer then return end; trackingTimer = C_Timer.NewTimer(0.5, OnTrackingTimer)` with a single file-level callback function (no per-event closure). Register the tracking events only while the feature is active (ARCH-002). If COMPAT-002 verification allows, drop `UNIT_AURA` entirely.
  - Risk: Check fires 0.5 s after the first event instead of the last; the watchdog and subsequent events cover late changes.
  - Verification: `C_AddOnProfiler.GetAddOnMetric("GatherSkillTooltip", Enum.AddOnProfilerMetric.CountTimeOver1Ms)` and `GetAddOnMemoryUsage` delta over a 5-minute combat session, before vs after.

- **PERF-002** | Performance | **Low**
  - Location: `Core.lua` `OnUnitTooltip` -> `LearnSkin` + `ApplySkinningLine` (L1367-1526); `CanSkinUnit`, `UnitNpcID`, `TooltipHasSkinnable`
  - Evidence: Per unit hover: `UnitFromTooltip` twice (each `tooltip:GetUnit()` -> `TooltipUtil.GetDisplayedUnit` -> `UnitTokenFromGUID` + `UnitName`), `UnitNpcID` twice (two `UnitGUID` + pattern matches), `UnitIsDead` up to three times, and `TooltipHasSkinnable` scans `data.lines` then rescans all font strings (`FontStringByIndex` concatenates `"TextLeft"..i` and may hit `_G`).
  - Recommendation: Resolve `unit`, `npcID`, `isDead` once in `OnUnitTooltip` and pass them down. In `TooltipHasSkinnable`, trust `data.lines` when accessible and skip the font-string rescan. Determine in-game whether `tooltip.TextLeft1` keys or `GameTooltipTextLeft1` globals are live and keep one path.
  - Risk: none. Verification: identical skinning line and learning results; fewer API calls per hover (count with a debug counter).

- **PERF-003** | Performance | **Low**
  - Location: `Core.lua` `CheckTracking` (L581-623)
  - Evidence: While the warning is visible the 1 s watchdog rebuilds the message via `L.SPELL_OFF:format(ns.SpellName(...))` (API call + `format`) every tick, then compares to `lastWarningKey`.
  - Recommendation: Compute the three possible messages once (lazily on first use, per session) and select by state.
  - Risk: Spell names do not change mid-session. Verification: message text unchanged.

- **PERF-004** | Performance | **Low**
  - Location: `Core.lua` `ApplyObservation` (L239-252), `ReportGatherLearn` (L1461-1477), `SkinningBand` (L1403-1412)
  - Evidence: Allocates a new 6-field band table per tooltip render whenever an observation lowers `orange`; `ReportGatherLearn` builds it twice; `SkinningBand` allocates a band table on every dead-unit hover.
  - Recommendation: Return the effective `orange` number instead of a table (`EffectiveOrange(band, key)`), and have `DifficultyColor` accept `(skill, orange, yellow, green, grey)` or the band plus an override. Cache skinning bands per level in a small table (levels are bounded, 1..63).
  - Risk: none. Verification: colors and required numbers identical on a set of known nodes/levels.

- **PERF-005** | Performance | **Low** (load-time only)
  - Location: `Locales.lua`
  - Evidence: ~48 KB of table constructors executed at login for 10 unused locales, then discarded.
  - Recommendation: ARCH-005 (per-locale files with `[AllowLoadTextLocale]`).
  - Verification: `GetAddOnMemoryUsage("GatherSkillTooltip")` after login, before vs after.

### Security, taint and WoW-specific risks

- **SEC-001** | Security | **Informational (pass)**
  - Evidence: No protected functions, no secure templates, no attribute writes on Blizzard frames, no `pcall` masking. The only Blizzard-owned objects touched are GameTooltip font strings via `SetText`/`SetTextColor`/`AddLine` (permitted, standard practice) and a `HookScript("OnShow")` on GameTooltip (safe; slated for removal under UI-001). Globals: 5 intentional, 0 accidental (regex scan of all assignments and function declarations).
  - Recommendation: none beyond UI-001. Document the global policy in Part 5.

- **SEC-002** | Secret values | **Informational**
  - Evidence: Forever docs show no `Secret*` flags on `UnitIsPlayer`, `UnitPlayerControlled`, `UnitIsDead`, `UnitCanAttack`, `UnitLevel`, `UnitIsTapDenied`, `UnitExists`; `SecretWhenUnitIdentityRestricted` on `UnitCreatureType`, `UnitGUID`, `UnitTokenFromGUID`; `SecretWhenUnitNameIdentityRestricted` on `UnitName`. The code guards all of them uniformly.
  - Assessment: The uniform guards are cheap and protect against future flag changes and against secrecy propagated from a secret unit token argument. Keep them, but centralize in `TooltipText.lua` so the policy lives in one place. Do not remove individual guards without an in-game reason.
  - Verification: In combat, hover NPCs and corpses; no Lua errors; skinning line degrades gracefully (expected: hidden while identity is restricted).

- **SEC-003** | Saved variables | **Low**
  - Evidence: `db.skinIds[npcID]` keys come from GUID parsing (trusted, numeric); `db.gather[key]` keys come from our own node keys or `"skin:<level>"`. No externally sourced data. Growth is bounded (nodes x skill levels; NPC ids encountered).
  - Recommendation: ARCH-006 validation on load is sufficient.

### Tooling

- **TOOL-001** | Tooling | **High**
  - Evidence: `git rev-parse` fails; the addon directory is the only copy and is edited live inside `Program Files (x86)`.
  - Problem: No history, no rollback, no diff review; the Forever beta's SavedVariables bug shows how easily state is lost.
  - Recommendation: Create a repository outside the game folder (e.g. `%USERPROFILE%\dev\GatherSkillTooltip`) and deploy to the AddOns folder with a directory junction (`mklink /J`) or a copy script. Commit the current 1.9.0 as the baseline before any change from this plan.
  - Risk: none. Verification: `git log` shows baseline; addon loads from the junction.

- **TOOL-002** | Tooling | **Medium**
  - Location: `.luarc.json`
  - Evidence: `workspace.library` is an absolute path into `C:/Users/rubin/.cursor/extensions/ketho.wow-api/Annotations/Core`; that folder contains a hand-authored `StatSourceTooltipGlobals.lua` (named for a different addon) that defines `TooltipDataProcessor` and `SlashCmdList` for LuaLS. An extension update replaces the folder and silently removes it.
  - Recommendation: Add a repo-local `.annotations/GatherSkillTooltip_Globals.lua` (`---@meta`) declaring only what Ketho's Core lacks (`TooltipDataProcessor`, `SlashCmdList`, `Settings`, `CreateSettingsListSectionHeaderInitializer`, `LibStub`, `GameTooltip`, `Minimap`, `UIParent`) and list it in `workspace.library` with a relative path alongside the Ketho path. Keep `runtime.version = Lua 5.1` and the strict severities; they are correct for this project.
  - Risk: none. Verification: LuaLS reports zero diagnostics on all files.

- **TOOL-003** | Tooling | **Medium**
  - Evidence: No `luacheck`, `lua`, or `lua-language-server` on PATH; no `.luacheckrc`; the only static analysis is the editor.
  - Recommendation: Add `.luacheckrc` modeled on BigWigs (`std = "lua51"`, `globals` limited to the WoW API and the 5 intentional globals, `max_line_length = false`) and install luacheck (via `scoop install luacheck` or luarocks). Optionally add a headless LuaLS check (`lua-language-server --check <dir> --configpath .luarc.json`) for CI parity. Purpose: catch accidental globals, unused locals/args, shadowing and unreachable code without the game client. Limitation: neither tool knows WoW API semantics (return counts, secret flags); those remain in-game checks.
  - Verification: `luacheck .` exits 0.

- **TOOL-004** | Tooling | **Low**
  - Evidence: No `.pkgmeta`, no CI, no `CHANGELOG.md`/`README.md` in the folder (changelog lives only in CurseForge per prior chats).
  - Recommendation: Add `README.md`, `CHANGELOG.md`, `.pkgmeta` (ignore `.luarc.json`, `.annotations`, tests) and a GitHub Actions workflow using `BigWigsMods/packager` (`release.sh`) to build the zip and upload with the Forever game version. Explain: packager reads the TOC `## Interface` to tag the game version; keep `## X-Curse-Project-ID` in the TOC for uploads.
  - Verification: workflow produces a zip that installs cleanly.

- **TOOL-005** | Tooling | **Low** (depends on ARCH-001)
  - Recommendation: Plain Lua 5.1 unit tests (busted or a 30-line runner) for the pure functions listed in ARCH-001 with fixtures: color-code stripping, `(3/5)` suffix stripping, `NpcIdFromGUID` on real GUID strings, `SkinningOrange` at levels 1/10/11/20/21/60, `ColorFromRate` thresholds, `ObservedColor` with the live DB's `Copper Vein` observation. What cannot be unit-tested: anything touching tooltips, units, Settings, timers (in-game checklist in Part 6).

### Data

- **DATA-001** | Data | **Informational**
  - Evidence: `Data.lua` bands and `SKILL_CAP = 300` are vanilla values; Forever adds zones and may add nodes/ranks. `ShowUnmatched` only prints with debug on.
  - Recommendation (optional): collect unmatched Object/Minimap names in a session-only table and expose `/gst unmatched` to list them, easing data updates. Not required for this audit's goals.

---

## Part 3: Prioritized remediation roadmap

### Phase 0: Baseline (prerequisite for everything)
- Persist this report as `CODE_AUDIT.md` in the addon folder (docs only).
- TOOL-001: create git repo outside the game folder, junction into AddOns, commit 1.9.0 as baseline. Small. No regression risk. Acceptance: `git log` shows baseline, addon loads.
- Record baseline measurements (Part 4 procedure) before any code change.

### Phase 1: Critical correctness, security and compatibility (quick wins marked QW)
- CQ-001 stale `lastNodeKey` (Small, QW). Acceptance: unknown-node gather records nothing.
- CQ-003 truthiness test in `HasTrackingBuff` (Small, QW). Acceptance: no error in combat.
- COMPAT-001 `GetPrimaryTooltipData` (Small, QW). Acceptance: pins and world nodes rewritten.
- CQ-004 + CQ-005 + ARCH-006 versioned migration and DB validation (Small). Acceptance: drag to 215 persists; corrupted DB recovers.
- CQ-002 skinning false negative: in-game confirmation first, then chosen option (Medium). Acceptance: unlooted own corpse never learns `false`.
- COMPAT-003 creature type IDs (Small, after `/dump` confirmation). Acceptance: type fallback works on non-enUS.
- COMPAT-004 `UNIT_SKINNABLE_LEATHER` (Small). Acceptance: `/dump` confirms; learning still works.

### Phase 2: High-impact performance and memory
- PERF-001 coalesced timer + conditional event registration (Small). Depends on ARCH-002 optional. Acceptance: `CountTimeOver1Ms` and memory delta not worse; warning still clears within 1 s.
- COMPAT-002 remove aura path if in-game check passes (Small). Acceptance: warning behavior identical in/out of combat.
- UI-001 instrument `OnShow` fallback, then remove or minimize (Small to instrument, Small to remove). Acceptance: 0 matches over a full session, then removal with smoke test.
- PERF-002 single unit resolution per hover, trust `data.lines` (Small). Acceptance: identical output, fewer calls.
- PERF-003 cached warning messages (Small). PERF-004 band allocation removal (Small).

### Phase 3: Structural refactoring and complexity removal
- COMPAT-005 delete dead fallbacks (Medium, mechanical). Acceptance: LuaLS clean; smoke test passes.
- ARCH-001 split `Core.lua` into concern files (Large). Prerequisite: Phases 1-2 merged so the split is a pure move. Acceptance: behavior-identical smoke test; no file over ~400 lines.
- ARCH-002 dispatch table (Small, do during the split). ARCH-003 shared factory/strip (Small). ARCH-004 data/helper relocation, `NODE_BY_KEY`, explicit `LOOKUP` (Small). UI-002 drop Corpse registration after check (Small).

### Phase 4: Modernization, tooling, maintainability
- TOOL-002 repo-local annotations (Small). TOOL-003 `.luacheckrc` + luacheck install (Small). ARCH-005/PERF-005 per-locale files with `[AllowLoadTextLocale]` (Medium). TOOL-004 README/CHANGELOG/.pkgmeta/CI (Medium). TOOL-005 unit tests for pure functions (Medium, after ARCH-001). Adopt Part 5 standards.

### Phase 5: Benchmarking, regression and final verification
- Re-run Part 4 measurements; compare to baseline; run the full Part 6 checklist on enUS and one other locale; bump version, update CHANGELOG, package.

---

## Part 4: Performance optimization plan

Ranked by expected impact and confidence. This addon has no demonstrated bottleneck; the goal is removing avoidable churn on the only high-frequency paths and confirming with measurement.

**Supported by code evidence (implement after baseline):**
1. PERF-001 `UNIT_AURA` timer/closure churn and always-on registrations. Frequency: every player aura change. Confidence high.
2. UI-001 `OnShow` fallback on every non-data tooltip. Frequency: every UI tooltip. Confidence high that it is waste if instrumentation shows 0 matches.
3. PERF-002 duplicate unit/GUID resolution and double line scan per unit hover. Frequency: every unit hover. Confidence high; magnitude small.
4. PERF-003 message rebuild each watchdog tick. Frequency: 1 Hz only while warning visible. Confidence high; magnitude tiny.
5. PERF-004 band table allocation per render. Frequency: per node/dead-unit hover. Confidence high; magnitude tiny.
6. PERF-005 / ARCH-005 locale load. One-time; mainly a maintainability win.

**Hypotheses, do not implement without profiling:** caching `NormalizeName` results; replacing `gmatch` in the multi-pin path; pooling the `parts` table. Human-paced, rare; not worth complexity.

**Measurement procedure (this client provides these APIs, verified in forever docs):**
- Enable `C_AddOnProfiler` (check `C_AddOnProfiler.IsEnabled()`), then read `C_AddOnProfiler.GetAddOnMetric("GatherSkillTooltip", Enum.AddOnProfilerMetric.RecentAverageTime | PeakTime | CountTimeOver1Ms)` after a scripted 5-minute session: 20 node hovers, 20 pin hovers, 20 unit hovers (10 dead), one 2-minute combat with buffs cycling, warning visible for 60 s.
- Memory: `UpdateAddOnMemoryUsage(); GetAddOnMemoryUsage("GatherSkillTooltip")` at login+60 s and after the session; also `collectgarbage("count")` delta during 1 minute of combat with and without the addon enabled (isolates PERF-001).
- Micro: `debugprofilestop()` around `ApplyTooltip` and `OnUnitTooltip` for 100 hovers (debug-only code, removed before release).
- Record baseline in `CODE_AUDIT.md` before Phase 1; do not claim percentages that were not measured.

---

## Part 5: Coding standards for this repository

- **Lua/scoping**: everything `local`; cache WoW API functions as file-level locals at the top of each file; no forward declarations except where mutual recursion is unavoidable (and then comment why). Lua 5.1 semantics only (no `goto`, no integer division, no `//`).
- **Global namespace**: exactly these globals are permitted: `GatherSkillTooltipDB`, `GatherSkillTooltip_OnAddonCompartmentClick`, `SLASH_GATHERSKILLTOOLTIP1/2`, `SlashCmdList.GATHERSKILLTOOLTIP`. Everything else goes on `ns` (the `...` addon table). Enforced by `.luarc.json` `diagnostics.globals` and `.luacheckrc`.
- **Modules**: one concern per file, loaded in TOC order; files communicate only through `ns.*` functions and `ns.db`; no file reads another file's locals; no file performs WoW API calls at load except `CreateFrame`/registration in `Events.lua`.
- **Client compatibility**: target is exactly `## Interface: 16001` + `AllowLoadGameType camelot`. Verify any API against the Gethe `forever` branch (or Ketho annotations) before use; no fallbacks for APIs that exist in the target build; guards only for optional third-party libraries.
- **Secret values**: never compare, do arithmetic, `#`, index, or use as a table key on a value that can be secret; use the shared `ReadableString`/`CanIndex`/`SecretBlocked` helpers; `type()` checks are allowed; truthiness tests only on non-boolean types.
- **Events and frames**: register only needed events, unregister when a feature is disabled; use `RegisterUnitEvent` for player-only unit events; no permanent `OnUpdate`; timers via `C_Timer` with a reusable callback (no per-event closures); frames created once and reused.
- **Performance/allocation**: no table or closure allocation inside event handlers or tooltip callbacks unless the path is rare (document it); return scalars instead of tables where possible; string building only at display time.
- **Errors**: no `pcall` to hide defects; validate at boundaries (SavedVariables load, tooltip/unit inputs) and trust internal calls; debug output only behind `db.debug`.
- **Saved variables**: `db.version` with one-time migrations; defaults applied via `CopyDefaults`; validate table-typed fields on load.
- **Testing and review**: pure logic in WoW-free files with plain Lua tests; `luacheck .` and LuaLS clean before commit; Part 6 in-game checklist before release; CHANGELOG entry per release.

---

## Part 6: Implementation and verification checklist

**Before each implementation session**
- Pull latest from git; `luacheck .` and LuaLS show 0 issues; note current `C_AddOnProfiler` and memory baseline.

**Static checks (no client)**
- `luacheck .` exit 0; LuaLS 0 diagnostics; unit tests pass (Phase 4+); TOC lists every file in dependency order; no new globals (`/dump` scan or luacheck).

**In-game verification (enUS, then one other locale)**
- Tooltips: hover Peacebloom/Copper Vein in world and on minimap pin; stacked pins; unknown object (no rewrite, debug prints unmatched); toggle each of `showCurrent`/`showRequired`/`color`; disable `enabled` (no rewrite, no banners).
- Skinning: hover living beast (no line), dead own beast unlooted (no false "cannot be skinned" line after CQ-002), looted skinnable (line present, learned true), non-skinnable humanoid (no line); in combat hover (no error, graceful degrade).
- Learning: gather a node until a skill-up; chat line appears only on color change; gather an unknown node after hovering a known one (no observation recorded, CQ-001).
- Tracking warning: turn Find Herbs off (warning within 0.5-1 s), on again in and out of combat (clears within 1 s); disable `warnTracking` (hidden; events unregistered after ARCH-002).
- Trainer reminder: with skill capped below 300, gather (banner for 4 s, not again within 30 s).
- Minimap button: with and without LibDBIcon present (disable BigWigs/BugSack to test fallback); drag to ~215, `/reload`, position persists (CQ-004); compartment click opens settings.
- Settings: every checkbox toggles behavior live; master `enabled` greys children; `/gst`, `/gst debug`.
- Secret/combat: full combat encounter with mouseovers; BugSack shows 0 errors.

**Performance comparison**
- Repeat the Part 4 scripted session; record `RecentAverageTime`, `PeakTime`, `CountTimeOver1Ms`, memory delta; compare with baseline; investigate any regression before release.

**Release**
- Bump `## Version`, update `CHANGELOG.md`, tag, package via packager, install the zip fresh and re-run the smoke subset.

---

## Appendix A: Baseline record (Phase 0)

Baseline code: git tag `v1.9.0-baseline` in `%USERPROFILE%\dev\GatherSkillTooltip` (the AddOns folder entry is a junction to that repo). To measure the baseline, check out the tag, `/reload`, and run the scripted session from Part 4.

Snippets (paste in chat; `/gst debug` is not required):

```
/run local m=Enum.AddOnProfilerMetric; local f=C_AddOnProfiler.GetAddOnMetric; print("GST profiler enabled:", C_AddOnProfiler.IsEnabled(), "avg", f("GatherSkillTooltip", m.RecentAverageTime), "peak", f("GatherSkillTooltip", m.PeakTime), ">1ms", f("GatherSkillTooltip", m.CountTimeOver1Ms))
/run UpdateAddOnMemoryUsage(); print("GST memory KB:", GetAddOnMemoryUsage("GatherSkillTooltip"))
```

| Measurement | Baseline (1.9.0) | After Phase 2 | After Phase 5 |
| --- | --- | --- | --- |
| `RecentAverageTime` (ms) after scripted session | not yet measured in-game | | |
| `PeakTime` (ms) | not yet measured in-game | | |
| `CountTimeOver1Ms` | not yet measured in-game | | |
| Memory at login + 60 s (KB) | not yet measured in-game | | |
| Memory after session (KB) | not yet measured in-game | | |
| `collectgarbage("count")` delta, 1 min combat, addon on | not yet measured in-game | | |
| `collectgarbage("count")` delta, 1 min combat, addon off | not yet measured in-game | | |

Rules: fill cells only with values read from the client; leave "not yet measured in-game" otherwise. No percentages are claimed anywhere in this document until both columns of a row are filled.

The "After Phase 2" and "After Phase 5" columns are also still empty: no game client was available during the implementation session. Measure "After Phase 5" on the current `main` (2.0.0) with the same snippets and session; measure "After Phase 2" only if a regression needs bisecting (`git checkout 386a5fc`).

---

## Appendix B: Implementation record (Phases 1-5)

All remediation items were implemented on branch `main` of `%USERPROFILE%\dev\GatherSkillTooltip`, one commit per item group, from tag `v1.9.0-baseline` to version 2.0.0. Static checks at the end of the session: `luacheck .` 0 warnings / 0 errors in 24 files; `luajit tests/run.lua` 18 passed; every TOC file compiles under LuaJIT 2.1; an offline smoke run (stubbed WoW API, enUS and deDE) loads the TOC in order, fires ADDON_LOADED / PLAYER_LOGIN / PLAYER_ENTERING_WORLD, rewrites an Object, a stacked MinimapMouseover and a Unit tooltip, records a gather miss, toggles tracking and loot event registration and applies the GameTooltip fallback once. The packager (`release.sh -d -z -e`) staged the addon as game type `forever`, version 1.60.1, honoring `.pkgmeta`; `.release/GatherSkillTooltip-2.0.0.zip` was built from that staging directory.

| Commit | Items | Notes |
| --- | --- | --- |
| `b3d4311` | CQ-001 | 15 s node memory with clear-on-unknown; single-match rule for pin stacks |
| `d04363c` | CQ-003, COMPAT-001 | truthiness test; `GetPrimaryTooltipData` first |
| `c8cde02` | CQ-004, CQ-005, ARCH-006 | `db.version = 2`, migrations, validation, `minimapIcon.hide` derived in one place |
| `628566a` | CQ-002 | loot-GUID tracking (option a): negative learning only for own, fully looted corpse |
| `fdc6e71` | COMPAT-003, COMPAT-004 | numeric creature type ids with name fallback and debug mismatch print; `UNIT_SKINNABLE_LEATHER` |
| `c190fbb` | PERF-001, ARCH-002 | coalesced timer, shared callback; tracking and loot events registered only while active |
| `09c4b92` | COMPAT-002 | aura path removed (verified `RequiresNonSecretAura`); UNIT_AURA kept as a trigger with debug trace |
| `5f449ab` | UI-001, UI-002 | fallback minimized and instrumented (`/gst stats`); Corpse post-call kept |
| `386a5fc` | PERF-002, PERF-003, PERF-004 | single unit resolution, `data.lines` first, cached messages and bands |
| `6c3acd2` | COMPAT-005 | dead multi-client fallbacks removed |
| `68ed53c` | ARCH-001, ARCH-002, ARCH-003, ARCH-004 | `Core.lua` split into 10 modules; dispatch table; `CreateBanner()`; `StripInline`; ids and `NODE_BY_KEY` in `Data.lua`; `ns.LOOKUP` a separate table |
| `d426eed` | TOOL-002, TOOL-003, TOOL-004 | `.annotations/`, `.luacheckrc`, README, CHANGELOG, `.pkgmeta`, CI and release workflows |
| `5adb5c9` | ARCH-005, PERF-005 | `Locales/<locale>.lua` gated by `[AllowLoadTextLocale]` (same TOC pattern BigWigs uses on this client) |
| `47cd566` | TOOL-005 | `tests/run.lua` |

### Deviations from the plan

- ARCH-001 module list gained `Database.lua` (SavedVariables) and `Tooltip.lua` (object tooltips) beyond the eight files named in the plan; `TooltipText.lua` holds the secret-safe readers, colors and strip helpers as planned.
- Frames are created lazily in `Warnings.lua` and `MinimapButton.lua` (first use, never at load); the only load-time WoW API calls are in `Events.lua`, as the Part 5 standard requires.
- `EN = nil` style memory release in the old `Locales.lua` is gone; per-locale files make it unnecessary.
- No GitHub remote exists yet, so the CI and release workflows have not run. They are configured against verified inputs (`nebularg/actions-luacheck@v1`, `leafo/gh-actions-lua@v13` with `5.1.5`, `BigWigsMods/packager@v2`; `release.sh` maps TOC `16xxx` to game type `forever`).

### Requires in-game confirmation before tagging 2.0.0

Everything below was implemented with a safe default and, where useful, debug instrumentation, because it cannot be observed from source. Run with `/gst debug` on where noted.

1. **CQ-002** — Kill and skin-check flow: hover your own unlooted dead beast (no "cannot be skinned" learned), loot it fully, hover again (line present, `Learned: X can be skinned` with `learnChat` on). Confirms the "Skinnable line appears only after looting" premise and the LOOT_OPENED/LOOT_CLOSED GUID capture.
2. **COMPAT-002** — Over a full session with `/gst debug`, watch for `tracking warning shown/hidden after UNIT_AURA`. If it never appears (only `MINIMAP_UPDATE_TRACKING`, `PLAYER_REGEN_ENABLED`, `watchdog/other`), remove the `{ "UNIT_AURA", "player" }` entry from `TRACKING_EVENTS` in `Warnings.lua` and the `UNIT_AURA` handler line in `Events.lua`.
3. **COMPAT-003** — `/dump UnitCreatureType("target")` on a beast and a dragonkin: confirm ids 1 and 2 (`ns.SKIN_TYPE_IDS` in `Data.lua`). A debug line `creature type mismatch` on hover means the id table is wrong for that type.
4. **COMPAT-004** — `/dump UNIT_SKINNABLE_LEATHER` should be `"Skinnable"` on enUS (and the localized word on the second locale). `nil` means the addon is using the locale fallback (still correct, but note it here).
5. **UI-001** — After a full session, `/gst stats`: if `applied` is 0, delete the fallback block at the end of `Events.lua` and the `stats` command in `Options.lua`.
6. **UI-002** — Hover a dead NPC with `/gst debug`: if the skinning line appears (it comes through the Unit post-call), the Corpse post-call in `Events.lua` can be removed once a session shows it never contributes.
7. **ARCH-005** — On a non-enUS client, confirm `Locales/<locale>.lua` loaded (settings panel in that language, localized node names matched). On enUS, only `Locales/enUS.lua` loads.
8. **Part 6 checklist** — run in full on enUS and one other locale; record the Appendix A measurements; then `git tag -a 2.0.0 -m "2.0.0"` and push (the release workflow packages and publishes).

---

## Appendix C: 2.0.1 remediation

### Phase 1 (implemented)

- **CQ-101, CQ-105.** `OnGatherCastStart` snapshots the unmatched object name and the pre-cast skill. It snapshots a name only when that cast has no known node key. `OnGatherCastSucceeded` learns only that snapshot and does not call `RecentUnknownName()` again. A skill-up that arrives before success does not change the stored orange.
- **CQ-102.** `orangeSeen` is the lowered threshold and only decreases. `EffectiveOrange` reads it. `gainedAt` is still the highest gain and still drives `GainedAtOrAbove`. SavedVariables `version` 3 seeds `orangeSeen` once from a `gainedAt` that is still below the table orange. A later load does not seed again, so a threshold that was already lost is not invented.
- **ARCH-101.** `ProfessionForGatherSpell` lives in `Data.lua` next to `GATHER_SPELLS`.
- **COMPAT-102.** `SecretBlocked` runs before `GATHER_SPELLS` and `TRACKING_SPELLS` are indexed.
- **TOOL-102.** `tests/run.lua` loads `Tooltip.lua` and `Learning.lua` under stubs. `luajit tests/run.lua`: 25 passed, 0 failed.
- **luacheck.** Not installed in this environment (`luarocks show luacheck` reports the package missing). The GitHub workflow still runs it. `.luacheckrc` lists the new test stubs as allowed globals.

Remaining hole, as specified: if a herb or ore tooltip never replaces an earlier unmatched name before the cast starts, that older name can still be learned.

### Phase 2 (decided: leave the fallbacks in place)

No debug session was available. The plan says not to delete or retarget these from the audit alone:

- **CQ-103.** The mouseover-or-target loot GUID is unchanged. `OnLootOpened` now prints, when `/gst debug` is on, the mouseover GUID, the target GUID, and the slot count. That is the session the decision still needs.
- **COMPAT-101.** `UNIT_AURA` stays registered.
- **UI-101.** The GameTooltip `OnShow` fallback and `/gst stats` stay.
- **UI-102.** The Corpse tooltip post-call stays.
- **CQ-104.** No locale aliases and no `LEARNED_NODE` translations were added. Those names have not been read from the client.

Part 6 steps 4 through 7 are still an in-game pass. No profiler numbers were taken.
