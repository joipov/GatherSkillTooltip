# Gather Skill Tooltip

Shows your gathering skill and the skill a node requires when you hover a
herb or ore in the world, and puts your Skinning skill
beside the level of a creature you can skin. Knows the Wowhead Forever herb
and ore requirements, and learns unknown Forever herb and ore names, plus
which NPCs are skinnable, from play.

Target client: World of Warcraft **Forever**, release client (`_forever_`, `## Interface: 16001`).

## Features

- Herb and ore tooltips in the world: `Peacebloom (70/1)`, colored red/orange/yellow/green/grey
  by difficulty. Minimap pins no longer show the skill: the yellow-dot name is a secret value.
- Requirements checked against the Wowhead Forever object database (Herbs and
  Mining lists) on 2026-11-10.
- Skinning: `Level 12 (Skinning 100/20)` on creatures you can skin. NPC ids are
  learned from the "Skinnable" line on your own, fully looted corpses; unknown
  NPCs fall back to creature type (Beast, Dragonkin).
- Known herbs and ores use the Wowhead Forever requirements. For names the
  table does not know, a skill-up recorded below the learned orange lowers it;
  repeated misses without a gain turn a node grey.
- An unknown name can also be learned from the node's loot when the tooltip
  had no readable name. The loot source must be a game object and its items
  must be herbs, or ore with optional gems, for the gathering profession.
- Warnings: an on-screen banner when Find Herbs / Find Minerals is off and
  you know the profession, with a small button that turns tracking on, and a
  trainer reminder when a profession is capped.
- Minimap launcher via LibDBIcon when present, otherwise a built-in button. On by default.
  Addon Compartment entry; `/gst` opens the settings.

## Commands

| Command | Effect |
| --- | --- |
| `/gst`, `/gatherskilltooltip` | Open the settings panel |
| `/gst reset` | Reset settings to default. Learned herbs, ores, and skinning stay |
| `/gst forget <name>` | Remove a wrongly learned herb or ore name and its observations |
| `/gst debug` | Toggle debug output (unmatched tooltip names, learning traces) |
| `/gst stats` | Print the GameTooltip fallback counters (diagnostic) |

## Files

Loaded in TOC order; modules communicate only through the shared `ns` table.

| File | Concern |
| --- | --- |
| `Data.lua` | Skill line / spell ids, node tables (`NODES`, `NODE_BY_KEY`) |
| `Locales/enUS.lua` | English strings, `ns.LOOKUP`, `ns.RegisterLocale` |
| `Locales/<locale>.lua` | Per-locale strings and node aliases; only the client's locale is loaded (`[AllowLoadTextLocale]`) |
| `Locales.lua` | Post-locale lookups (creature types, "Skinnable" text, spell/profession names) |
| `Database.lua` | SavedVariables defaults, migrations, validation |
| `TooltipText.lua` | Secret-value guards, text stripping, colors, tooltip access |
| `Skills.lua` | Cached profession ranks |
| `Nodes.lua` | Node lookup, difficulty colors, learned observations |
| `Tooltip.lua` | Object / minimap tooltip rewrite, remembered node |
| `Skinning.lua` | Unit tooltip line, skinnable learning |
| `Learning.lua` | Loot tracking, gather watch (skill-up attribution) |
| `Warnings.lua` | Tracking warning and trainer reminder banners |
| `MinimapButton.lua` | LibDBIcon launcher or built-in button |
| `Events.lua` | Event frame, dispatch table, tooltip post-calls |
| `Options.lua` | Settings panel and slash commands |

## Development

The repository lives outside the game folder; the AddOns entry is a
directory junction to it:

```
mklink /J "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\GatherSkillTooltip" "D:\Repos\Joipov\GatherSkillTooltip"
```

Static checks (no game client needed):

```
luacheck .            # .luacheckrc: Lua 5.1, explicit WoW globals
luajit tests/run.lua  # or: lua5.1 tests/run.lua
```

LuaLS uses `.luarc.json` and Ketho's WoW API annotations. The repo-local
`.annotations/` folder declares Blizzard globals those annotations lack.

`assets/` is release media for CurseForge and Wago (screenshots, and a logo
when one exists). The game does not load it, and it is not part of the addon
zip. Do not delete it during cleanup.

Local zip, with the addon folder at the root, written to `.release/`:

```
powershell -File package.ps1
```

Releases: push an annotated tag (`git tag -a <version> -m "<version>"`). The
`Package and release` workflow runs BigWigsMods/packager, which reads the game
version from the TOC and the manual changelog from `CHANGELOG.md`.
`CODE_AUDIT.md` holds the audit and remediation record and is not shipped.

## Verifying in-game

- Hover Peacebloom / Copper Vein in the world, and an unknown object (no rewrite; `/gst debug` prints it).
  A yellow dot shows the game's name only.
- Hover the guild roster, a party/raid frame, a bag item, an action-bar button,
  and a unit frame: no node rewrite and no skinning line. World herb/ore and
  unit tooltips still rewrite.
- Skinning: living beast (no line), your own unlooted dead beast (no "cannot
  skin" learned), looted skinnable (line, learned), humanoid (no line).
- Toggle Find Herbs / Find Minerals and use the warning's own text buttons;
  the banner appears within a second and clears when tracking is back on.
  It stays quiet in combat and re-checks when combat ends.
- Watch `BugSack` (or the default error frame) through a combat session.
