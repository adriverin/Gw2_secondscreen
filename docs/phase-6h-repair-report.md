# Phase 6H repair report

## 1. Derived-map root cause

The source-child coordinate formula was already correct. The old compositor
translated the destination CGContext by 256 and applied a Y scale of -1, then
drew each raw CGImage directly into a child rectangle. That positioned the rows
in top-left order but inverted the **contents of each child**. A northern feature
inside a source image became a southern feature inside that child rectangle.
Solid-color quadrants and a mean image-difference metric cannot detect this.

The new directional regression reproduces the former implementation: its
southern black marker incorrectly appears in the north. The repaired reference
keeps the northern white marker north.

## 2. Chosen live architecture

Live Detailed maps use original z7 images directly: 256 points at z7, 128 at z6,
64 at z5 (before gesture magnification). Existing continent projection, source
coordinates, Mumble movement, and POI positions are unchanged.

The viewport prefetches one source-tile border. The source grid is hard-capped
at 384 images, with six simultaneous fetches and a conservative 48-parent limit.
Original images reuse request deduplication and bounded memory/disk caches;
disk reads now reuse the persisted original image files. Shared requests track
consumers, so cancelling one viewport does not cancel another consumer's tile.

Only a complete grid matching the current request can replace native artwork.
A missing/invalid tile, cancellation, unsupported zoom, or exceeded budget retains
the whole native lower-zoom grid. Changing the viewport immediately makes an old
Detailed frame ineligible. Balanced mode does not enumerate high-zoom sources.

The compositor remains a QA/reference implementation only. It uses a full
factor*256 canvas with explicit upright row placement, followed by one whole-
canvas downsample. Its cache version/directory changed, isolating old bad mosaics.
The Developer A/B screen now displays the actual direct-tile architecture.

## 3. Why horizontal bands appeared

Each successive source row contained independently inverted child imagery.
Terrain at the bottom of one source tile could not continue into the top of the
next tile. This creates apparent horizontal geographical bands even though the
tile indices and marker projection are correct. The previous compositor also
resized individual children rather than resampling one assembled source canvas.

## 4. Continuity tests

`PhaseSixHMapTests` checks directional 2x2 red/green/blue/yellow quadrants,
sixteen uniquely numbered/color-coded 4x4 children, the exact parent-child
formula, and the former context-flip failure. It includes twelve original
ArenaNet Kessex JPG fixtures: parent z6 (87,61), its eastern neighbor (88,61),
and its southern neighbor (87,62).

Every geographic pixel is compared to an independent upright UIKit reference.
Eight-pixel strips on both sides of internal and neighboring horizontal/vertical
seams are checked individually, not averaged. Neighbor golden parents are
independently filtered, like displayed tiles, to avoid confusing cross-parent
resampling-kernel color changes with geography. Shared source-world edges and
128/64-point neighboring screen offsets are tested separately. Tests also check
missing-child rejection, complete-frame publication, limits, and rapid-pan
cancellation followed by a successful new request.

## 5. Equipment input failure and limits of the diagnosis

A captured default `/v2/items` response contains
`"secondary_suffix_item_id": ""`. The old synthesized `Int?` decoder threw for
this optional field. `ItemMetadata` swallowed that error using `try?`, discarding
the **entire details object**, including fixed attributes, defense, stat choices,
and upgrade data. These detail-less items were then cached as resolved and never
requested again. The decoder now tolerates empty/string/integer optional suffix
IDs, and equipment metadata lacking details is re-requested.

The previous engine already used selected `equipment.stats.attributes` when
present. The screen recording alone does **not** prove why Flashonder's selected
attribute dictionaries were absent; there is no authenticated equipment dump in
the request. Missing template attributes now have an additional safe source:
the character equipment endpoint at schema 2021-07-15. Hydration requires a
unique item/slot/tab/prefix match and never overwrites supplied selected values
or transfers another legendary template's prefix. Still-unresolved selectable
items are explicitly reported rather than assigned generic item defaults.

Active inputs now share one resolver with the audit. It excludes aquatic
headgear/weapons, alternate weapon sets, unslotted Armory copies, and duplicate
slot records. The audit offers terrestrial A/B selection because the account API
does not report the live weapon swap. No new stat catalogs were added.

## 6. Per-item audit example

Real public item 48199, Wei Qi's Breastplate:

| Source | Before | After |
| --- | --- | --- |
| Default item details | discarded | decoded |
| Fixed infix | +0 | FALLBACK: Power +101, Toughness +101, Vitality +141 |
| Defense | +0 | USED: +381 |
| Selected attributes, if supplied | authoritative already | USED; infix IGNORED |

Each slot's Developer audit shows item ID/name, record location, stats.id, raw
selected attributes, infix attributes, defense, upgrade/infusion IDs and resolved
names, and USED / IGNORED / FALLBACK / UNRESOLVED explanations.

## 7. Flashonder reconstructed regression totals

This is explicitly a **reconstructed input regression**, not Flashonder's actual
account equipment. The recording supplies aggregate observations, not item-level
records. The test injects those attribute contributions and a defense breakdown
whose total matches the observed Armor minus Toughness; zero attribute records
are deliberate test scaffolding, not proposed game items.

| Attribute | Total |
| --- | ---: |
| Power | 1873 |
| Precision | 1170 |
| Toughness | 1868 |
| Vitality | 2051 |
| Ferocity | 260 |
| Condition Damage | 73 |
| Expertise | 49 |
| Concentration | 49 |
| Healing Power | 133 |

