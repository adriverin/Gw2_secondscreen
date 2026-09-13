# Account data architecture

## Authentication and permissions

`GW2APIClient` is the single owner of ArenaNet HTTP requests. The API key is read from `CredentialStore` only while an authenticated request is built and remains protected by the device Keychain. It is never placed in telemetry, `UserDefaults`, logs, UI state, or the Windows bridge.

The app validates a new key through `/v2/tokeninfo` before saving it. `AccountStore` converts the returned strings into a centralized `PermissionSet` and checks each feature before loading it:

- `account`: account identity and home world
- `characters`: roster and character summaries
- `inventories`: character bags, bank, shared inventory, and materials
- `builds`: equipment tabs and build tabs
- `wallet`: wallet quantities and currency metadata

A missing permission affects only its section. The live map and MumbleLink connection never require an API key.

## ArenaNet endpoints

Authenticated account loads use:

- `/v2/tokeninfo`, `/v2/account`, and `/v2/worlds/{id}`
- `/v2/characters?page=…&page_size=…`
- `/v2/characters/{name}/inventory`
- `/v2/characters/{name}/equipmenttabs?tabs=all`
- `/v2/characters/{name}/buildtabs?tabs=all`
- `/v2/account/bank`, `/v2/account/inventory`, `/v2/account/materials`, and `/v2/account/wallet`

Static metadata is resolved in batches through `/v2/items`, `/v2/currencies`, `/v2/professions`, `/v2/specializations`, `/v2/traits`, `/v2/skills`, `/v2/skins`, and `/v2/materials`. The existing live-map path continues to use the public map/floor endpoints.

## Loading coordination

`AccountStore` is the main-actor observable domain store shared by all four app areas. It coordinates account identity, roster, inventories, wallet, holdings, and detail loads so views do not independently request the same account payloads. Pull-to-refresh refreshes account data; it does not poll. Live telemetry stays in the separate `TelemetryStore` real-time pipeline.

The app restores its last successful `AccountSnapshot` before refreshing. If the refresh fails, saved values remain visible and the UI marks them as saved/stale instead of replacing the screen with an error.

## Static metadata and request batching

The `GW2APIClient` actor owns typed in-memory caches backed by atomic Codable files for items, currencies, professions, specializations, traits, skills, skins, material categories, maps, and floors. ID lists are deduplicated, sorted, and split into endpoint-safe batches of at most 200. Equal in-flight metadata batch requests share one task.

Remote icon artwork goes through `RemoteImagePipeline`, which provides an `NSCache` memory tier, hashed disk files, concurrent-request deduplication, cancellation checks, placeholders, and graceful failure. The UI does not depend on repeated `AsyncImage` downloads.

## Global holdings aggregation

The account inventory domain is deliberately independent of SwiftUI. `AccountHoldingAggregator` accepts `(ItemLocation, [InventorySlot])` sources and emits one `AccountHolding` per item ID. Locations are:

- `character(name)`
- `bank`
- `sharedInventory`
- `materialStorage`

Each holding retains a total quantity plus the quantity in every location. `HoldingSearch` joins that index to already-resolved item metadata and performs immediate localized case-insensitive filtering and name, quantity, or rarity sorting. Typing in search causes no network request.

## Current character matching

`TelemetryStore` publishes the MumbleLink character name. `AccountStore` passes it to `CurrentCharacterMatcher`, which first checks the exact ArenaNet character name and then accepts a unique case-insensitive match after trimming surrounding whitespace. Ambiguous or unknown names do not select a character.

The match is available to the roster and live map. The map quick panel deep-links through `AppNavigation` to the matching character's Equipment, Build, or Inventory section. When no API key is connected, the raw live character name remains visible and the map continues working.

## On-device portraits

PhotosPicker selections are resized, JPEG-compressed, and saved under Application Support with a SHA-256 key derived from account and character names. Portraits never leave the device and have an explicit remove action.
