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

On startup and refresh, the app attempts to fetch Creator Hub metrics from authenticated private dashboard endpoints by reading the active Chrome Roblox session. It caches both display values and raw daily series for the Analytics menu graphs.
Playthrough rate uses Creator Hub's acquisition PTR metric, with a fallback to the broader acquisition conversion rate if the qualified PTR metric is unavailable.

The cache lives at:

```text
~/.config/roblox-stats-bar/dashboard-metrics.json
```

The optional local cookie fallback lives at:

```text
~/.config/roblox-stats-bar/roblox-cookie.txt
```

The app first tries Chrome's encrypted local cookie store and decrypts the Roblox session through Chrome's macOS Keychain secret. This file can contain either the raw cookie value or `.ROBLOSECURITY=<value>` as a fallback. It is intentionally ignored by git.

## API boundary

Roblox's Open Cloud docs index says analytics/engagement data and revenue breakdowns are not exposed through supported REST APIs and recommends using Creator Dashboard for those values:

```text
https://create.roblox.com/docs/cloud/llms.txt
```

The app therefore avoids committing account cookies such as `.ROBLOSECURITY`, avoids checking in personal universe IDs, and keeps dashboard-backed values in a local ignored cache. The authenticated fetcher is a private personal dashboard integration and may break if Roblox changes Creator Hub internals.
