# Roblox Stats Bar

Local macOS menu-bar app for tracking Roblox game stats.

## Live metrics

- Aggregate current CCU across enabled games
- Per-game CCU
- Per-game total visits
- Per-game favorites
- Game name, universe ID, and root place ID

These currently come from Roblox public game endpoints and do not require storing Roblox account cookies.

## Creator Hub metrics

The app reserves menu rows for the requested dashboard-backed metrics:

- D1 retention
- D7 retention
- 72h Robux sales
- Total sales
- Performance error count
- Playthrough rate

Those rows are marked `Pending` until a stable authenticated Creator Hub source is added. The repo should not contain personal game IDs, account cookies, `.ROBLOSECURITY`, or local config.

## Build and Run

```sh
scripts/build_app.sh
open "dist/Roblox Stats Bar.app"
```

## Config

Config is stored locally:

```text
~/.config/roblox-stats-bar/config.json
```

Use **Manage Games...** from the menu bar to add universe IDs, Roblox game URLs, or Creator Hub experience URLs.
