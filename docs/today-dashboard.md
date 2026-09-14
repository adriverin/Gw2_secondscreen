# Today dashboard

Phase 6A evolves the Session destination into the daily/weekly entry point. It does not add a second planning engine. `TodayRepository` loads and caches API data, `TodayMerger` produces account-current `AccountOpportunity` values, and `TodayStore` is the main-actor presentation facade shared by SwiftUI and the Session Planner.

## Data flow

```text
ArenaNet public metadata (long TTL) ─┐
ArenaNet account state (5 minute TTL)├─ TodayMerger ─ AccountOpportunity[]
local reward wishes                  ┘                     │
                                                           └─ SessionPlanner
```

The public catalog contains the current Vault season, Vault objective/listing metadata, checklist IDs, raid definitions, dungeon definitions, item metadata, and validated Astral Acclaim currency metadata. Account data supplies current Vault progress/claim state, purchases, and completed checklist IDs.

## Reset scopes

- `daily`: Vault Daily, world bosses, map chests, daily crafting, dungeon paths.
- `weekly`: Vault Weekly and raid boss encounters.
- `seasonal`: Vault Special objectives.
- `none`: reserved for account-current opportunities without a reset window.

The UI says “Current Daily”, “Current Weekly”, or “This Vault Season”. It intentionally does not calculate countdowns. A future exact countdown must live in a dedicated reset service backed by a documented trustworthy source.

## Completion and claim semantics

Checklist completion comes only from the matching ArenaNet account endpoint. `companionObserved` and user interaction are never promoted to ArenaNet completion. Vault progress completion and reward claim are separate fields: complete plus `claimed == false` becomes `completeUnclaimed`; complete plus `claimed == true` becomes `completeClaimed`.

The app has no claim or purchase mutation. “Ready to claim in game” is informational.

## Refresh and offline behavior

Account Today state uses a five-minute TTL. App foreground calls `refreshIfNeeded`; the dashboard offers pull-to-refresh and a Refresh button; active Session “Refresh Progress” refreshes Today too. There is no continuous polling and telemetry updates do not rebuild Today.

Public metadata uses a 24-hour TTL and a separate disk record. The current Vault season identity is title + start + end; refreshed season metadata replaces the catalog and its listing set. Account listings and purchase counts are never treated as static metadata.

The last successful account-scoped merged snapshot is cached. If refresh fails, it remains visible with Offline/stale labeling and its original timestamp. A session plan can continue using those cached opportunities. API responses replace current daily/weekly sets; local calendar boundaries are not used to merge old completion into a new response.

## Permissions and localization

Progression endpoints require `account` and `progression`. Without progression, public checklists render with unknown account completion and the dashboard explains the required permission. Wallet balance additionally requires `wallet`. Missing permissions do not affect map, character, or inventory features.

Locale-aware endpoints receive the app/API language value. Reviewed fallback labels are currently English because several public endpoints expose identifiers only; the gap is explicit and does not block localization of API-provided Vault titles.
