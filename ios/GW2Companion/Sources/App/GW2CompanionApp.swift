import SwiftUI
import UIKit

@main
struct GW2CompanionApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var telemetry = TelemetryStore()
    @StateObject private var gathering = GatheringStore()
    @StateObject private var overlays = MapOverlayStore()
    @StateObject private var objectives = MapObjectiveStore()
    @StateObject private var account: AccountStore
    @StateObject private var goals: GoalStore
    @StateObject private var sessions: SessionStore
    @StateObject private var today: TodayStore
    @StateObject private var navigation = AppNavigation()
    @StateObject private var qaResults = QAResultStore()
#if DEBUG
    @State private var phaseSixHPriceRace = false
#endif
    private let api: GW2APIClient

    init() {
        if ProcessInfo.processInfo.arguments.contains("--ui-smoke") {
            UserDefaults.standard.set(true, forKey: "onboarding.completed.v1")
            UserDefaults.standard.set(false, forKey: "developer.mode.enabled")
        }
        if ProcessInfo.processInfo.arguments.contains("--developer-mode") {
            UserDefaults.standard.set(true, forKey: "developer.mode.enabled")
        }
        let api = GW2APIClient()
        self.api = api
        _account = StateObject(wrappedValue: AccountStore(api: api))
        _goals = StateObject(wrappedValue: GoalStore(api: api))
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--phase7-preview") {
            _sessions = StateObject(wrappedValue: SessionStore(defaults: UserDefaults(suiteName: "PhaseSevenPreview.\(UUID().uuidString)")!))
            _today = StateObject(wrappedValue: TodayStore(provider: PhaseSevenPreviewProvider(),
                cache: MetadataDiskCache(directory: FileManager.default.temporaryDirectory.appending(path: "PhaseSevenTodayPreview-\(UUID().uuidString)"))))
        } else {
            _sessions = StateObject(wrappedValue: SessionStore())
            _today = StateObject(wrappedValue: TodayStore(provider: api))
        }
#else
        _sessions = StateObject(wrappedValue: SessionStore())
        _today = StateObject(wrappedValue: TodayStore(provider: api))
#endif
    }

    private var todayPermissions: PermissionSet {
#if DEBUG
        if GWPresentation.isDesignReview {
            return PermissionSet((account.tokenInfo?.permissions ?? []) + ["progression", "wallet"])
        }
#endif
        return account.permissions
    }

    var body: some Scene {
        WindowGroup {
            RootNavigationView(api: api)
                .environmentObject(telemetry)
                .environmentObject(gathering)
                .environmentObject(overlays)
                .environmentObject(objectives)
                .environmentObject(account)
                .environmentObject(goals)
                .environmentObject(sessions)
                .environmentObject(today)
                .environmentObject(navigation)
                .environmentObject(qaResults)
                .environmentObject(DeveloperDiagnostics.shared)
                .tint(GWPalette.accent)
                .task {
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--map-handoff-regression") {
                        UserDefaults.standard.set(MapDetailMode.detailed.rawValue, forKey: MapDetailMode.storageKey)
                    }
#endif
                    DeveloperDiagnostics.shared.startNetworkMonitor()
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--simulate-telemetry") {
                        telemetry.startSimulation()
                    } else {
                        telemetry.connectSavedPairing()
                    }
#else
                    telemetry.connectSavedPairing()
#endif
                    await account.restoreCachedState()
                    goals.setAccountScope(account.account?.id)
                    sessions.setAccountScope(account.account?.id)
#if DEBUG
                    let fixtureMode = ProcessInfo.processInfo.arguments.contains("--phase2-fixtures")
                        || ProcessInfo.processInfo.arguments.contains("--phase2-no-inventories")
#else
                    let fixtureMode = false
#endif
                    if fixtureMode {
                        await today.setAccountScope(account.account?.id, permissions: todayPermissions)
                    } else {
                        async let accountRefresh: Void = account.refresh()
                        async let todayRefresh: Void = today.setAccountScope(
                            account.account?.id, permissions: todayPermissions)
                        _ = await (accountRefresh, todayRefresh)
                    }
                    await goals.prepareLegendaries()
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--phase7-preview"),
                       !goals.activeGoals.contains(where: { $0.type == .legendary(itemID: 30704) }) {
                        goals.addLegendaryGoal(itemID: 30704, name: "Twilight", priority: .normal)
                    }
#endif
#if DEBUG
                    phaseSixHPriceRace = ProcessInfo.processInfo.arguments.contains("--phase6h-price-race")
                        || ProcessInfo.processInfo.arguments.contains("--tp-loading-regression")
#endif
                    await sessions.prepare(recipes: goals.recipes, prices: goals.marketPrices)
                }
