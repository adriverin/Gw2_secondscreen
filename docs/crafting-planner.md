# Crafting planner

## Recipe metadata and reverse index

Recipe definitions model item, currency, guild-upgrade, and unknown ingredient types defensively. The decoder accepts both typed modern ingredients (`type` plus `id`) and the live legacy representation (`item_id` plus a separate `guild_ingredients` array). On first Goals use, the app opens the persistent recipe cache, fetches the public recipe ID list, fills missing definitions in batches of 200, and writes a versioned `RecipeOutputIndex` from output item ID to sorted recipe IDs. Searches then run locally over recipe-backed item metadata. Index building is asynchronous and never blocks app launch.

When several recipes produce an item, the smallest recipe ID is the deterministic default. The user can select another recipe; its ID is saved on the goal keyed by output item ID, and the complete plan recalculates.

## Quantity propagation

For an item demand `D`, owned item quantity is allocated first. The remaining demand uses:

`batches = ceil(remaining demand / recipe output count)`

Each ingredient demand is `ingredient count × batches`, using overflow-checked integer arithmetic. This handles target quantity, ingredient counts, and recipes producing more than one output.

## Graph safeguards

Expansion carries the current item path for cycle detection and has a default depth limit of 24. Cycles, depth limits, missing recipes, guild upgrades, and unknown ingredient types become explicit terminal requirements and diagnostics. The planner never recurses indefinitely.

## Holdings allocation and flattening

The planner receives the existing Phase 2 global holdings output. It does not read inventories separately. A mutable per-item supply pool is allocated once, in deterministic ingredient order, across all branches. Intermediate items are consumed before their recipe is expanded. Terminal demands are consolidated by typed requirement key.

Thus, if two branches demand 30 ectoplasm total and the account owns 18, the flattened result is 30 required, 18 allocated, 12 missing. Branch nodes explain demand, while the flattened list is the authoritative shopping/material shortage view.

Item provenance dependencies retain account locations such as material storage, bank, shared inventory, and characters. When `inventories` permission is absent, the same graph is available but owned subtraction is disabled and the UI labels it accordingly.

## Recipe capability

Discipline/rating and recipe availability are independent signals. The highest matching character discipline is compared with the recipe rating. Availability is `autoLearned`, `known`, `locked`, or `unknown`; without `unlocks` permission the engine does not claim a non-auto-learned recipe is locked.

## Market data

Commerce prices are batched and cached for five minutes. All multiplication uses `Int64` copper. Buy-now is lowest sell offer × missing quantity. Sell-now is highest buy order × quantity. Zero orders, missing records, stale cache, and network failure remain distinct states; market failure never invalidates a material plan.

Current-price comparisons do not include a generalized opportunity-cost model and are not called value, profit, or an optimal strategy.

## Current limitations

Ordinary recipe data cannot represent every legendary, Mystic Forge, collection, vendor, or reward chain. Guild upgrades are visible but unsupported. The acquisition model is method-agnostic so future curated providers can be added without equating every item with a recipe.
