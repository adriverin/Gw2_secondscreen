# World objectives

## Source and supported types

The active map is identified with public `GET /v2/maps/{mapId}` metadata. The app then requests the matching public `GET /v2/continents/{continentId}/floors/{floor}?lang={language}` hierarchy and selects only the object whose map ID matches live telemetry.

`MapObjective` is the shared presentation model for official waypoints, vistas, points of interest, renown hearts, hero challenges, mastery insights and adventures, plus separately supplied gathering and future user markers. Data providers remain independent; the live renderer, Nearby list and route engine consume the combined objective list.

Official responses are defensive: missing collections are treated as empty, malformed coordinates are skipped, and a map that cannot be found in its reported floor produces no stale markers.

## Coordinates

Official objective `coord` values are continent coordinates. They are used directly by map tiles, proximity and navigation. Gathering data is transformed once through `GW2CoordinateTransformer` before it becomes a `MapObjective`. No view applies independent offsets or Y-axis corrections.

## Cache

Official objective snapshots are keyed by schema version, continent, floor, map ID and language. A current snapshot is reused for 30 days. After that, the client refreshes it; if refresh fails, the last compatible snapshot remains available offline. Map metadata continues to use the existing persistent metadata cache. Increasing `MapObjectiveCacheEnvelope.currentSchemaVersion` invalidates incompatible records without deleting unrelated cached metadata.

## Completion limitation

The world-map API describes objects; it does not provide reliable generic per-character completion for individual waypoints, vistas, POIs or hearts. `/v2/characters/:id/heropoints` is not used because it is not a reliable completion source.

The domain therefore keeps separate local meanings:

- `unknown`: not observed by Companion;
- `visited`: Companion observed the player within the objective's arrival radius;
- `manuallyCompleted`: the user explicitly marked it complete;
- `skipped`: the user skipped it locally.

Automatic arrival never becomes `manuallyCompleted`, and UI copy never claims “completed in Guild Wars 2.” Visit history is stored locally under the active account/character scope when available.

## Live validation (2026-09-13)

Public API checks required no key. `/v2/maps/15` reported Queensdale on continent 1, region 4, default floor 1, with current continent rectangle `[42624, 28032]–[46208, 30464]`. Its detailed continent-map response contained 16 waypoints, 9 vistas, 21 landmarks, 1 additional `unlock` POI, 17 hearts and 7 hero challenges. The `unlock` type is deliberately represented as a generic point of interest.

`/v2/maps/1052` reported Verdant Brink on continent 1, region 10, default floor 1. Its detailed response contained 9 mastery insights and 5 adventures; live values confirmed mastery IDs are numbers and adventure IDs are UUID strings.

The repository's older Queensdale simulations used the former continent placement near `(11710, 13370)`. Live metadata now places the same map exactly `+32768` X and `+16384` Y from that old rectangle. Both bridge and iOS simulations, plus synthetic gathering markers, were shifted to the current rectangle. The simulation ellipse crosses official hero challenge `0-7` at approximately `(45135.5, 29863.7)`, enabling the Phase 3 arrival flow without claiming real character completion.
