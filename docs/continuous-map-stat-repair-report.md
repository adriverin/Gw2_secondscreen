# Continuous map zoom and deterministic stat-source repair

Follow-up: [physical recording correctness repair](physical-correctness-repair-report.md) supersedes this report's progressive emergency-fill handoff and account-source status notes.

Implementation report, 2026-10-02; public metadata verified 2026-10-01. No new Legendary content or redesign of Today, Inventory, Wallet, Goals, builds, or account browsing.

## 1. Previous zoom architecture

The live map stored an integer display zoom. A temporary magnification scaled the view during a gesture; releasing it changed the integer by one step and reset magnification. Pinches were centered on the map, not the fingers. Detailed z5/z6 used original z7 tiles; a changed request discarded the previous matching frame. z4 used native artwork.

## 2. Continuous camera architecture

The camera now retains a `Double` zoom after release. Integer raster selection is independent. Camera zoom is clamped to 2…7 in Tyria and 2…6 in the Mists, including continent changes. Tile screen scale is `2^(cameraZoom - tile.zoom)`; every marker, route, player arrow and offscreen indicator shares the continuous continent-to-screen transform. Map calibration and accessibility expose the fractional camera separately from its requested tile level.

## 3. Pinch anchor

At pinch start, store the initial zoom, screen centroid and continent coordinate. During the gesture, calculate `startZoom + log2(scale)` and solve the center so that continent coordinate remains under the live centroid. UIKit supplies the moving two-finger location, not just a fixed start anchor. The last valid centroid is retained when a finger lifts. Single-finger pan is kept separate so it cannot commit a second pinch translation. Northeast anchoring, moving centroids, clamping and fractional release are tested.

## 4. Hysteresis

From source z6, request z7 at camera 6.65 or above and z5 below 5.35. After selecting z7, return to z6 only below 6.35. Requests change at source thresholds or tile-coverage boundaries, not for each fractional pinch frame. A large zoom change can skip several levels safely.

## 5. Layer handoff and crossfade

Retain the complete active frame while replacements load. A frame with missing images or a cancelled request cannot replace it. Complete replacements crossfade over 150 ms, retaining the outgoing frame until completion. Native readiness and Detailed generation run independently: a cold or slow pyramid cannot hold the camera at an obsolete level. Initial native tiles start loading immediately; complete native coverage can hand off before the Detailed frame.

Uncovered areas are filled at the previous source level while waiting. Emergency fill is capped at 96 tiles during an unusually fast multi-level pinch. This avoids an unbounded old-level grid. A cold/offline region without cached native artwork can still have unavailable tiles; this is not a guarantee that unfetched imagery can be displayed. Physical rapid-pinch/network-outage verification remains necessary.

## 6. Detailed z4 strategy

The production provider builds z6 from four official z7 children, z5 from four derived z6 children, and z4 from four derived z5 children. There is no flattened cold 8×8 compositor. Each intermediate is deduplicated and cached in memory and lossless PNG disk storage. The existing upright 2×2 compositor and geographical projection remain unchanged. Cache namespace/projection version is v3, preventing old derived files from being reused with the new strategy.

Cancellation is consumer-aware: one cancelled viewport does not cancel a tile still needed by another. Generation permits are acquired only after children are ready, preventing recursive semaphore deadlock. Native artwork remains the fallback if coverage is incomplete or the budget is exceeded.

## 7. Performance and limits

| Resource | Bound |
| --- | --- |
| Derived memory cache | 32 images / 12 MiB cost cap; 256×256 RGBA tiles normally use 8 MiB at the count cap |
| Derived disk cache | 1,024 PNG files; enough for a 48-parent z4 pyramid's 1,008 nodes |
| Concurrent root parents | 2 |
| Concurrent compositing permits | 2; no permit held during recursive child loads |
| Concurrent z7 source loads | 6 |
| Cold leaf footprint per layer | 3,072 z7 tiles maximum |
| Parent frame | 96 tiles maximum; the leaf budget limits z4 to 48 |
| Prefetch | At most one parent-tile ring at z5/z6; shed it before sacrificing visible detail; no z4 ring |
| Emergency native fill | 96 tiles |

An iPad-class 1024×1366 viewport centered near Kessex needs 35 z4 parents, or 2,240 cold leaf images. Synthetic full-viewport compositor/cache runs measured approximately 2.6–4.0 s cold and 7–10 ms warm on the iPad simulator. A phone-simulator run under concurrent build load took 7.7 s cold and 27 ms warm, showing the sensitivity to host load. The warm runs after derived memory eviction performed **zero** additional source fetches. Fetch concurrency stayed at or below six. These timings exclude real-network latency and do not constitute a physical-device RSS/FPS profile. Rendering and native loading remain independent of this background work.

## 8. Exact missing sources

The recording supplies counts but not the two item IDs, the missing-defense slot, the seven upgrade/infusion IDs, or the selected Strength major IDs. The local iPad simulator snapshot contains fixture characters, not Flashonder. Therefore none of those account-specific identities can honestly be claimed as discovered or repaired here.

