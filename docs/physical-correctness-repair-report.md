# Recording follow-up: atomic map handoff, stat sources, TP async state

2026-10-02. Continues the existing continuous camera; no new features, Legendary content, or screen redesign. This supersedes the handoff/source-status portions of the earlier continuous-map report, not its camera/projection/pyramid implementation.

## 1. Black map rectangles: code-level cause

The retained complete frame covered its **old viewport**, not every continent coordinate exposed after zooming out or panning. Under that crop, `NativeTileMapView` drew a progressive old-source `MapTileImage` grid. Missing images were translucent placeholder rectangles, exposing the dark map background. Emergency fill also stopped after 96 tiles. A whole-frame completeness check on incoming images therefore did not guarantee complete visual backing for the moving camera.

The readiness request also included a padded prefetch ring, allowing a failed non-visible tile to delay a usable visible replacement. Same-source Detailed failure did not always start a native fallback. The outgoing layer had no complementary fade.

These are verified code paths consistent with the recording description. The physical video itself was not supplied as an inspectable file, so this is not a frame-by-frame forensic claim about it.

## 2. Atomic handoff repair

- Keep the current complete frame fully opaque while the desired frame loads. Incoming images never render individually.
- Separate **visible tile requests** from prefetch. Promotion requires every visible image, not the ring.
- Retain a complete low-resolution native continent mosaic below the viewport frames. This uses the same existing tile provider/projection/camera transform and covers newly exposed geography beyond the old crop. Tyria needs six z0 tiles (all six public URLs returned HTTP 200). It is a small visual safety backing, not a replacement camera or Detailed architecture.
- No progressive tile placeholder renderer remains in this path. A true cold start shows a loading indicator until complete backing exists; it does not pretend unfetched artwork is available.
- `begin(request)` obsoletes older targets; promotion validates target identity, continent, floor and exact visible tile set. Cancellation guards reject late work, including ABA return-to-an-earlier-request races.
- A complete incoming frame crossfades 0→1 while outgoing fades 1→0 over 150 ms. Both tile levels use the current fractional transform. Cleanup is identity-guarded.
- Interrupting a fade keeps the already-complete incoming frame opaque. Failed visible Detailed coverage falls back only to a complete native frame; native failure retains current backing and retries. Prefetch runs after promotion and never installs its frame.

Geographic projection, source hysteresis, camera anchoring, marker transforms, Detailed z4 pyramid/cache budgets and map chrome are unchanged. Tile-debug labels remain available.

## 3. Physical-like rapid zoom regression

Unit tests reproduce Kessex-centered 1024×1366 fractional zoom/pan sequences, one failed visible tile, old/new request races, cancelled loading, interrupted fades, and Detailed→native replacement. They check complete retained artwork covers the newly exposed viewport, pending opacity stays 1, and both layers share the continuous transform.

A DEBUG-only UI fixture delays incoming native/derived frames and deliberately fails Detailed z4. The UI test pinches outward, pans, reverses zoom and captures screenshots; a central pixel sample rejects large dark regions after each gesture. It passed on iPad and iPhone. Synthetic colored tiles isolate compositing/loading behavior; they are **not physical-device or real-network proof**. Existing real Kessex imagery/projection/seam tests remain in the full unit suite. Production Release builds contain no fixture branch.

## 4. Why Great Fortitude failed in the recording