#if DEBUG
                .sheet(isPresented: $phaseSixHPriceRace) {
                    TradingPostPriceSheet(item: ItemPlaceholder.metadata(id: 29185), quantity: 1)
                        .environmentObject(goals)
                }
#endif
                .onChange(of: telemetry.latest?.character?.name, initial: true) { _, name in
                    account.updateLiveCharacter(name: name)
                }
                .onChange(of: account.account?.id) { _, id in
                    goals.setAccountScope(id)
                    sessions.setAccountScope(id)
                    Task { await today.setAccountScope(id, permissions: todayPermissions) }
                }
                .onChange(of: account.tokenInfo?.permissions) { _, _ in
                    Task { await today.setAccountScope(account.account?.id, permissions: todayPermissions) }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    MapIconStore.shared.handleMemoryPressure()
                    Task { await MapTileImageCache.shared.handleMemoryPressure() }
                    Task { await DerivedDetailedTileProvider.shared.handleMemoryPressure() }
                    Task { await RemoteImagePipeline.shared.handleMemoryPressure() }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            telemetry.setAppActive(phase == .active)
            if phase == .active {
                Task {
                    await account.refreshGoalAccountData()
                    await today.refreshIfNeeded()
                }
            }
        }
    }
}

private struct RootNavigationView: View {
    let api: GW2APIClient
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var navigation: AppNavigation
    @AppStorage("onboarding.completed.v1") private var onboardingCompleted = false
    @AppStorage("appearance.theme") private var appearance = GWAppearance.dark.rawValue
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var goals: GoalStore

    var body: some View {
        Group {
        if horizontalSizeClass == .regular {
            NavigationSplitView(columnVisibility: splitVisibilityBinding) {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: GWSpacing.small) {
                            Text("GW2 Companion").font(.headline)
                            Text(account.account?.name ?? "Your second screen for Tyria")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if let character = account.currentCharacter {
                                HStack { GWBadge(text: "LIVE", color: GWPalette.success, symbol: "circle.fill"); Text(character.name).font(.caption).lineLimit(1) }
                            }
                        }.padding(.vertical, GWSpacing.small)
                    }.listRowBackground(Color.clear)
                    ForEach(AppTab.iPadSidebar) { tab in
                        Button {
                            navigation.show(tab)
                        } label: {
                            HStack {
                                Label(tab.title, systemImage: tab.symbol)
                                Spacer()
                                if tab == .goals && !goals.activeGoals.isEmpty {
                                    Text(goals.activeGoals.count.formatted()).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sidebar.\(tab.title.lowercased())")
                        .listRowBackground(navigation.selectedTab == tab ? GWPalette.accent.opacity(0.16) : Color.clear)
                    }
                }
                .navigationTitle("")
                .scrollContentBackground(.hidden)
                .background(GWPalette.secondaryBackground)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 250)
            } detail: {
                content(for: navigation.selectedTab)
            }
        } else {
            TabView(selection: phoneTabBinding) {
                content(for: .session)
                    .tabItem { Label(AppTab.session.title, systemImage: AppTab.session.symbol) }
                    .tag(PhoneRootTab.session)
                content(for: .map)
                    .tabItem { Label(AppTab.map.title, systemImage: AppTab.map.symbol) }
                    .tag(PhoneRootTab.map)
                content(for: .goals)
                    .tabItem { Label(AppTab.goals.title, systemImage: AppTab.goals.symbol) }
                    .tag(PhoneRootTab.goals)
                content(for: .inventory)
                    .tabItem { Label(AppTab.inventory.title, systemImage: AppTab.inventory.symbol) }
                    .tag(PhoneRootTab.inventory)
                    .accessibilityIdentifier("tab.inventory")
                moreNavigation
                    .tabItem { Label("More", systemImage: "ellipsis") }
                    .tag(PhoneRootTab.more)
            }
            .toolbar(navigation.sidebarHidden && navigation.selectedTab == .map ? .hidden : .automatic, for: .tabBar)
        }
        }
        .preferredColorScheme((GWAppearance(rawValue: appearance) ?? .dark).colorScheme)
        .background(GWPalette.background)
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingCompleted },
            set: { if !$0 { onboardingCompleted = true } }
        )) { OnboardingFlow() }
    }

    private var splitVisibilityBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { navigation.splitColumnVisibility },
            set: { navigation.splitColumnVisibility = $0 })
    }

    private var phoneTabBinding: Binding<PhoneRootTab> {
        Binding(
            get: { navigation.phoneRootTab },
            set: { navigation.phoneRootTab = $0 })
    }

    private var moreNavigation: some View {
        Group {
            if navigation.moreShowsList || !AppTab.iPhoneMore.contains(navigation.selectedTab) {
                NavigationStack {
                    List {
                        ForEach(AppTab.iPhoneMore) { tab in
                            Button {
                                navigation.show(tab)
                            } label: {
                                Label(tab.title, systemImage: tab.symbol)
                            }
                            .accessibilityIdentifier("more.\(tab.title.lowercased())")
                        }
                    }
                    .navigationTitle("More")
                }
            } else {
                content(for: navigation.selectedTab)
            }
        }
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .map: LiveMapView(api: api)
        case .goals: GoalsView()
        case .session: TodayDashboardView()
        case .characters: CharactersView()
        case .inventory: InventoryView()
        case .account: AccountView()
        case .settings: SettingsView()
        }
    }
}

