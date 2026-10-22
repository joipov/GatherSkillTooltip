# Gather Skill Tooltip audit

Target: World of Warcraft Forever, `## Interface: 16001` (client 1.60.1.70425), Lua 5.1.
Compared 2026-10-21 against NodeSight 1.4.1 (2026-10-21) and EllesmereUIMinimap
9.6.1 (2026-10-19). Behaviour only; nothing was taken from either.

This note is for development. It is not shipped in the addon zip.

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
