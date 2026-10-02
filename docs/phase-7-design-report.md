# Phase 7 — UI/UX redesign and product polish

The design centers on “Your second screen for Tyria” and the account → action → live map loop. Changes are limited to app presentation, reusable UI components, Debug review fixtures, and UI tests. Existing domain and unit-test source files, bridge protocol, map camera/projection/tile internals, scoring, stat formulas, account isolation, provenance and production endpoints remain unchanged. The pre-existing untracked `.gitignore` and signing settings are preserved; no commit was created.

## Design report

| # | Area | Before → after and reason |
|---|---|---|
| 1 | Direction | Repeated outlined cards → charcoal surfaces, clear type, compact rows and selective orange actions. Content and the next action lead. Dark is the initial preference; light/system remain available. |
| 2 | Design system | Expanded [GWDesignSystem.swift](/Users/adrianro/Desktop/finance-blockchain/Gw2_secondscreen/ios/GW2Companion/Sources/DesignSystem/GWDesignSystem.swift): adaptive palette, typography/spacing tokens, plain/subtle surfaces, compact badges, primary/selection button styles, search, progress summary, freshness, loading rows and a Debug UI Gallery. Existing image cache and coin components are reused. |
| 3 | Navigation | Kept the five iPhone tabs and seven iPad sidebar destinations. Added compact sidebar account/live identity and active-goal count. Map inspector starts hidden and restores on demand. |
| 4 | Today | Multiple status/planning cards → greeting, daily/weekly summary, acclaim, claim readiness, one session action, Quick Wins and daily/weekly disclosures. Wide layouts separate the summary from the checklist. |
| 5 | Map | Permanent controls/panels → compact map-name/live HUD, contextual control menu, Layers detail picker and on-demand navigator. Empty-map tap preserves immersive chrome hiding; target and restore buttons remain available. Distance labels use meters through a presentation helper, without changing navigation calculations. |
| 6 | Characters | Dense roster details → portrait/profession/level/live/playtime rows and one profile with Equipment, Build, Inventory and Stats. Wide layouts keep roster and profile side by side. |
| 7 | Equipment | Equipment and stat audit competing for attention → icon-led item rows, restrained rarity treatment and neutral equipment-tab selection. Item taps retain the shared detail sheet. |
| 8 | Builds | Tier-only trait labels → selected trait names in order, compact build tabs and a scrolling skill bar. Metadata icons remain game icons when available. |
| 9 | Stats | Always-visible development audit → estimated static attributes and combat stats, unavailable-source warning, calculation disclosure and per-stat source detail. Raw audit fields require Debug plus Developer Mode. Selected equipment tabs continue to use the existing stat engine. |
| 10 | Inventory | Heavy tab/filter treatment → consistent all-inventory search, compact location choices, optional price menu, owned totals and three location previews. Wide layouts use a location column; Bank/Shared retain indexed slot grids. Full row touch areas open item details reliably. |
| 11 | Item details | Context-specific quantity presentation → shared ownership total and all locations, readable item types, Sell now/Buy now/Estimated stack and active-goal relationships. Checking prices and unavailable prices are distinct; absent sections stay absent. |
| 12 | Wallet | Repeated wallet cards and inline pin controls → compact currency rows, pinned overview, search, a 44-point full-wallet disclosure and contextual pinning. The account overview uses a stable stack to prevent layout oscillation when that disclosure changes height. Existing balances, pinning and coin arithmetic are unchanged. |
| 13 | Goals | Engine-oriented summaries → progress plus next major requirement. Add Goal choices explain Legendary, Craft, Achievement and Custom. Suggested actions disclose their reasons; numerical ranking stays in developer presentation. |
| 14 | Legendary | Nested boxed tree → one hero, major progress, restrained tradable/account-bound summary, one next-action button and compact requirement disclosures. Standard OWNED/READY/BUY/CRAFT/EARN/ACCOUNT-BOUND/MANUAL labels replace internal terminology. Owned legendaries initially show ownership and View Full Plan. |
| 15 | Sessions | Setup/algorithm details ahead of tasks → numbered itinerary and prominent Start Session, focus disclosure and completed/skipped disclosure. Wide layouts put preferences beside the itinerary. Candidate counts and score breakdowns require Developer Mode. |
| 16 | Account/Settings | Equal-weight identity/status cards → account summary and lower account-access disclosure. Settings group Account, PC, Map, Planning, Appearance, Data, Privacy, Help and About. Developer/QA/calibration/simulation controls are unavailable in Release even with a saved developer preference. |
| 17 | Onboarding | More conceptual steps and technical copy → three pages: second screen, account, gaming PC. Privacy opens separately; account and PC setup retain existing behavior. |
| 18 | States | Large spinners and repeated stale warnings → static skeleton rows, compact saved-data freshness and severity-aware error treatment. Useful cached content stays usable. |
| 19 | Accessibility | Added combined progress/ownership labels, non-color status symbols/text, 44-point custom control targets, monospaced values and a menu alternative to character section buttons at accessibility text sizes. New panel/disclosure transitions honor Reduce Motion. Dynamic Type uses system text styles. |
| 20 | iPad | Available-width thresholds enable Today summary/checklist, roster/profile, goal list/detail, inventory locations/content and session preferences/itinerary. Map inspector opens only when useful; narrow widths fall back to navigation or sheets. |
| 21 | iPhone | Existing tab structure remains. Character detail uses a navigation stack; item/planning detail uses sheets; inventory locations scroll horizontally and map navigator uses a sheet. |
| 22 | Performance | Retained inventory lazy lists/grids, price batching and image caching. The small account overview uses a stable stack for reliable disclosure layout. Skeletons are static; no new continuously animated/blurred card system. Geometry is used at screen layout boundaries. Map camera, raster retention and tile-source implementation were not edited. |
| 23 | Validation | See the verified results below. Baseline: 276 unit tests passed before UI work. |
| 24 | Physical review | All screens still need real account/game-icon review. Prioritize iPad window resizing, live map overlays during a long session, character/equipment switching, large Materials inventories, wallet, pairing/onboarding, accessibility text sizes/VoiceOver and light/high-contrast appearance. Fixture screenshots verify layout, not live game correctness. |
| 25 | Walkthrough | Open Today and claim an actual in-game reward; plan/start a session; navigate with a physical Windows bridge; hide/restore map chrome and use Layers/Navigator; inspect current character equipment/build/stats; search an item across Bank/Materials/Shared and open its goal relationship; expand Twilight and add its next action to a session; check pinned wallet and offline cache; rotate/resize iPad and repeat with large text and Reduce Motion. Keep it open through a full play session. |

