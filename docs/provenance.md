# Phase 4 data provenance

`DataProvenance` is the common vocabulary for every fact shown by the goals engine.

| Value | Meaning | Example |
| --- | --- | --- |
| `arenaNetAccount` | Authenticated account state returned by ArenaNet | achievement completion, inventory quantity |
| `arenaNetPublic` | Public game definition or current public market data | recipe ingredient, item name, lowest sell offer |
| `liveTelemetry` | Current MumbleLink bridge observation | current map and player position |
| `companionObserved` | Local observation or validated bundled Companion knowledge | visit history, validated gathering mapping |
| `userDeclared` | A fact explicitly entered or linked by the user | achievement-bit map link, custom checklist |
| `derived` | Deterministic calculation from other facts | missing quantity, action score, buy-now estimate |

Derived values carry `ProvenanceDependency` records. A material shortage, for example, records public recipe demand and account-owned quantities by location. The requirement detail screen exposes these dependencies under **Why?**.

Provenance does not turn a weak fact into an authoritative one. A Companion-observed visit is not achievement completion. A user-linked coordinate is navigable but is not an ArenaNet-provided achievement location. An account holding proves current ownership, not that the item was crafted.

Cache age is separate from provenance. A stale Trading Post record is still ArenaNet public data, but the UI marks its timestamp and stale state. Offline calculation retains the last recipe and account inputs and does not silently replace them with assumptions.