Derived: Armor 3127; Health 29722; Critical Damage 167.3333%; Boon Duration
3.2667%; Condition Duration 3.2667%. Separate representative tests exercise
fixed armor and selected ascended/legendary armor, trinkets, backpack, and weapon
attributes without generic-infix double counting.

## 8. Defense total

Regression defense is **1259**: 1143 from six heavy armor pieces plus a synthetic
116 shield contribution. That split is a test construction, not a claim about
Flashonder's shield or actual armor rarity. The real account sum is shown
explicitly in Stat Audit. Armor = Toughness + active armor/shield Defense.

## 9. Remaining Critical Chance

Precision 1170 yields 5 + 170/21 = **13.095238%**. The observed 18.09% leaves
**4.994762 percentage points**, approximately 5%, unexplained. No modifier is
invented. The audit shows precision baseline, modeled direct build modifier
(currently zero), calculated chance, and the observed remainder. Existing trait
attribute modifiers still enter Precision before this calculation. Flashonder's
actual active build data and game context are required to identify the remainder.
Coverage remains Partial for unresolved equipment, defense, or modifiers.

## 10. Power Difference bug

The old observation restore path formatted numbers with locale grouping, then
parsed them with `Double(...)`, which is not locale-aware. For a dot-grouping
locale, 1873 became the editable string `1.873`, parsed as 1.873; subtraction
1024 - 1.873 = 1022.127 then displayed as **1022**. This reproduces the recording.

Observations now restore without grouping, parse using the current locale, and
reject fractional values for integer attribute rows. Every row uses the same
subtraction helper and stable row identity. Tests cover German, US, and Swiss
locales, derived percentages, and 1024 - 1873 = **-849**. Weapon-set B observations
have a separate persistence key; existing A notes retain their old key.

## 11. Legendary detail hierarchy

Before: goal header + ownership/summary cards + repeated Major Requirements
progress + large parallel account-bound cards.

After: compact left-list fraction; one right-hand hero with icon/name/type,
primary progress, tradable/account-bound/ready counts, estimate, and work button;
then the four compact major rows. Prose, price actions, and children appear only
when expanded. Completed branches stay hidden/collapsed by default with Show
completed available. Owned Legendary labels and the existing dependency logic,
content, and suggested-work engine remain intact.

## 12. Metadata race

Price-detail opening requests item metadata at high priority, then price at high
priority. A valid earlier/cached price may display while metadata loads, but the
header shows a spinner and “Loading item details…” instead of `ITEM 29185`.
Failure shows “Item details unavailable,” not an ID. A delayed-metadata debug
fixture verifies an already available price followed by the resolved Dusk name.
Debug UI fixtures are compiled out of release builds.

## 13. Verification

- iPad Pro 11-inch, iOS 26.4: 225 unit tests passed; two new UI tests passed.
- iPhone 17e, iOS 26.4: all 225 unit tests passed on the latest source.
- Release simulator build passed with debug fixtures compiled out.
- The new UI tests verify exactly one primary progress text, four compact rows,
  collapsed children, expand/collapse, Show completed, and price-before-metadata
  without an ID leak. Existing completed-branch and owned Sunrise tests pass.
- Exported screenshots were visually inspected for hierarchy and loading state.
- Existing iPhone navigation, inventory, and missing-permission smoke tests passed.
  The Developer QA test initially searched downward for a link above the API
  section; correcting its test-only scroll direction made it pass. Wallet
  expansion was visible in its failure recording, but its test searched for a
  standalone StaticText rather than the combined currency-row accessibility
  label. Only the test query was corrected; Wallet production code is unchanged.
  Its rerun still stalled on the simulator's accessibility/event-loop query after
  expansion, so the broader smoke suite is **not fully green**. Final smoke
  status across runs: four passed; Wallet query timeout remains unresolved.
  The stalled rerun was stopped after repeated 30/60-second snapshot waits;
  the initial run already recorded the Wallet test failure.
  This is not treated as a physical Wallet pass or a reason to rewrite Wallet.
- `git diff --check`: passed.
- Physical iPad acceptance is not yet verified.

## 14. Physical retest

1. Build/install the updated app on the same iPad. In Kessex Hills use Developer
   Map Detail Comparison at z6 and z5, then the live map in Detailed mode. Check
   roads/rivers/settlements at every child seam while panning both directions.
   Toggle Balanced, zoom to z7, rapidly pan and pinch, and interrupt networking.
   Detailed must switch only as a complete frame; over-budget views use native.
   Confirm POIs/player remain aligned. Do not adjust telemetry/projection.
2. Open Flashonder's equipment and refresh character details. Select the template
   and terrestrial weapon set matching the level-80 PvE Hero Panel, without
   downscaling or transient effects. In Stat Audit inspect every source, especially
   Wei Qi's coat, selected legendary/trinket attributes, six active runes,
   HelmAquatic IGNORED, and the actual Defense sum. Re-enter observed Power 1873;
   Difference must equal calculated minus 1873, not 1022. Capture unresolved slot
   diagnostics and the active build if any values still differ.
3. Open Twilight. Verify one detail progress indicator, four compact top-level
   rows, expand/collapse, Show completed, work-button navigation, and owned Sunrise
   state. Open Dusk's price with a cold metadata cache/slow connection: loading
   text must precede the name/icon, with no raw ID flash.
4. Sanity-check Today, movement/live character switching, immersive controls,
   Bank/Materials/Shared Inventory/Wallet, equipment/build browsing, Craft Item
   goals, and existing Legendary dependency behavior.
