# Achievement tracking

## Public hierarchy and metadata

The browser uses `/v2/achievements/groups` and `/v2/achievements/categories` ordering. Detailed definitions are fetched in category-sized batches and cached persistently; the app does not download every achievement detail at launch. Search is local over loaded name, description, requirement, and category text.

Supported bit types are Text, Item, Skin, and Minipet. Item, skin, and mini labels resolve through their public metadata endpoints when available. Unknown future bit types are preserved and shown defensively.

## Account progress

`/v2/account/achievements` is merged by achievement ID. `done`, count progress, repeated progress, and completed bit indices remain ArenaNet account facts. Without `progression` permission, public browsing still works and every completion value is unknown. Text alone never implies completion.

Skin and mini ownership hints use account unlock endpoints only when `unlocks` permission exists. An unlock hint does not override authoritative achievement bit progress.

Tracking creates the shared `PlayerGoalType.achievement` goal. Refreshing account progress updates the displayed goal without recreating it.

## Geographic limitation and manual links

Achievement bits do not generally include coordinates. The app therefore shows **No map location available** unless a user explicitly links a bit to an existing current-map objective or saves the live player coordinate. Links are editable by replacement and removable in the goal model; their provenance is `userDeclared`.

A linked objective can enter the existing Phase 3 navigator. Reaching it records only Companion visit history. The app never claims that visit completed the achievement bit; only a later ArenaNet account refresh can do that.

Wiki scraping, inferred name-to-location matching, and invented coordinates are intentionally out of scope.
