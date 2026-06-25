# Roblox Stats Bar

Local macOS menu-bar app for tracking public Roblox game stats.

## Current metrics

- Aggregate current CCU across enabled games
- Per-game CCU
- Per-game total visits
- Per-game favorites
- Game name, universe ID, and root place ID

The app also shows the requested dashboard-only metrics as pending source items:

- D1 retention
- D7 retention
- 72h Robux sales
- Total sales
- Performance error count
- Playthrough rate

Those are not pulled in this MVP because the reliable public Roblox endpoints do not expose them. A later Creator Hub connector can plug into the same menu once a stable authenticated source is chosen.

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
