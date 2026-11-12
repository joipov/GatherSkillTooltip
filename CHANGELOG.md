# Changelog

## 2.2.3

### Fixed

- Tooltips owned by a UI window (the guild roster, party/raid frames, bags, action bars, chat links) are never rewritten as herb or ore nodes, even when the client delivers them without typed tooltip data. The tooltip owner is checked in addition to the mouse focus.
- A node name that is also a valid unit token (a group member's name from a minimap dot, for example) is never decorated or learned as a herb or ore.
- Unit tooltips owned by a UI frame no longer receive a Skinning suffix.

## 2.2.2

Unknown herbs and ores can be learned even when their tooltip has no readable name, and minimap pin stacks using the `|n` escape are handled like real newlines.

### Added

- An unknown herb or ore is now learned from the loot window when the cast had no tooltip name. The addon reads the loot source and item classes, accepts only herbs or ore for the cast's profession (gems on ore are ignored), and records the skill from before the cast. Other loot, a non-game-object source, or a loot window more than three seconds after the gather is ignored.

### Changed

- Loot events stay registered while herbalism or mining is on, not only while skinning is on.
- Decorated tooltip lines are remembered in a small bounded cache while a minimap pin is hovered. The cache is cleared when a custom node or locale alias changes.
- The tooltip reflows after its first line is rewritten, so the longer skill line is not clipped.

### Fixed

- Stacked minimap pins separated with `|n` are split and decorated like pins separated with a real newline.
- A generic tooltip callback no longer assumes the frame is a game tooltip. Frames without `GetUnit` or `AddLine` are skipped instead of throwing, the same failure mode that breaks `Gathering_Tooltip` r21 on item comparison tooltips.

## 2.2.1

### Fixed

- Hovering a Questie map icon no longer throws `attempt to call a nil value` in the mouse-focus check. The addon walks the focus frame's parents instead of assuming every frame has `IsDescendantOf`.

## 2.2.0

Known Forever herbs and ores now use the Wowhead Forever requirements, and a stale hover cannot teach the wrong number.

### Added

- Hyjal Silphium, Tomb Weed, Doom Weed, Gloom Weed, Incendia Agave, Serpentbloom, and Violet Tragan at Herbalism 1, and Demonsage at Herbalism 300.
- Chunk of Amber and Large Chunk of Amber at Mining 1.

### Fixed

- Khadgar's Whisker and other known nodes keep their verified requirement. A gain recorded below a known node's requirement, such as a Kingsblood gain attributed to a Khadgar's Whisker minimap pin, no longer lowers the displayed number or turns the node orange too early.
- A remembered node is attributed to a gather only while that same name is still on the tooltip, so a stale minimap pin or an earlier hover cannot lend its name to a different node.
- DB v10 drops built-in observations below the verified requirement. Custom names keep their learned data.

## 2.1.9

Tooltip rewriting stays on gathering tooltips; UI windows are left alone.

### Fixed

- UI tooltips (the guild roster, bags, action bars, unit frames, chat links) are never rewritten as herb or ore nodes, even when a player or object name matches a learned name.
- An unknown herb or ore is learned only while its name is still on the tooltip under the cursor. A name hovered earlier (a player on the minimap, a campfire) can no longer be saved as the node a later cast gathered.

### Added

- `/gst forget <name>` removes a wrongly learned node and its observations, so the name stops being colored and suffixed.

## 2.1.8

Re-checked against the current Forever client; no code change was needed.

### Changed

- Verified against Forever client 1.60.1.70862 and the current EllesmereUIMinimap host.

## 2.1.7

The tracking warning can turn tracking on itself and clears in combat.

### Added

- The tracking warning has a small text button for each missing tracking spell, **Turn on Find Herbs** or **Turn on Find Minerals**. Clicking one enables that tracking and clears the warning.

### Changed

- The warning and the trainer reminder default to text size 18 instead of 20. A stored 20 moves to 18 once; any other chosen size stays.
- The **Text size** tooltip no longer calls 20 the large size.

### Fixed

- The tracking warning stays quiet in combat, where the client hides or stales the tracking state, and checks again when combat ends. Turning tracking on in combat no longer leaves the warning behind.
- A successful tracking cast or a warning button click counts as on while a read is stale, so the warning does not linger. If the tracking really is still off, it returns after a few seconds or when combat ends.
- Entering combat triggers a check, so a warning does not stay up on stale data.

## 2.1.6

Hidden tracking and skill values in combat no longer produce wrong warnings or numbers.

### Fixed

- When the minimap tracking state cannot be read in combat, the tracking warning stays quiet instead of warning about a state that was not seen to be off.
- A profession skill that cannot be read in combat is left unknown instead of being cached as a number built from a hidden value.

### Changed

- **Minimap button** stays active while the addon is off.
- `/gst help` lists the subcommands.

## 2.1.5

The minimap button tooltip is the same sentence in every language.

### Changed

- The minimap button tooltip says the button opens settings.

## 2.1.4

Same skill colors. The minimap button matches the other Joipov addons.

### Changed

- The minimap launcher is the shared button. Click still opens settings.

## 2.1.3

Forever herbs and ores that share a classic requirement use that band before you gather them.

### Added

- **Nightmare Moss** uses the Kingsblood band. **Dreamroot** uses the Firebloom band. **Moonroot** and **Star Lotus** use the Gromsblood band.
- **Cold Iron Deposit** uses the Iron Deposit band. **Fool's Gold Vein** uses the Mithril Deposit band. **Starsilver Vein** and **Greater Moonstone Formation** use the Small Thorium Vein band.
- **Heavy Thorium Vein** requires 300. Its band is 300 / 325 / 365 / 400.

## 2.1.2

The login line shows the addon name and version. The Joipov name color is a brighter violet.

### Changed

- The login line reads Joipov <name> (v<version>). The name and version come from the TOC, so they never drift. The version is a different color.
- Joipov is now a saturated violet.

## 2.1.1

### Changed

- The minimap position is stored in LibDBIcon's own table, so dragging the button with LibDBIcon keeps its place, and the built-in button uses the same value.
- The addon loads only on the `forever` game type.

### Fixed

- A spellcast id that the client hides is no longer compared, which could error on a secret value.
- A unit tooltip's data table is checked before it is read.
- The learned-node chat line and the node names in it use the client's language.
- Locking the reminder no longer shifts it. The drag box sits around the message, and the trainer line stacks from the warning's real top.
- Kingsblood stays yellow through 189 and turns green at 190. The band is
  125 / 150 / 190 / 225. At 189 the tooltip was calling it green while it is
  still yellow.
- Every other herb and ore uses that same green step, 65 percent of the way
  from the skill just below yellow to grey. Copper Vein turns green at 65.
- Skinning and nodes learned in play use that step. Saves that still have the
  old midpoint green are updated once.

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
- The button uses LibDBIcon when that library is loaded, and the same frame name when it is not, so the default minimap and the addon compartment can show it.

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
  stack of minimap pins clears the memory.
- "Cannot be skinned" is learned only for your own corpse after you have
  fully looted it, so the missing "Skinnable" line on an unlooted corpse no
  longer marks an NPC as unskinnable.
- SavedVariables are versioned and validated on load: legacy minimap angle
  and position values are migrated once, string-keyed skill counts become
  numeric, and any option with a wrong type resets to its default.
- The tracking warning's aura check was inert in combat on this client; the
  warning now uses the minimap tracking list only.

### Changed

- Skinnable creature types are matched by numeric creature type id first,
  with the localized name as fallback; the "Skinnable" text uses the client's
  own `UNIT_SKINNABLE_LEATHER` string.
- Tracking, loot and aura events are registered only while the feature that
  needs them is enabled; tracking checks are coalesced into one timer.
- One unit/NPC resolution per hover; tooltip data lines are trusted before
  font strings are scanned; warning texts and skinning bands are cached.
- Fallbacks for other clients (`UnitIsTapped*`, `GetSpellInfo`,
  `OnTooltipSetUnit`, API existence guards) were removed; the addon targets
  the Forever client only.
- `Core.lua` was split into per-concern files (see `README.md`), with a
  dispatch table for events and a shared banner factory.
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