## Validation and visual review

Screenshot assets remain temporary under `/tmp/gw2-phase7-design-review`; no large images are added to the repository. The [screenshot index](/tmp/gw2-phase7-design-review/README.md) includes the required iPad landscape and iPhone screens, plus builds, stats, item details, active session, wallet, settings and onboarding.

The visual pass is separate from test assertions. It led to moving Start Session above the itinerary, reducing Legendary row height so all four major requirements are discoverable sooner, using width-based columns on the 11-inch iPad, strengthening inventory hit areas, giving map disclosures a readable overlay surface, and preventing character section labels from wrapping on iPhone. Simulator review uses Debug-only fixtures through the existing store/provider interfaces. Production behavior uses the original providers.

The final unit suite passed all 276 tests, matching the baseline. The complete final iPhone Debug UI suite passed all 14 tests, including existing map/camera, Wallet and price-race regressions. All three final iPad product tests passed. UI validation exposed and fixed the iPhone Wallet layout loop; expansion/collapse now updates immediately. The iPad 13-inch Release developer-gate test passed with a saved developer preference and the developer launch argument: Gallery, QA, Calibration, simulation and pairing developer controls stayed hidden. Production Release builds use normal testability settings; the separate Release test build enabled testability only to compile the unit-test target's existing `@testable` imports.

| Build matrix | Result | Evidence |
|---|---|---|
| iPhone 17 Pro · Debug | Passed build and tests | [Build/test log](/tmp/gw2-phase7-wallet-layout-fix-tests.log) |
| iPhone 17 Pro · Release | Passed production build | [Build log](/tmp/gw2-phase7-wallet-fix-iphone-release.log) |
| iPad Pro 11-inch (M5) · Debug | Passed build and tests | [Build log](/tmp/gw2-phase7-verified-ipad11-debug-build.log) |
| iPad Pro 13-inch (M5) · Release | Passed production build | [Build log](/tmp/gw2-phase7-wallet-fix-ipad13-release.log) |

| Verification | Result | Evidence |
|---|---|---|
| Baseline unit suite | 276 passed, zero failures | [Baseline log](/tmp/gw2-phase7-baseline.log) |
| Final full unit suite | 276 passed, zero failures · 17.2 seconds | [Final iPhone log](/tmp/gw2-phase7-verified-iphone-tests.log) |
| Final full iPhone UI suite | 14 passed, zero failures · 373.3 seconds | [Final iPhone result](/tmp/gw2-phase7-verified-iphone.xcresult) |
| Final iPad product UI suite | 3 passed, zero failures · 130.3 seconds | [Final iPad log](/tmp/gw2-phase7-verified-ipad-tests.log) |
| Release developer gate | 1 passed, zero failures · 23.3 seconds | [Release test log](/tmp/gw2-phase7-release-gate-final.log) |
| Whitespace validation | `git diff --check` passed | Final worktree check |

Forty temporary screenshots cover both device layouts. Final captures were reviewed for hierarchy, map dominance, label wrapping, disclosure density and primary-action placement. They use fixture data and do not establish real-game data fidelity or physical-device performance.

Builds use Xcode 26.4 / iOS 26.4 simulators, with command-line code signing disabled. Repository signing settings were not edited. Build logs include the App Intents metadata notice (also present in the baseline) and a Release-only unreachable Debug fixture branch warning; neither failed the build.

No physical-device FPS/energy measurement or real ArenaNet/Windows session was performed during this phase. That acceptance remains the walkthrough above.
