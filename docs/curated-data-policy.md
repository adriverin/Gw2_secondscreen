# Curated data policy

Phase 5 favors explicit scope and provenance over broad coverage.

- Do not scrape or bulk-copy Guild Wars 2 Wiki, GW2Efficiency, Fast Farming, Reddit, marker packs,
  or other fan sites.
- Represent a small number of independently reviewed facts in original wording.
- Every curated record must identify the Companion catalog source and review date.
- ArenaNet API-derived records and Companion-curated records remain distinguishable in storage
  and UI.
- Exact coordinates are included only when the source supports them. Map-only facts stay
  map-only.
- `complete`, `partial`, and `exampleOnly` coverage are data, not marketing labels. Version 1 is
  deliberately example-only overall and partial for gathering mappings.
- User additions are stored separately with `userDeclared` provenance and win only stable-ID
  conflicts. A catalog update never deletes or overwrites them.
- Confidence describes the represented fact, not a guarantee of live spawn, vendor inventory,
  price, acquisition, or yield.

The initial catalog validates the architecture with common ore/wood mappings and a few guarded
vendor, Mystic Forge, achievement, and manual examples. It is not a comprehensive game database.
All costs and transformations with limited representation instruct the player to verify current
in-game conditions before spending resources.

No remote catalog, remote configuration, analytics service, or cloud account is used. A future
remote provider must be signed and must pass the same validation before it can enter the merge
pipeline.
