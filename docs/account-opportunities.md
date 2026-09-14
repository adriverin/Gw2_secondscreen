# Account opportunities

Account opportunities normalize current checklists while preserving each endpoint's real semantics.

## World bosses

`/v2/worldbosses` returns known IDs. `/v2/account/worldbosses` is authoritative evidence that an ID was completed in the current daily period. This is a checklist, not a schedule: Phase 6A has no boss timers or guessed spawn times.

## Map chests

`/v2/mapchests` returns Hero's Choice Chest IDs; `/v2/account/mapchests` identifies current daily acquisitions. A small reviewed catalog provides friendly English labels. A “map” association means the broader map activity, not a single chest coordinate.

## Daily crafting

`/v2/dailycrafting` and `/v2/account/dailycrafting` provide public and completed IDs. Reviewed mappings connect the five current time-gated IDs to their official `/v2/items` result IDs. This structured item relationship enables goal cross-benefit; string similarity is never used.

## Raids

`/v2/raids` supplies raids, wings, events, and event types. `/v2/account/raids` supplies weekly completed event IDs. Only events whose public type is `Boss` become boss-encounter opportunities; checkpoints and unknown future event types are not counted as bosses.

## Dungeons

`/v2/dungeons` supplies dungeon/path structure and `/v2/account/dungeons` supplies path IDs completed during the current daily period. The UI groups paths by dungeon and does not infer rewards.

## Unknown IDs, labels, and navigation

Public world-boss, map-chest, and daily-crafting endpoints return identifiers rather than localized display metadata. Raid/dungeon definitions similarly omit display names. The app uses a bounded reviewed English mapping plus a deterministic readable fallback. Account IDs absent from the public response are retained as completed “Unknown …” records with their developer IDs and diagnostics.

Navigation is exposed only for reviewed map mappings. A map-only mapping does not imply an exact target. Phase 6A includes a small set of validated mappings and does not infer coordinates from names. Manual user linking remains the route for location knowledge not represented by structured or reviewed data.

All checklist completion provenance is `arenaNetAccount`; public membership/structure is `arenaNetPublic`. Local visits remain `companionObserved` and never alter API completion state.
