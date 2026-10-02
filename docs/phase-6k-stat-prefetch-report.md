# Phase 6K — offline stat closure and earlier map prefetch

Date: 2026-10-02. Scope: the supplied Phase 6K brief and `ScreenRecording_10-02-2026 13-55-25_1.MP4`. No new features, screen redesign, camera/projection rewrite, or Trading Post implementation changes.

## 1. Map thresholds before and after

Before: adjacent source generation started with the visible source request at the existing ±0.65 camera/source threshold; only the same-source viewport border was warmed afterward.

After: direction-aware adjacent Detailed prefetch starts at ±0.10. For current source z5, outward intent prepares z4 at camera 4.90; inward intent prepares z6 at 5.10. Integer source selection remains unchanged: z5 → z4 below 4.35; z5 → z6 at/above 5.65. Visual promotion still requires the entire visible frame to be complete. Preparing a source never installs a visual frame or changes the camera.

Direction needs 0.04 levels of initial movement; reversal needs 0.08 levels from the directional extremum. The chosen adjacent level is latched through threshold jitter, cleared on reversal/source change, and limited to useful Detailed levels 4–6. Projected coverage is warmed at the promotion boundary, including the expanded outward viewport. Same-level border warming is independently cancelled at pinch start, leaving the speculative lane for adjacent-source work.

Existing limits remain: two concurrent parent jobs shared with visible loading, six native-source workers, two generation/root workers, 96 parents / 3,072 cold leaves, existing memory/disk caches. Speculation is further limited to one parent at a time globally. It never queues in front of foreground work: busy permits or excessive tile budgets drop speculation. Reversal/view task cancellation stops remaining parents. Slow/failing speculative tiles cannot replace retained artwork.

## 2. Simulated soft interval

The timing regression uses the actual frame/prefetch scheduling methods with an injected cache: one z4 parent, 450 ms cold generation latency, and 550 ms lead time (4.90 → 4.35 at one camera-level/second). The full two-source viewport and real ArenaNet transport are not represented by this fixture.

Final unit run: cold post-threshold wait **453.01 ms**, early-prefetched **0.074 ms**. Both results were complete frames. This demonstrates the cache-warming benefit in simulation, not a measured physical-device sharpness improvement. Whole-view cold generation, pan/anchor movement, contention and faster gestures may reduce that benefit. The physical recording must be repeated to validate the perceptual result.

## 3. Great Fortitude mismatch cause

The recording confirms Strength specialization 4 and selected major IDs 1444, 1449, 1437. Selection was not the problem. The previous engine required a decoded `TraitMetadata` and two matching `BuffConversion` facts before executing the already-curated rule. The coverage audit independently compared two expected rules against the matching decoded fact count and emitted “static rule/API facts mismatch.” Missing/incomplete cached facts therefore disabled a known rule during an outage.

The recording does not expose the device's decoded facts, so it does **not** prove which cached fact was missing or malformed. The precise field-level defect in that device cache remains unknown; the runtime overdependency and its reproducible failure path are established. A public recheck of [ArenaNet trait 1449](https://api.guildwars2.com/v2/traits/1449) returned Strength 4 and Power → Vitality/CritDamage, both 10%.

## 4. Offline rule architecture

Catalog `pve-2026-10-02-v4` separates fact matching/validation from ID-keyed runtime adjustments and conversions. Known rules execute without trait metadata. Great Fortitude additionally requires Strength 4 and selected major 1449. Verified Strength minor identities allow Pinnacle of Strength's unconditional +5% critical chance offline; its Might-dependent Power fact remains excluded. Other shipped safe rules and ID-keyed rune rules also execute offline.

Missing/incomplete facts or fingerprint differences produce “API metadata differs from verified catalog; local rule applied,” not a missing deterministic source. Relevant positive contradictions suppress the whole affected rule and are visibly flagged for metadata refresh: changed conversion source/percentage, changed flat value, conversion ↔ flat-adjustment replacement on an expected target, or contradictory Strength specialization identity. For Great Fortitude, a complete two-conversion same-source replacement with an expected target missing and a different target present also signals a target change. A lone unrelated fact is insufficient evidence; extra facts cannot invalidate an intact expected pair. Ordering, localized descriptions, icons, duplicates and unrelated targets are ignored. The Percent-only Pinnacle rule blocks a sole explicit changed percentage, not unrelated Might facts.

Regression arithmetic, using synthetic—not reconstructed Flashonder—equipment: pre-conversion Power 1873 → +187 Vitality and +187 Ferocity; Ferocity 73 → 260; critical damage 167.3333%. The recording's unresolved equipment had Power 1828; the app must use its actual available Power, never force the fixture's 1873.

## 5. Was Sunrise lost in persistence?

No encoder/decoder loss was found: authenticated `stats.id` and `stats.attributes` already survived DTO conversion and snapshot round trips. Two refresh paths could erase them before the next snapshot: normal equipment-tab replacement and explicit targeted-tab replacement with a poorer same-item DTO. Both are now covered by regression tests.

