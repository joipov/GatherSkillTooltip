# GatherSkillTooltip

Shows your gathering skill and the skill a node requires when you hover a
herb or ore (in the world or on a minimap pin), and puts your Skinning skill
beside the level of a creature you can skin. Learns from play: which NPCs are
skinnable, and at which skill a node actually stopped giving skill-ups.

Target client: World of Warcraft **Forever** (`camelot`, TOC `## Interface: 16001`).

## Features

- Herb and ore tooltips: `Peacebloom (70/1)`, colored red/orange/yellow/green/grey
  by difficulty. Stacked minimap pins are handled line by line.
- Skinning: `Level 12 (Skinning 100/20)` on creatures you can skin. NPC ids are
  learned from the "Skinnable" line on your own, fully looted corpses; unknown
  NPCs fall back to creature type (Beast, Dragonkin).
- Learned difficulty: a skill-up recorded below the table's orange threshold
  lowers it; repeated misses without a gain turn a node grey.
- Warnings: an on-screen banner when Find Herbs / Find Minerals is off and
  you know the profession, and a trainer reminder when a profession is capped.
- Minimap launcher via LibDBIcon when present, otherwise a built-in button;
  Addon Compartment entry; `/gst` opens the settings.

## Commands

| Command | Effect |
| --- | --- |
| `/gst`, `/gatherskilltooltip` | Open the settings panel |
| `/gst debug` | Toggle debug output (unmatched tooltip names, learning traces) |
| `/gst stats` | Print the GameTooltip fallback counters (diagnostic) |

## Files

Loaded in TOC order; modules communicate only through the shared `ns` table.

| File | Concern |
| --- | --- |
| `Data.lua` | Skill line / spell ids, node tables (`NODES`, `NODE_BY_KEY`) |
| `Locales.lua` | Strings, node name aliases, `ns.LOOKUP` |
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
mklink /J "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\GatherSkillTooltip" "%USERPROFILE%\dev\GatherSkillTooltip"
```

Static checks (no game client needed):

```
luacheck .            # .luacheckrc: Lua 5.1, explicit WoW globals
luajit tests/run.lua  # or: lua5.1 tests/run.lua
```

LuaLS uses `.luarc.json`; the repo-local `.annotations/` folder declares the
Blizzard globals the Ketho WoW API annotations lack.

Releases: push an annotated tag (`git tag -a 2.0.0 -m "2.0.0"`); the
`Package and release` workflow runs BigWigsMods/packager, which reads the game
version from the TOC and the manual changelog from `CHANGELOG.md`.
`CODE_AUDIT.md` holds the audit and remediation record.

## Verifying in-game

- Hover Peacebloom / Copper Vein in the world and on the minimap; check
  stacked pins and an unknown object (no rewrite; `/gst debug` prints it).
- Skinning: living beast (no line), your own unlooted dead beast (no "cannot
  skin" learned), looted skinnable (line, learned), humanoid (no line).
- Toggle Find Herbs / Find Minerals in and out of combat; the banner appears
  within a second and clears when tracking is back on.
- Watch `BugSack` (or the default error frame) through a combat session.
