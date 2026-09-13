import SwiftUI

@main
struct GW2CompanionApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var telemetry = TelemetryStore()
    @StateObject private var gathering = GatheringStore()
    @StateObject private var overlays = MapOverlayStore()
    @StateObject private var objectives = MapObjectiveStore()
    @StateObject private var account: AccountStore
    @StateObject private var navigation = AppNavigation()
    private let api: GW2APIClient

    init() {
        let api = GW2APIClient()
        self.api = api
        _account = StateObject(wrappedValue: AccountStore(api: api))
    }

    var body: some Scene {
        WindowGroup {
            RootNavigationView(api: api)
                .environmentObject(telemetry)
                .environmentObject(gathering)
                .environmentObject(overlays)
                .environmentObject(objectives)
                .environmentObject(account)
                .environmentObject(navigation)
                .tint(GWPalette.accent)
                .task {
                    telemetry.connectSavedPairing()
                    await account.start()
                }
                .onChange(of: telemetry.latest?.character?.name, initial: true) { _, name in
                    account.updateLiveCharacter(name: name)
                }
        }
        .onChange(of: scenePhase) { _, phase in telemetry.setAppActive(phase == .active) }
    }
}

private struct RootNavigationView: View {
    let api: GW2APIClient
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var navigation: AppNavigation
    @State private var splitVisibility: NavigationSplitViewVisibility = .detailOnly

    var body: some View {
        if horizontalSizeClass == .regular {
            NavigationSplitView(columnVisibility: $splitVisibility) {
                List {
                    ForEach(AppTab.allCases) { tab in
                        Button {
                            navigation.selectedTab = tab
                            splitVisibility = .detailOnly
                        } label: {
                            Label(tab.title, systemImage: tab.symbol)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(navigation.selectedTab == tab ? GWPalette.accent.opacity(0.16) : Color.clear)
                    }
                }
                .navigationTitle("GW2 Companion")
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 250)
            } detail: {
                content(for: navigation.selectedTab)
            }
        } else {
            TabView(selection: $navigation.selectedTab) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    content(for: tab)
                        .tabItem { Label(tab.title, systemImage: tab.symbol) }
                        .tag(tab)
                }
            }
        }
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .map: LiveMapView(api: api)
        case .characters: CharactersView()
        case .inventory: InventoryView()
        case .account: AccountView()
        }
    }
}
