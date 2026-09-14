# Wizard's Vault

Phase 6A supports the current season plus Daily, Weekly, Special, and Astral Reward listings.

## Objectives and meta progress

`/v2/account/wizardsvault/daily` and `/weekly` supply objective titles, tracks, acclaim, progress, claim state, meta progress, meta item/acclaim rewards, and meta claim state. `/special` supplies season-scoped objectives without forcing them to use daily or weekly urgency.

Progress and claim are deliberately independent. Reaching `progress_complete` never implies `claimed`. Complete-unclaimed objective and meta rewards are highlighted as “Ready to claim in game”; there is no network action behind that label.

`/v2/wizardsvault` supplies the season title and availability strings. `/v2/wizardsvault/objectives` is retained as public metadata/provenance; current account objective membership remains authoritative from the account response. Season names are never hard-coded.

## Rewards and wishes

Public `/v2/wizardsvault/listings` supplies the seasonal catalog. Account `/listings` adds optional `purchased` and `purchase_limit` values. Featured, Normal, and Legacy are grouped; unknown future listing types decode to `unknown(rawValue)` and appear in diagnostics.

Reward item names/icons resolve through `/v2/items`. The local account-scoped wish list stores listing IDs. For wished rewards, the UI performs only direct arithmetic against the current Astral Acclaim balance: remaining balance or additional acclaim needed. It never recommends a purchase.

Astral Acclaim is resolved by requesting public currency metadata for the live-validated stable ID and confirming the returned name before matching `/v2/account/wallet`. If validation or wallet permission is unavailable, the UI says the balance is unavailable.

## Cache and known API limitations

Season/public listing metadata uses the long public cache. Purchased counts use the short account cache. A changed season identity replaces seasonal catalog data.

The authenticated listings endpoint has documented upstream caveats: purchased counts have historically been reported incorrectly, and data may not update until a character logs in during the current season. The Companion displays the API value and its stale state; it does not repair or infer purchases.