The audit now lists every missing source with slot, item name, item ID, selected stats ID and reason. Reasons distinguish missing `equipment.stats`, missing item metadata, missing itemstat metadata, absent defense, unsupported selectable-stat reconstruction and unsupported static rules. Individual upgrades/infusions retain their IDs and names rather than being reduced to a count.

## 9. Melandru

Versioned ID rule **24771** grants cumulative Toughness 25/25/75/75/175/175 for counts 1…6 and Vitality 0/35/35/35/35/35. Only active terrestrial armor counts. The rule works without item-name metadata and is not selected by English name. Incoming condition-duration bonuses never add Expertise or outgoing duration. Verified against [ArenaNet item 24771](https://api.guildwars2.com/v2/items/24771) and the [Melandru reference](https://wiki.guildwars2.com/wiki/Superior_Rune_of_Melandru).

## 10. Strength IDs

Current [ArenaNet Strength metadata](https://api.guildwars2.com/v2/specializations/4) identifies specialization **4**, automatic minors **1446, 1448, 1453**, and Great Fortitude major **1449**. The audit displays the actual active build's selected major IDs. Missing or stale minor metadata is flagged and can be refreshed. Flashonder's actual selected majors were not supplied.

## 11. Great Fortitude selection and conversions

Apply only if the active build explicitly selects trait **1449 within Strength 4**, and both structured 10% Power conversion facts match the curated rule. No selection is inferred from matching totals. [Current trait facts](https://api.guildwars2.com/v2/traits/1449) verify Power → Vitality and Power → Ferocity.

Calculation order is base → selected/fixed equipment → structured upgrades/runes/infusions → deterministic flat traits → conversions → derived stats. Conversions read one immutable pre-conversion attribute snapshot, preventing conversion-on-conversion feedback and dependence on Set iteration order. Each conversion retains the engine's integer floor semantics, covered by a fractional-boundary regression. The recording alone cannot independently distinguish floor from nearest rounding at Power 1873; physical boundary verification is included below.

## 12. Pinnacle of Strength

Strength's automatic minor **1453** contributes **+5 percentage points critical chance** only with the active specialization and verified `Percent: 5` fact. Its `AttributeAdjust Power: 10` is extra Power per Might, not flat Power, and is deliberately excluded. [Current ArenaNet trait payload](https://api.guildwars2.com/v2/traits/1453) supports this distinction. Audit lines separate base 5%, Precision contribution, Pinnacle, other deterministic modifiers, excluded conditional effects and total.

## 13. Defense repair

The targeted action requests only unresolved active armor/shield item metadata and recovers `details.defense`; a test repairs a real public coat's missing 381 Defense. The audit separately displays every active armor/shield slot, including unresolved entries, and total Defense. Aquatic pieces and inactive weapon sets remain excluded. Flashonder's missing **121 Defense** cannot be assigned to a slot/item without his records; it is not fabricated.

## 14. Equipment, upgrades and infusion repair

Developer/QA **Resolve Missing Stat Sources** fetches unresolved supporting IDs at high priority. It can hydrate missing attributes through the selected character's equipment endpoint, then fetch item/itemstats metadata, specialization minors and trait facts as needed. It never refreshes the account, Wallet, inventory or unrelated characters. Each successful stage publishes to the audit immediately and persists its repaired metadata without marking an outage-era account snapshot current.

Selected account attributes stay authoritative. Exact matching infix prefixes or verified `stat_choices` plus `attribute_adjustment` and itemstat coefficients are safe fallbacks. Prefix reconstruction uses ArenaNet's documented rounded `adjustment × multiplier + value` equation, tested against [Zojja's Breastplate](https://api.guildwars2.com/v2/items/48073) and [prefix 161](https://api.guildwars2.com/v2/itemstats/161); see [itemstat formula](https://wiki.guildwars2.com/wiki/API:2/itemstats). Generic defaults never substitute for an unresolved selected prefix. Structured upgrade/infusion attributes share the canonical Ferocity/Expertise/Concentration/Healing Power aliases. No localized bonus-prose parsing is introduced.

## 15. Flashonder comparison

**No measured after-repair Flashonder dataset exists in the supplied files.** The following is only the known six-Melandru contribution projected onto the recording's baseline. It is not an account-source regression fixture and does not assume Great Fortitude or repaired equipment.

| Stat | Recording calculation | With known rune attributes only | Observed |
| --- | ---: | ---: | ---: |
| Power | 1828 | 1828 | 1873 |
| Precision | 1116 | 1116 | 1170 |
| Toughness | 1661 | 1836 | 1868 |
| Vitality | 1797 | 1832 | 2051 |
| Ferocity | 73 | 73 | 260 |
| Condition Damage | 73 | 73 | 73 |
| Expertise / Concentration | 49 / 49 | 49 / 49 | 49 / 49 |
| Healing Power | 133 | 133 | 133 |
| Defense | 1138 | 1138 | 1259 implied |
| Armor | 2799 | 2974 | 3127 |
| Health | 27182 | 27532 | 29722 |
| Critical Chance | 10.52% | 10.52% | 18.09% |
| Critical Damage | 154.87% | 154.87% | 167.3% |
| Boon / outgoing Condition Duration | 3.27% / 3.27% | unchanged | 3.26% / 3.26% |

If verified active Strength metadata is available, Pinnacle adds five points to the calculated critical chance, bringing the baseline-Precision estimate to approximately **15.52%**. Resolving Precision to 1170 yields approximately **18.095%**. If Great Fortitude is actually selected, 1873 resolved Power yields 187 Vitality and Ferocity under the current floor rule; no character-specific fudge is added. Health stays `9212 + Vitality × 10`; critical damage stays `150 + Ferocity / 15`.

## 16. Remaining deterministic gaps

Flashonder still needs his actual selected equipment/build records and supporting metadata to establish identities, real after values and a source-authentic regression fixture. The previous aggregate observed-total fixture was renamed explicitly as an arithmetic-only test; it is not evidence of character-source fidelity. New tests derive values from modeled public item/trait/rune data and controlled source records, not an aggregate coat carrying observed totals.

The UI now reports **Static Stats complete/incomplete** and a resolved/total deterministic-source score independently from account freshness. Remaining sources are kept visible even if ArenaNet is unavailable. Unsupported or mismatching static rules remain gaps, not silently successful repairs.

## 17. Intentionally excluded effects

Food, utilities, boons, live combat state, conditional traits/sigils, conditional relic effects and unstructured profession mechanics remain outside the static total. They are listed separately from repairable missing metadata. Incoming Melandru condition-duration reduction is not outgoing Expertise. No unexplained critical-chance adjustment or character-specific correction is added.

## 18. Verification

The full unit suite passes **245 tests** (20 new tests beyond the 225-test baseline). Three targeted iPad UI tests pass: fractional pinch/release and chrome tap, the existing compact Legendary detail, and price-before-metadata handling. The four iPhone navigation/Inventory/missing-permission/Developer-QA smoke tests pass; fractional pinch and price-before-metadata also pass there. Coverage includes fractional camera/release, northeast and moving anchors, continuous geometry/scale, fractional label fade, source hysteresis, all-or-nothing handoff, stale completion, 150 ms retention, native cold fallback, recursive cache reuse, cancellation/retry, iPad viewport and prefetch budgets, rune counts, terrestrial exclusions, selected trait gating, conversion ordering/flooring, aliases, itemstat reconstruction, old-cache decoding, incomplete Strength minor metadata, and targeted refresh/outage persistence.

Phone-specific smoke tests initially failed on iPad because their helpers require tab bars; the supported iPhone rerun passes. The pre-existing Legendary UI test has one **iPhone failure**: it does not find Gift of Battle immediately after expanding its parent on the narrow viewport. It passes on iPad; no Legendary production code changed. This failed phone check is not hidden or represented as a passing suite. Wallet's previously recorded UI timeout was not rerun or changed in this phase. Release compilation passes, and `git diff --check` is clean. Real-device network, FPS/RSS, Flashonder's selected traits, conversion rounding at a distinguishing boundary, and exact item identities remain unverified.

## 19. Physical retest

1. On iPad in Kessex, enable Developer mode and Detailed. Pinch slowly near the northeast corner; verify the same waypoint stays under the moving finger centroid, the fractional camera remains after release, and player/route/offscreen geometry follows smoothly.
2. Oscillate around camera 6.5 and verify source hysteresis rather than repeated swaps. Zoom z6 → z5 → z4, wait for derived coverage, then revisit z4. Verify geographic labels remain upright, old coverage stays visible and whole replacement layers crossfade without a level snap.
3. Test a cold launch at z4, rapid repeated pinches and panning. Native artwork should remain responsive while Detailed loads. Repeat with slow/offline networking and observe any genuinely unavailable uncached regions; capture footage of edge gaps or stalls. Profile physical FPS and memory while moving between cached and cold regions.
4. Keep Flashonder level 80, terrestrial, unscaled and out of combat. Select the exact equipment template and weapon set shown in the Hero Panel. Open Stat Audit and record its active build IDs and every missing slot/component identity before repair.
5. Tap **Resolve Missing Stat Sources**. Compare the updated score, individual armor/shield defenses and critical-chance breakdown. Confirm no account-wide refresh and no change to cached-account freshness. Capture the remaining-source list if an outage prevents repair.
6. Verify Great Fortitude from selected ID 1449, not from appearance or fitting numbers. For rounding, use a controlled Power value with a 10% fractional result above .5 and compare the trait-on/off Vitality and Ferocity increment.
7. Attach the selected equipment and active build JSON (or complete expanded source-audit screenshots), plus new calculated/observed values. **Do not include an API key.** These are required to finish the authentic Flashonder fixture and exact before/after verification.
