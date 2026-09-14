# Onboarding and degraded modes

The first launch presents Welcome → ArenaNet account → gaming PC → Ready. Account and PC setup can each be skipped. Completion is stored as `onboarding.completed.v1`; Reset App clears it.

Recommended ArenaNet permissions are exactly those used by the app: `account`, `characters`, `inventories`, `builds`, `progression`, `unlocks`, and `wallet`. Trading Post account history is not used, so `tradingpost` is not requested. The key is validated directly with ArenaNet before being stored.

An account-only user starts on Today and can use account, goals, inventory, characters, and planning. A PC-only user starts on Map and can use live position, public objectives, gathering, and navigation. Skipping both keeps the public map available. Settings can complete either setup later.

The camera is requested only when Scan Bridge QR Code is selected. GPS/location permission is never requested. Manual pairing remains available when camera permission is denied or scanning is unsupported.
