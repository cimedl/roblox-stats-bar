# Data Sources

Roblox Stats Bar keeps supported public stats separate from Creator Hub-only dashboard metrics.

## Public live stats

The app refreshes these from public Roblox endpoints without account cookies:

- Current CCU
- Visits
- Favorites
- Game name
- Universe ID
- Root place ID

## Creator Hub metrics

The menu can display these metrics from a local cache:

- D1 retention
- D7 retention
- 72h Robux sales
- Total sales
- Performance error count
- Playthrough rate

Use `Update Creator Hub Metrics...` to save values locally after checking Creator Hub. The cache lives at:

```text
~/.config/roblox-stats-bar/dashboard-metrics.json
```

## API boundary

Roblox's Open Cloud docs index says analytics/engagement data and revenue breakdowns are not exposed through supported REST APIs and recommends using Creator Dashboard for those values:

```text
https://create.roblox.com/docs/cloud/llms.txt
```

The app therefore avoids committing or storing account cookies such as `.ROBLOSECURITY`, avoids checking in personal universe IDs, and keeps dashboard-backed values in a local ignored cache.
