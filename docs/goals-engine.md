# Goals engine

## Shared model

`PlayerGoal` is the only goal persistence model. Its `PlayerGoalType` supports achievements, craftable items with quantity, and custom goals. All types share priority, status, source reference, map links, selection, and presentation. Statuses are active, paused, completed, and archived. Crafting goals are never automatically marked complete merely because their requirements are ready.

## Account scoping and persistence

Goals are encoded as a versioned `GoalScopeSnapshot` in local preferences. The storage key uses the stable ArenaNet account ID. Changing API keys saves the old scope and loads the new account's scope, so display names and data from different accounts never mix. With no authenticated account, the app uses an isolated local-anonymous scope.

Custom checklists and all manual map links are `userDeclared`. Account-specific goals remain safely stored if another account becomes active.

## Progress

- Achievement completion and count/bit progress come from `/v2/account/achievements` and are authoritative when `progression` permission exists.
- Crafting reports distinct flattened final requirements ready. It avoids a fake precision percentage dominated by bulk unit counts.
- `Target already owned` means holdings contain the requested final quantity. It does not claim the target was crafted.
- Custom progress is the number of manually checked items.

## Suggested actions

`SuggestedActionEngine` is a deterministic rules engine, not AI. Each action includes a reason, confidence, provenance, score, and optional `MapObjectiveID` values.

The current score is:

- same current map: +100
- navigable: +80
- goal priority high/normal/low: +50/+25/+0
- distance: +0 through +30, decreasing by one per 100 continent units
- all requirements ready to craft: +40
- current sell listings available: +20
- generic inspection: +5

Scores rank immediate convenience only; they do not represent optimal gameplay. Diagnostics show every score and reason. Missing telemetry removes map and distance bonuses without breaking actions.

Navigation adapts action objective IDs into the existing Phase 3 `NavigationRoute` and `MapObjectiveStore`. It does not introduce a second navigator.

## Refresh

Achievement account progress refreshes when Goals opens, on pull-to-refresh, and explicitly. Holdings refresh only through the account refresh path. Neither is polled at MumbleLink frequency. Goal calculation continues with saved metadata when offline.
