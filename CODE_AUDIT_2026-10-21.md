# Gather Skill Tooltip audit

Target: World of Warcraft Forever, `## Interface: 16001` (client 1.60.1.70862), Lua 5.1.
Compared 2026-10-21 against NodeSight 1.4.1 and EllesmereUIMinimap 9.6.1.
Behaviour only; nothing was taken from either. Re-checked against client
1.60.1.70862 and EllesmereUIMinimap 9.8.2 on 2026-11-08.

This note is for development. It is not shipped in the addon zip.

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

## Data check against NodeSight (no change, by design)

NodeSight's name lists know Forever nodes this addon only learns by play
(Hive Thistle, Demonsage, Death Lotus, Marefoil, Stranglevine, Frilled
Lichen, Rosecap, Chunk of Amber, Large Chunk of Amber). NodeSight carries
no required-skill values for them (it falls back to 1), so there was no
verified band to adopt. Until the true requirements are seen in the client,
these stay learn-by-play here: `LearnCustomNode` records the orange at
first gain, which can overstate the requirement for an over-level first
gatherer. That is recorded, not silent.

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
  NodeSight's value-only checks. Learned difficulty, skinning, locales,
  and the DB v8 migration ladder are ahead of the compared addon.