#if DEBUG
/// Deterministic design-review data enters through the existing provider and merge pipeline.
/// No preview data or launch flag is present in Release.
private struct PhaseSevenPreviewProvider: TodayDataProvider {
    func wizardVaultSeason(language: String) async throws -> WizardVaultSeason {
        WizardVaultSeason(title: "Design review", start: "2026-01-01", end: "2027-01-01", listings: [], objectives: [])
    }
    func wizardVaultObjectives(ids: [Int], language: String) async throws -> [WizardVaultObjectiveMetadata] { [] }
    func wizardVaultListings(ids: [Int], language: String) async throws -> [WizardVaultListingMetadata] { [] }
    func worldBossIDs() async throws -> [String] { ["shadow_behemoth"] }
    func mapChestIDs() async throws -> [String] { [] }
    func dailyCraftingIDs() async throws -> [String] { ["lump_of_mithrilium"] }
    func raids(language: String) async throws -> [RaidDefinition] { [] }
    func dungeons(language: String) async throws -> [DungeonDefinition] { [] }
    func wizardVaultDaily() async throws -> WizardVaultAccountPeriod { try JSONDecoder().decode(WizardVaultAccountPeriod.self, from: Data(Self.daily.utf8)) }
    func wizardVaultWeekly() async throws -> WizardVaultAccountPeriod { try JSONDecoder().decode(WizardVaultAccountPeriod.self, from: Data(Self.weekly.utf8)) }
    func wizardVaultSpecial() async throws -> WizardVaultAccountSpecial { WizardVaultAccountSpecial(objectives: []) }
    func accountWizardVaultListings() async throws -> [WizardVaultAccountListing] { [] }
    func accountWorldBossIDs() async throws -> [String] { [] }
    func accountMapChestIDs() async throws -> [String] { [] }
    func accountDailyCraftingIDs() async throws -> [String] { [] }
    func accountRaidEventIDs() async throws -> [String] { [] }
    func accountDungeonPathIDs() async throws -> [String] { [] }
    func todayItems(ids: [Int]) async throws -> [Int: ItemMetadata] {
        [46742: ItemMetadata(id: 46742, name: "Lump of Mithrillium", icon: nil, rarity: "Ascended")]
    }
    func todayCurrencies(ids: [Int]) async throws -> [Int: CurrencyMetadata] {
        [63: CurrencyMetadata(id: 63, name: "Astral Acclaim", description: "", icon: nil, order: 1)]
    }
    func todayWallet() async throws -> [WalletEntry] { [WalletEntry(id: 63, value: 125)] }
    private static let daily = #"""
{
  "meta_progress_current": 3,
  "meta_progress_complete": 4,
  "meta_reward_item_id": 99961,
  "meta_reward_astral": 20,
  "meta_reward_claimed": false,
  "objectives": [
    {"id": 1, "title": "Complete 3 Events", "track": "PvE", "acclaim": 10, "progress_current": 0, "progress_complete": 3, "claimed": false},
    {"id": 2, "title": "Defeat 10 Enemies", "track": "PvE", "acclaim": 10, "progress_current": 4, "progress_complete": 10, "claimed": false},
    {"id": 3, "title": "Dodge 3 Attacks", "track": "PvE", "acclaim": 10, "progress_current": 3, "progress_complete": 3, "claimed": false},
    {"id": 4, "title": "Gather 10 Resources", "track": "PvE", "acclaim": 10, "progress_current": 10, "progress_complete": 10, "claimed": true}
  ]
}
"""#
    private static let weekly = #"""
{
  "meta_progress_current": 4,
  "meta_progress_complete": 6,
  "meta_reward_item_id": 100137,
  "meta_reward_astral": 450,
  "meta_reward_claimed": false,
  "objectives": [
    {"id": 5, "title": "Defeat Veteran Enemies", "track": "PvE", "acclaim": 50, "progress_current": 50, "progress_complete": 50, "claimed": true},
    {"id": 57, "title": "Complete 10 Events", "track": "PvE", "acclaim": 50, "progress_current": 7, "progress_complete": 10, "claimed": false}
  ]
}
"""#
}
#endif
