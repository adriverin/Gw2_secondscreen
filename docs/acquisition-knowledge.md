# Acquisition knowledge

Phase 5 introduces a reusable acquisition domain between goals and presentation. An
`AcquisitionMethod` has a stable Companion ID, typed target, method type, structured
requirements, optional mixed cost, optional location, confidence, coverage, and a
`KnowledgeSource`.

Targets are tagged records rather than item-only assumptions. Version 1 supports items,
currencies, achievements, and custom targets. Requirements separately support items,
currencies, achievements, map access, crafting disciplines, vendor interaction, references to
other acquisitions, and manual conditions. Costs can contain coin, currencies, and items at the
same time. Locations distinguish exact coordinates, map-only knowledge, objective references,
and unknown locations. A coordinate is never synthesized when only a map is known.

`AcquisitionKnowledgeStore` is the authoritative query layer. It indexes methods by target and
merges sources with deterministic stable-ID precedence:

1. user-declared methods
2. current ArenaNet API-derived methods
3. the bundled curated catalog

User methods are persisted separately, so bundled updates cannot overwrite them. API recipe
records create craft methods and current sell listings create Trading Post methods. The Phase 4
compact `AcquisitionOption` UI model has an adapter from the new method model; the recursive
`CraftingPlanner` remains unchanged.

The bundled provider implements `AcquisitionCatalogProvider`. A future signed remote provider
can implement the same protocol, but Phase 5 performs no remote catalog download.

Every method retains its source type, identifier/URL when applicable, review time, and notes.
Companion-curated information is never labeled as ArenaNet API data. Exact source and coverage
are inspectable in task detail.

Catalog validation rejects unsupported schemas, empty versions, duplicate IDs, malformed or
non-positive target/requirement IDs and quantities, negative/malformed mixed costs, partial or
mapless coordinates, unknown maps when a known-map set is supplied, missing curated source
identifiers, and direct self-referential acquisition cycles.

