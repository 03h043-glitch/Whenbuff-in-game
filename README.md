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

For current data, use the local scheduled refresh below or rely on the included GitHub Action to refresh the repository copy of `Data.lua` on a schedule.

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
powershell -ExecutionPolicy Bypass -File tools\update-data.ps1 -Days 60
```

The script fetches WhenBuff servers and future buffs, then rewrites `Data.lua`.

## Automatic Local Refresh

Install a Windows scheduled task from the addon folder:

```powershell
powershell -ExecutionPolicy Bypass -File tools\install-daily-refresh.ps1
```

By default this refreshes `Data.lua` once immediately, once every day at 07:00, and once when you log into Windows. It uses a 60-day lookahead so future scheduled buffs are gathered as well.

Optional examples:

```powershell
powershell -ExecutionPolicy Bypass -File tools\install-daily-refresh.ps1 -DailyAt 12:00
powershell -ExecutionPolicy Bypass -File tools\install-daily-refresh.ps1 -Days 90
```

If WoW is already open when `Data.lua` changes, run `/reload` so the addon reloads the updated file. The in-game `/wb refresh` command refreshes the display from data already loaded by WoW; it cannot fetch the website directly.

## Repository Refresh

The GitHub Action refreshes the repository copy of `Data.lua` every 6 hours with the same 60-day lookahead. That keeps the repo current, while the Windows scheduled task keeps your installed addon folder current.

## Current Supported Realms

The addon supports the realms returned by WhenBuff's `/servers` endpoint. If your logged-in realm is not in that endpoint, the addon will show a no-data state instead of guessing.