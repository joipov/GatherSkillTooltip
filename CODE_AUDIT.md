# Gather Skill Tooltip audit

Target: World of Warcraft Forever, `## Interface: 16001` (client 1.60.1.70862), Lua 5.1.
Compared 2026-10-21 against NodeSight 1.4.1 and EllesmereUIMinimap 9.6.1.
Behaviour only; nothing was taken from either. Re-checked against client
1.60.1.70862 and EllesmereUIMinimap 9.8.2 on 2026-11-08. Also compared on
2026-11-10 against PrettyTooltip 1.3.5, EllesmereUIForeverEssentials'
gather-skill module and Gathering_Tooltip r21. Static herb and ore
requirements checked against Wowhead Forever on 2026-11-10.

This note is for development. It is not shipped in the addon zip.

## What changed in 2.2.3

- Node rewriting now checks the tooltip owner (`GameTooltip:GetOwner`). A
  tooltip owned by the guild roster, a party/raid frame, a bag, an action bar
  or a chat link is skipped even when the client gives it no typed tooltip
  data. World object and minimap-pin tooltips keep UIParent/WorldFrame or a
  frame under the minimap as their owner.
- A first line that is itself a valid unit token (a group member's name) is
  never treated as a node, remembered as an unknown node, or learned. This
  covers a player's name on a minimap dot after it had been learned once.
- Skinning is only applied to world unit tooltips; a party/raid frame tooltip
  is skipped before its unit is resolved.

In-game check:

- [ ] Hover the guild roster and a party/raid frame whose member's name was
      wrongly learned once: no skill suffix or difficulty color.
- [ ] Hover the same group member on the minimap: the name stays normal.
- [ ] Hover a world herb/ore and a minimap pin: both still show the skill.
- [ ] Hover a living or dead beast in the world: the skinning line still works.

## What changed in 2.2.2

Compared on 2026-11-10 against NodeSight 1.4.1, PrettyTooltip 1.3.5,
EllesmereUIForeverEssentials' gather-skill module and Gathering_Tooltip r21.
Behaviour only; no code or data was copied.

- NodeSight learns an unknown node from the loot window. The same useful path
  is now here without its loose name heuristics: `UNIT_SPELLCAST_SENT` keeps
  the cast target, and `GetLootSourceInfo(1)` must name a `GameObject-` source.
  The loot items must all be herbs, or ore with optional gems, for the cast's
  profession. The learned orange is the skill snapshotted before the cast, and
  the record expires after three seconds. This covers a node whose tooltip had
  no readable name; the existing tooltip-name path still learns first.
- Loot events are now registered while herbalism or mining is on, not only
  while skinning is on. `LOOT_READY` and `LOOT_OPENED` both feed the same
  one-shot candidate, so either client event can supply the window.
- PrettyTooltip splits stacked minimap-pin names on the `|n` escape as well as
  newlines. That split is now used here before decorating each pin.
- Ellesmere's gather module memoizes the minimap line rewrite and calls
  `tooltip:Show()` after editing a line. Both ideas are adopted: `ExactNode`
  keeps a bounded 256-entry cache for decorated lines, invalidated whenever a
  custom node or locale alias changes, and the tooltip reflows after a rewrite.
- Not adopted: NodeSight's 25/50/100 difficulty bands (the local green step is
  client-verified), PrettyTooltip's full tooltip reskin and its loot/NPC data
  tables, and NodeSight's unverified requirement values for Forever names.