This establishes a real loss path, not proof that this particular Sunrise had ever received a successful selected-stat payload on the physical device. If no saved selected ID/attributes exist, the prefix remains unavailable; no generic legendary/default prefix is substituted.

## 6. Persistence fix

Merge within one character's stored details, matching equipment tab + slot + item ID. New non-null fields win; absent selected stats retain richer prior selections and attributes. Nested fields follow the same rule: fresh attributes take precedence even when an omitted selected ID must remain cached. Retained selections persist `stats_are_cached`, display cached provenance in the source audit, and keep account detail/domain freshness cached without advancing the saved timestamp. Fresh authenticated full-equipment data can replace those cached selections. Targeted full-equipment repair retains its proven tab association when publishing to inactive templates, so repaired selections survive publication and restart without borrowing the active template's prefix.

A different item never inherits prior stats or upgrades. A different explicit selected-prefix ID invalidates prior attributes even if new attributes are missing. Other tabs, slots and characters cannot donate selections. Removed slots are not resurrected. Empty upgrade arrays clear old upgrades, unlike absent arrays. The new optional provenance key is backward-compatible with existing snapshots.

Verified public item/defense metadata remains in the stored detail and survives failed network refresh and restart. The 121-defense test value is supplied only by a synthetic metadata fixture, never inferred or hard-coded into production.

## 7. Remaining network-dependent sources and status

The recorded shoulders item 4633 remains without metadata/defense; a public recheck returned HTTP 404. This is not evidence for inserting the observed 121 gap. Once authoritative metadata arrives, targeted repair and snapshot persistence can retain it through outages. Sunrise 30703 still requires authenticated selected stats if none were ever saved. Unsupported/missing upgrade or infusion attributes remain unresolved, including the recording's Birthday Enrichment 93953. No stat contributions were fabricated.

The existing stat card/source sheet now partition counts into Local rules, Account data, Public metadata, and Network required. Missing deterministic source rows explicitly say “Requires ArenaNet metadata refresh.” Conditional combat effects remain separately excluded; known offline rules do not appear as missing merely because ArenaNet is unavailable.

## 8. Verification

All selected verification passed:

- **276 unit tests, 0 failures** — including 14 added tests. Final run includes the duplicate-irrelevant-fact safeguard and all persistence changes.
- **6 iPad UI tests, 0 failures** — two continuous-map regressions, three existing price regressions, and the existing compact legendary layout regression.
- **5 phone UI tests, 0 failures** — two continuous-map regressions and three existing price regressions.
- **Release arm64 simulator build succeeded** on final sources; `git diff --check` clean. No Trading Post production files changed.

Unit coverage includes offline Great Fortitude, incomplete/irrelevant/duplicate facts, mechanical contradictions, offline automatic minor identities, selected-stat snapshot/restart/outage retention, normal and targeted poorer refreshes, inactive-template publication/persistence, item/prefix/tab/slot/character invalidation, nested non-null field precedence, network copy and count partitioning, unchanged promotion thresholds, reversal cancellation, cold-work limits, shared parent concurrency and timed cache warming. UI handoff stress remains deterministic and does not issue speculative real-network requests under its synthetic fixture. These are selected UI regressions, not a claim that every UI test was run.

Evidence retained locally:

- Unit suite/timing: `/tmp/gw2-phase6k-final-unit.log`.
- iPad UI/full preceding unit run: `/tmp/gw2-phase6k-complete.log`.
- Phone UI: `/tmp/gw2-phase6k-complete-phone.log`.
- Final Release: `/tmp/gw2-phase6k-final-release.log`.

The iPad is the 11-inch M5 simulator; the phone is the iPhone 17e simulator. All test runs used `CODE_SIGNING_ALLOWED=NO`. The final fingerprint-only duplicate-fact refinement was followed by a full unit rerun and Release rebuild; map/UI implementation was unchanged from the successful device-size UI runs. Existing user-owned `.gitignore` was left untouched. Changes are uncommitted.

## 9. Minimal physical retest

1. Detailed map: repeat slow outward/inward pinch and a quick reversal on the recorded map. Confirm no black rectangles, seams or snapping; compare the soft interval with the old recording. Include a fast pinch and a cold-cache run.
2. Stats offline: with cached Strength 4 and major 1449 selected, confirm local Great Fortitude contributes `floor(actual pre-conversion Power × 0.10)` to Vitality and Ferocity. Confirm missing network rows remain explicit and the four source counts are visible.
3. Stats online: resolve shoulders/Sunrise using the device's existing account authorization when ArenaNet supports the requested sources. Confirm the actual selected ID/attributes and returned defense; do not assume 121 or a prefix. Restart, go offline, then perform a partial refresh: same-item selections/verified defense should remain cached. Changing item/prefix/template must not borrow old stats.

No physical-device retest was performed during this implementation. Simulator and synthetic fixture results do not close the remaining live-source checks.
