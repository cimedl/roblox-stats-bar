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

On startup and refresh, the app attempts a local-only Creator Hub fetch from the active Chrome Roblox session. Use **Update Creator Hub Metrics...** from the menu bar to fetch a selected game on demand, open the selected game's Creator Hub page, or manually save fallback values into the local dashboard metric cache.

Roblox's current Open Cloud docs say analytics/engagement and revenue breakdown data are not exposed through a supported REST API, so the authenticated Creator Hub fetch uses private dashboard endpoints and a local ignored cookie file. See [docs/data-sources.md](docs/data-sources.md).

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

Optional authenticated Creator Hub cookie fallback:

```text
~/.config/roblox-stats-bar/roblox-cookie.txt
```

The app first attempts to read Chrome's encrypted local Roblox session. The cookie file can contain either the raw cookie value or `.ROBLOSECURITY=<value>` as a fallback. It is local-only and ignored by git.

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