The [current ArenaNet trait 1449 response](https://api.guildwars2.com/v2/traits/1449), fetched 2026-10-02, contains `BuffConversion`, Power→Vitality 10 and Power→CritDamage 10. Those facts match the **pre-change** catalog. A regression now explicitly demonstrates that. The existing matcher was already structural, not byte-for-byte, and already ignored fact ordering/descriptions and counted duplicate facts only once per curated rule.

Therefore the recording's exact historical mismatch **cannot be honestly established from the supplied numbers and source IDs alone**. The failing physical device's cached/raw trait payload is absent. A stale/partial cache or dropped decoded fact is possible, not proven. The repair does not invent a claimed ArenaNet payload change.

A concrete decoder vulnerability was found: synthesized `TraitFact.value: Int?` could reject an entire conversion fact if an irrelevant `value` evolved to a non-integer. Since `TraitMetadata` uses a lossy facts array, that fact would disappear before matching. The new test reproduces this failure mode, but it does not claim the current live 1449 payload has such a field.

## 5. Great Fortitude repair and safe gating

`TraitFact` decodes required type/structural fields independently of irrelevant text/value fields. Percent remains numeric; no prose or fractional-percent guess is accepted. For 1449 only, the structured semantic target `Ferocity` is accepted alongside ArenaNet's canonical `CritDamage` alias. Reordering, duplicate facts, localization, unrelated extra fields and integer/Double percent representations are tested. Trait catalog version is `pve-2026-10-02-v3`.

The engine still requires **1449 selected in active Strength 4**, verified 10% Power conversions, and one immutable pre-conversion snapshot. Each contribution floors independently; no feedback, character override, default prefix, extra crit modifier or Health-formula change.

At 1873 resolved Power, each conversion is 187. Existing 73 Ferocity becomes 260, critical damage is 167.333…%. Pinnacle remains +5 percentage points: Precision 1170 produces 18.095238…%. Warrior Vitality 2051 produces 29722 Health. Tests cover these formulae with explicitly synthetic generic equipment inputs plus structured trait sources; they are **not a source-authentic Flashonder gear fixture**.

Developer Stat Audit now shows the actual decoded 1449 type/source/target/percent fields, so a remaining mismatch is inspectable instead of only a generic label.

## 6. Item 4633 result

[ArenaNet `/v2/items/4633`](https://api.guildwars2.com/v2/items/4633) returned HTTP 404 with `no such id`. A batch containing 4633 and 30703 returned Sunrise only. Thus no public item metadata, selected stats or verified Defense exists for 4633 in this check. **121 is not installed as a fallback.** The test keeps 4633's attributes and Defense unresolved.

Targeted repair retries missing item metadata and the authenticated full equipment/selected template. The latter can reveal whether a stale cached shoulder identity differs from the authoritative current record. This has not been verified against Flashonder's real account.

A real shoulder fixture, [Zintl Shoulderguard 48197](https://api.guildwars2.com/v2/items/48197), verifies actual decoded Defense **102**, fixed infix attributes and correct Armor contribution. It is deliberately not substituted for item 4633 or claimed to close Flashonder's gap.

## 7. Sunrise selected-stat result

[Public Sunrise metadata 30703](https://api.guildwars2.com/v2/items/30703) is available: Greatsword, zero Defense, `attribute_adjustment=717.024`, multiple stat choices, and no account-instance selection. It cannot determine Flashonder's prefix.

Repair now checks `/characters/{name}/equipment?v=2021-07-15T13:00:00.000Z`, then the **specific equipment tab** if unresolved. The known version supports Legendary Armory records; no new armory-wide account call is necessary. This follows the documented [equipment schema](https://wiki.guildwars2.com/wiki/API:2/characters/:id/equipment) and [per-tab response](https://wiki.guildwars2.com/wiki/API:2/characters/:id/equipmenttabs).

Before Codable conversion, diagnostics retain only endpoint kind, item ID, slot, tab, raw stats-object presence, selected stat ID and attribute keys. No raw authenticated body, attribute values, headers, URL, character-bound metadata or API key is retained by that diagnostic.

Fixed paths:

- Hydration formerly rejected an authenticated selected ID with no attributes. It now retains that ID, allowing selected-prefix itemstats reconstruction.
- A malformed/evolving attribute object no longer discards the legendary slot/selected ID; its attributes stay unresolved until independently reconstructable from that selected ID.
- A specific refreshed template can correct item identity, upgrades, location and selection. A missing fresh legendary selection is never populated from a historic cached prefix. Only the current authenticated full response can hydrate it.
- Controlled authenticated Sunrise DTO/tab fixtures prove selected stats survive repair and snapshot persistence. The 161 fixture's 251/179/179 values are fixture-specific, **not Flashonder's selected prefix**.

If both real authenticated endpoints omit selection, Sunrise remains unresolved. No attempt was made to obtain an API key from the user or fabricate a physical-account response.

## 8. Remaining deterministic sources and repair UX

For the provided recording: shoulder 4633 metadata/attributes/Defense and Sunrise's authenticated selected stats remain account-specific unresolved sources. A 1449 mismatch requires the actual device payload/targeted retry; current public facts are verified. Birthday Enrichment still contributes no invented attributes. [Deep Strikes 1343](https://api.guildwars2.com/v2/traits/1343) remains explicitly conditional/excluded (Fury/bleeding-target effects), not an unexplained always-on deterministic gap.

Resolve Missing Stat Sources now shows individual source rows as `checking…`, then `resolved`, `still unavailable`, `unsupported/conditional`, or replaced-by-refreshed-template. Rows update after each stage; successful sources do not wait for all other requests. The audit recomputes immediately from published repaired inputs. Cached-account freshness is untouched; no account/Inventory/Wallet-wide refresh is added. Errors and unresolved sources remain visible.

## 9. New Flashonder calculated values: evidence limit

There is **no authenticated Flashonder equipment/build dataset** in the supplied attachment or repository JSON. Consequently no actual after-repair Flashonder totals can be reported or promoted into a source-authentic regression fixture.

The following is a **conditional arithmetic projection only**: keep every recorded equipment input unchanged and successfully resolve selected 1449's verified conversions at recorded Power 1828. `floor(1828×0.10)=182`. It is not a measured repaired account result.

## 10. Comparison against observed values

| Stat | Recorded calculation | GF-only conditional projection | Observed |
| --- | ---: | ---: | ---: |
| Power | 1828 | 1828 | 1873 |
| Precision | 1116 | 1116 | 1170 |
| Toughness | 1836 | 1836 | 1868 |
| Vitality | 1832 | 2014 | 2051 |
| Ferocity | 73 | 255 | 260 |
| Condition Damage | 73 | 73 | 73 |
| Expertise / Concentration | 49 / 49 | unchanged | 49 / 49 |
| Healing Power | 133 | 133 | 133 |
| Defense | 1138 | 1138 | 1259 implied |
| Armor | 2974 | 2974 | 3127 |
| Health | 27532 | 29352 | 29722 |
| Critical Chance | 15.52% | 15.5238…% | 18.09% |
| Critical Damage | 154.87% | 167% | 167.3% |
| Boon / Condition Duration | 3.27% / 3.27% | unchanged | 3.26% / 3.26% |

Equipment still must defensibly supply +45 Power, +54 Precision, +32 Toughness and +32 pre-conversion Vitality. At final Power 1873, conversion rises from 182 to 187, explaining the other five Vitality/Ferocity points. Defense's diagnostic missing 121 plus Toughness +32 would close Armor's 153 gap **only if real sources verify those values**. Already-correct attributes, duration, Health and crit formulae are unchanged; no discrepancy is fitted in production.

## 11. Trading Post root causes and fix

The sheet called `TradingPostPriceResolver` with its default `loading=false`, before/during async metadata and price loading. Nil price therefore rendered unavailable. It also consumed a global price error, allowing unrelated requests to influence a detail. The resolver prioritized loading/error above a cached price and discarded its presentation.

A real HTTP-failure regression found a second cause: `fetchCommerceBatch` caught **all** single-item failures and fabricated a fresh zero-price result. HTTP 500, timeout and decode errors were indistinguishable from completed no-listing responses and could overwrite cached prices.

Repair:

- Explicit initial/in-flight state: `Checking Trading Post…` with a progress indicator and known metadata retained.
- Per-item request phase/error and revision gating; old/other-item results cannot overwrite a newer detail state.
- Cached price remains visible as Last known price / Refreshing… during refresh. Failure preserves it and displays the saved-price/error explanation.
- Available, no listings, bound/not tradable, genuine completed unavailable and failed requests are separate outcomes.
- Only HTTP 404 permits the unavailable/no-listing fallback; network/server/decode failures never become fabricated zero listings. Detail refresh opts into reporting errors even when the API cache has a fallback. Other API callers retain the existing quiet cached-fallback option.

## 12. Verification

Final result: **262 unit tests pass** (17 added beyond the 245-test baseline), **six targeted iPad UI tests pass**, and **arm64 Release compilation passes**. Five iPhone map/price UI tests passed before the final API HTTP-failure repair; that repair is covered by the final unit suite. `git diff --check` is clean.

An intermediate new HTTP 500 test failed and exposed the catch-all fallback described above; that code was repaired and the complete suite rerun successfully. This failure is not concealed as a successful first run.

Logs are under `/tmp/gw2-handoff-final.log` (final units), `/tmp/gw2-handoff-complete.log` (units + iPad UI), `/tmp/gw2-handoff-phone.log`, and `/tmp/gw2-handoff-release-verified.log`. New cases cover visible completeness, opaque retention, native fallback, prefetch independence, stale/cancelled frames, interrupted crossfades, continuous transforms, payload evolution, selected 1449 gating, conversion flooring, unchanged derived formulae, real shoulder metadata, missing 4633, authenticated Sunrise repair/persistence/no guessing, source-level statuses, TP loading/cached/available/no-listing/bound/error outcomes, HTTP 404/500 and cached failure preservation. Two exported rapid-gesture screenshots were also visually checked: retained artwork fills the map without rectangular holes.

No physical device run or full unrelated UI suite is claimed. Legendary production code was not touched. The existing iPad Legendary layout check was included; the prior phone-only Legendary UI failure and Wallet timeout were not retested or changed in this scoped phase.

## 13. Minimal physical retest

1. Kessex, Detailed: start with painted artwork, pinch outward through source 6→5→4 while panning, then reverse quickly. Repeat with slow networking. Confirm no loading rectangles/checkerboards; briefly blurrier retained artwork is acceptable. A truly cold/offline start without cached artwork cannot manufacture map images.
2. Flashonder, same terrestrial template/set A, unscaled/out of combat: tap Resolve Missing Stat Sources. Capture per-source results, decoded 1449 structural facts, raw DTO shape rows for Shoulders/Sunrise, and the new calculated/observed totals. **Do not include an API key.** If 4633 remains absent or Sunrise's selection is absent, keep them unresolved; the sanitized evidence is needed to finish source-authentic totals.
3. Open a TP detail with no cached price: it must say Checking Trading Post…, then show its completed outcome. Reopen with a stale cached price and slow/offline networking: Last known price must remain visible during refresh and on failure.
