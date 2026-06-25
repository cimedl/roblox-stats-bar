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

The app has menu rows for the requested dashboard-backed metrics:

- D1 retention
- D7 retention
- 72h Robux sales
- Total sales
- Performance error count
- Playthrough rate

Use **Update Creator Hub Metrics...** from the menu bar to save values from Creator Hub into the local dashboard metric cache. The app can also open the selected game's Creator Hub page from that window.

Roblox's current Open Cloud docs say analytics/engagement and revenue breakdown data are not exposed through a supported REST API, so the app does not store `.ROBLOSECURITY` cookies or scrape private dashboard endpoints. See [docs/data-sources.md](docs/data-sources.md).

The repo should not contain personal game IDs, account cookies, `.ROBLOSECURITY`, or local config.

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

Optional dashboard metric cache:

```text
~/.config/roblox-stats-bar/dashboard-metrics.json
```

Example shape:

```json
{
  "metrics": [
    {
      "universeId": 1234567890,
      "d1Retention": "18.4%",
      "d7Retention": "4.9%",
      "robuxSales72h": "12,340",
      "totalSales": "245,900",
      "performanceErrors": "3",
      "playthroughRate": "61%",
      "updatedAt": "2026-06-25T20:00:00Z"
    }
  ]
}
```
