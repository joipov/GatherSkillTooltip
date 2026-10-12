# Gather Skill Tooltip audit — 2026-10-12

Target: World of Warcraft Forever, `## Interface: 16001`, Lua 5.1.
References: Ketho's vscode-wow-api annotations, the Forever API, and the other Joipov addons.

## Already in good shape

Secret guards, locale loading, and the single minimap position key from the 2026-10-11 pass still hold. The warning poll runs at 1 Hz only while a warning is showing.

## This pass

- The minimap button is the shared launcher. Click still opens settings.
- Ticket ids are gone from comments.
- The local annotation stub is `.annotations/Wow.lua`.
- TOC fields follow the house order.
- Ketho's annotation path stays in `.luarc.json`. That file is the library list LuaLS uses for this addon.

## Left as-is

The tooltip post-calls and the `GameTooltip` `OnShow` fallback both stay. Some tooltips never get a data post-call, so the fallback is the path that still sees them.