- Gathering_Tooltip r21 is useful as a failure case, not as a model. It hooks
  `ShoppingTooltip1/2` and calls `GetUnit` unconditionally; in Forever those
  comparison frames have `Regions` but no `GetUnit`, so every item comparison
  throws. It also matches node names by substring (its own comments report
  "Rich Adamantite Deposit" taking the shorter deposit's requirement),
  carries multi-expansion hardcoded node and NPC tables, and adds a second
  `Current ... /max` line. None of that is adopted. The failure did prompt a
  boundary check here: `ApplyTooltip` now requires `GetName`, `NumLines` and
  `AddLine` before matching, and `OnUnitTooltip` requires `GetUnit`, so a
  generic frame is skipped instead of throwing.

In-game check:

- [ ] Show an item comparison tooltip with an item that has a node-like name;
      no Lua error and the comparison line is unchanged.

- [ ] Hover an unknown herb or ore whose tooltip name is missing and gather it;
      it is learned at the pre-cast skill.
- [ ] Gather an ore node that drops a gem; it is still learned as mining.
- [ ] Loot a corpse or a chest right after gathering; no node is learned.
- [ ] Hover two pins that share a line and confirm both names are decorated,
      whether the client separates them with a newline or `|n`.
- [ ] Hover a minimap pin for several seconds; skill values stay current and
      `/gst forget <name>` still removes a learned node.
- [ ] Turn skinning off with herbalism on and confirm node learning still works.

## What changed in 2.2.1

- `FrameIsUnder` walks `GetParent` instead of calling `IsDescendantOf` on the
  mouse-focus frame. Questie's map-icon buttons do not have that method, so
  their tooltip `Show` used to throw in the fallback context check.
- In-game check: hover a Questie map icon on the minimap; no Lua error and
  the UI tooltip is skipped. Hover a world herb/ore and a minimap pin; both
  still rewrite.

## What changed in 2.2.0

- Static herb and ore requirements were checked against Wowhead Forever, not
  Classic. Every Classic row matched; the Forever-only rows that were missing
  were added (see the data check below).
- Built-in nodes now keep the verified requirement. `EffectiveOrange` ignores
  learned lowering for them, `ObservedColor` stays red below the requirement,
  and `NoteGatherResult` ignores observations below it.
- A remembered node is used for learning only while the same node is still on
  the tooltip (`TooltipShowsNode`). A stale minimap pin or an earlier hover
  can no longer lend its name to another node's gather.
- DB v10 drops built-in observations below the verified requirement. Custom
  names keep their learned data.

In-game check:

- [ ] Hover Khadgar's Whisker at 125 and confirm `(125/185)` and red.
- [ ] Hover a Khadgar's Whisker pin, gather Kingsblood, and confirm the
      Khadgar's Whisker number does not drop to 125.
- [ ] Hover an unknown Forever herb or ore and gather it; it is still learned.
- [ ] Existing saved data loads without errors and custom names keep their
      learned numbers.

## What changed in 2.1.9

- Node tooltip rewriting is limited to the world and minimap pins. The untyped
  `GameTooltip` fallback and the typed `Object` post-call check the client's
  `GetMouseFoci`; UI tooltips (guild roster, bags, action bars, unit frames)
  are skipped. The fallback now records the hovered node again, so untyped
  world objects can still be learned.
- Unknown node names are learned only when the same name is still in the
  visible tooltip at cast start (`TooltipShowsName`). A stale minimap/player
  or campfire name can no longer be saved as the gathered node.
- `/gst forget <name>` removes a learned node and its gather observations.
  Built-in names and locale aliases are refused.

In-game check:

- [ ] Hover the guild roster, a bag item, an action bar button, and a unit
      frame: none gains a skill suffix or difficulty color.
- [ ] Hover a world herb/ore and a minimap pin: both still show the skill.
- [ ] Hover an unknown Forever node, gather it, and confirm it is learned.
- [ ] Hover a player on the minimap, then gather a node; the player name is
      not added to `customNodes`.
- [ ] `/gst forget <wrong name>` removes it; `/gst stats` reports skipped UI
      tooltips.

## What changed in 2.1.8

- Re-checked the tracking reads, the warning buttons, and the minimap
  button against client 1.60.1.70862. `C_Minimap.GetTrackingInfo`,
  `C_Minimap.SetTracking`, and `CastSpellByID` keep their shapes, and the
  Ellesmere minimap still collects `LibDBIcon10_*` frames. No code change.

## What changed in 2.1.7

- The tracking warning now carries a small text button per missing tracking
  spell. The buttons call `C_Minimap.SetTracking` on the last readable index,
  fall back to `CastSpellByID`, and hide the warning at once.
- A successful tracking cast and a warning button click mark that profession
  as on for five seconds. This covers combat, where the tracking list can
  answer unknown or keep a stale off state. A delayed recheck runs when the
  mark expires, so a failed enable still warns again.
- `TrackingState` reports on/off per profession plus whether that profession's
  state was readable. Unknown stays quiet; a readable off still warns.
- The warning stays quiet for the whole of combat, where the list is secret
  or stale, and re-checks on `PLAYER_REGEN_ENABLED`. Entering combat
  (`PLAYER_REGEN_DISABLED`) triggers a check that hides it.
- The banner default is 18 (was 20). DB v9 moves a stored 20 to 18 once.

In-game check:

- [ ] Warning shows with herb tracking off; clicking **Turn on Find Herbs**
      turns it on and the warning goes away.
- [ ] Enter combat while the warning is up; it hides and does not come back
      after combat when tracking was turned on in combat.
- [ ] Cast Find Minerals with both professions known; either one clears it.
- [ ] Turn tracking off again after the optimistic window; the warning returns.
- [ ] Unlock position still drags and locks, and the drag hint sits under the
      buttons.

## What changed in 2.1.6

- `TrackingState` no longer assumes `C_Minimap.GetTrackingInfo` fields are
  readable. An entry whose `active` or `spellID` is a combat secret marks
  the answer unknown, and the caller stays quiet instead of warning that
  tracking is off. Readable entries still answer exactly as before.
- `CacheProfession` leaves a profession unknown when any of its line,
  level, cap, or modifier values is a combat secret, instead of doing
  arithmetic on an unreadable number. Numbers are also type-checked before
  the rank is added.
- `/gst help` lists the subcommands. The Minimap button row stays active
  while the addon is off, and checkbox defaults come from `ns.defaults`.
- `.luacheckrc` build comment updated to 70425.

## Data check against Wowhead Forever (2026-11-10)

The static table was checked against Wowhead Forever's object database, not
the Classic database: `wowhead.com/forever/objects/herbs` and
`wowhead.com/forever/objects/mining`. Every Classic herb and ore keeps its
Classic requirement in Forever (Khadgar's Whisker is still 185, Kingsblood
125, Black Lotus 300), so those rows did not change. The Forever-only rows
matched too: Nightmare Moss 125, Dreamroot 205, Moonroot 250, Star Lotus 250,
Cold Iron Deposit 125, Fool's Gold Vein 175, Starsilver Vein 245, Greater
Moonstone Formation 245, Heavy Thorium Vein 300, and Small/Large Obsidian
Chunk 305.

Added from the same lists: Hyjal Silphium, Tomb Weed, Doom Weed, Gloom Weed,
Incendia Agave, Serpentbloom, and Violet Tragan at Herbalism 1; Demonsage at
Herbalism 300; Chunk of Amber and Large Chunk of Amber at Mining 1. Wowhead
publishes the required (orange) skill only, so the added rows keep the
client's usual +25 yellow and +100 grey offsets from that requirement.

The Khadgar's Whisker report (125 instead of 185) was not a table error. The
table already said 185. A gain made on one node could be recorded against a
different node hovered earlier within the 15 second window; a Kingsblood gain
at 125 then lowered Khadgar's Whisker. Known nodes now keep the table
requirement, and a remembered node is used for learning only while that same
name is still on the tooltip. DB v10 removes stored observations below a
built-in node's requirement. Custom names keep their learned data.

## Data check against NodeSight (no change, by design)

NodeSight's name lists know Forever names this addon still learns by play
(Hive Thistle, Death Lotus, Marefoil, Stranglevine, Frilled Lichen, Rosecap).
NodeSight carries no required-skill values for them (it falls back to 1), so
there was no verified band to adopt. These stay learn-by-play here:
`LearnCustomNode` records the orange at first gain, which can overstate the
requirement for an over-level first gatherer. That is recorded, not silent.
Demonsage, Chunk of Amber, and Large Chunk of Amber are now in the static
table from Wowhead Forever.

NodeSight's difficulty bands were not adopted. This addon's green step is
client-verified (Kingsblood turns green at 190); NodeSight's 50-point band
disagrees with that.

## Ellesmere minimap check (manual, no code assumed)

EllesmereUIMinimap collects `LibDBIcon10_*` frames, reparents them into
its flyout, re-points their tooltips, and tracks their visibility. This
addon's fallback button is exactly such a frame parented to `Minimap`,
and `PlaceButton` assumes that parent. It does not hook the minimap
mouseover tooltip, so the gathering feature itself is unaffected.

- [ ] Button appears (minimap or flyout) and still opens settings.
- [ ] Dragging keeps the saved angle; tooltip shows title and drag text.
- [ ] The **Minimap button** setting still shows and hides it.
- [ ] On a square or rectangular Ellesmere minimap the button sits on the
      edge, not inside the map.

The same check covers every Joipov addon: `MinimapButton.lua` is one
shared file, byte-identical apart from its title and icon lines (the stray
blank-line split between copies was removed in this pass).

## Still holds

- Secret-table guards (`issecrettable`/`canaccesstable`) are deeper than
  NodeSight's value-only checks. Learned difficulty for unknown names,
  skinning, locales, and the DB v10 migration ladder are ahead of the
  compared addon.
