import SwiftUI

@main
struct GW2CompanionApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var telemetry = TelemetryStore()
    @StateObject private var gathering = GatheringStore()
    private let api = GW2APIClient()

    var body: some Scene {
        WindowGroup {
            RootTabView(api: api)
                .environmentObject(telemetry)
                .environmentObject(gathering)
                .preferredColorScheme(.dark)
                .task { telemetry.connectSavedPairing() }
        }
        .onChange(of: scenePhase) { _, phase in telemetry.setAppActive(phase == .active) }
    }
}

struct RootTabView: View {
    let api: GW2APIClient

    var body: some View {
        TabView {
            LiveMapView(api: api)
                .tabItem { Label("Map", systemImage: "map.fill") }
            CharactersView(api: api)
                .tabItem { Label("Characters", systemImage: "person.2.fill") }
            InventoryView(api: api)
                .tabItem { Label("Inventory", systemImage: "shippingbox.fill") }
            AccountView(api: api)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .tint(.orange)
    }
}
