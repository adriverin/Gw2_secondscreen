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
    @StateObject private var sessions = SessionStore()
    @StateObject private var today: TodayStore
    @StateObject private var navigation = AppNavigation()
    @StateObject private var qaResults = QAResultStore()
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
        _today = StateObject(wrappedValue: TodayStore(provider: api))
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
                    await account.start()
                    goals.setAccountScope(account.account?.id)
                    sessions.setAccountScope(account.account?.id)
                    await today.setAccountScope(account.account?.id, permissions: account.permissions)
                    await sessions.prepare(recipes: goals.recipes, prices: goals.marketPrices)
                }
                .onChange(of: telemetry.latest?.character?.name, initial: true) { _, name in
                    account.updateLiveCharacter(name: name)
                }
                .onChange(of: account.account?.id) { _, id in
                    goals.setAccountScope(id)
                    sessions.setAccountScope(id)
                    Task { await today.setAccountScope(id, permissions: account.permissions) }
                }
                .onChange(of: account.tokenInfo?.permissions) { _, _ in
                    Task { await today.setAccountScope(account.account?.id, permissions: account.permissions) }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    MapIconStore.shared.handleMemoryPressure()
                    Task { await MapTileImageCache.shared.handleMemoryPressure() }
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
    @State private var splitVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("onboarding.completed.v1") private var onboardingCompleted = false

    var body: some View {
        Group {
        if horizontalSizeClass == .regular {
            NavigationSplitView(columnVisibility: $splitVisibility) {
                List {
                    ForEach(AppTab.iPadSidebar) { tab in
                        Button {
                            navigation.show(tab)
                        } label: {
                            Label(tab.title, systemImage: tab.symbol)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sidebar.\(tab.title.lowercased())")
                        .listRowBackground(navigation.selectedTab == tab ? GWPalette.accent.opacity(0.16) : Color.clear)
                    }
                }
                .navigationTitle("GW2 Companion")
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
        }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingCompleted },
            set: { if !$0 { onboardingCompleted = true } }
        )) { OnboardingFlow() }
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
