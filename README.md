# WhenBuff In-Game

WoW Classic addon for showing upcoming WhenBuff world buff drops for the realm your character is logged into.

## What It Does

- Detects the current WoW realm on login.
- Opens a movable in-game window for that realm automatically.
- Shows all upcoming world buffs from generated WhenBuff data, including future days.
- Shows a live `HH:MM:SS` countdown to the next buff.
- Includes a resizable mini window with the next buff icon, shorthand name, countdown, and faction-aware Onyxia filtering.
- Prints chat reminders 1 hour, 30 minutes, 15 minutes, and 5 minutes before a buff drops.

## Important Data Note

WoW addons cannot make live HTTP requests while the game is running. This addon uses a generated `Data.lua` file that is refreshed from `https://api.whenbuff.com`.

For current data, run the updater before launching WoW or rely on the included GitHub Action to refresh `Data.lua` on a schedule.

## Install

Place this folder in:

```text
World of Warcraft\_classic_\Interface\AddOns\WhenBuffInGame
```

Then restart WoW or run `/reload`.

## Commands

- `/wb` or `/whenbuff`: toggle the window
- `/wb show`: show the window
- `/wb hide`: hide the window
- `/wb mini`: toggle the resizable mini window
- `/wb options`: open exact width/height controls for both windows
- `/wb refresh`: rebuild the current realm view from loaded data
- `/wb test`: print a test reminder message

Both windows can be dragged and resized from a larger bottom-right handle. The mini window opens options on right click.

## Updating Data Locally

Run:

```powershell
node tools/update-data.js --days 35
```

The script fetches WhenBuff servers and future buffs, then rewrites `Data.lua`.

## Current Supported Realms

The addon supports the realms returned by WhenBuff's `/servers` endpoint. If your logged-in realm is not in that endpoint, the addon will show a no-data state instead of guessing.
