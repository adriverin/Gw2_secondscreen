import SwiftUI

struct LiveMapView: View {
    let api: GW2APIClient
    @EnvironmentObject private var telemetry: TelemetryStore
    @EnvironmentObject private var gathering: GatheringStore
    @State private var metadata: GW2MapMetadata?
    @State private var metadataFailed = false
    @State private var followPlayer = true
    @State private var showingLayers = false
    @State private var showingPairing = false

    private var playerPoint: ContinentPoint? {
        guard telemetry.latest?.positionAvailable == true, let player = telemetry.latest?.player else { return nil }
        return ContinentPoint(x: player.continentX, y: player.continentY)
    }

    private var heading: Double {
        guard let player = telemetry.latest?.player else { return 0 }
        return atan2(player.headingX, -player.headingY)
    }

    private var nearest: GatheringNode? {
        guard let playerPoint else { return nil }
        return GatheringGeometry.nearest(to: playerPoint, among: gathering.visibleNodes.filter { !gathering.visited.contains($0.id) })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NativeTileMapView(
                    player: playerPoint,
                    heading: heading,
                    metadata: metadata,
                    nodes: gathering.visibleNodes,
                    visited: gathering.visited,
                    followPlayer: $followPlayer,
                    onToggleVisited: gathering.toggleVisited)
                    .ignoresSafeArea(edges: .top)

                VStack(spacing: 10) {
                    header
                    connectionBanner
                    if metadataFailed { unavailableArtworkBanner }
                    Spacer()
                    if let nearest { nearestCard(nearest) }
                    controls
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingLayers) { LayerPanelView() }
            .sheet(isPresented: $showingPairing) { PairingView() }
            .task(id: telemetry.latest?.map?.id) {
                guard let mapId = telemetry.latest?.map?.id else { return }
                metadataFailed = false
                async let mapLoad: Void = loadMetadata(mapId)
                async let markerLoad: Void = gathering.load(mapId: mapId)
                _ = await (mapLoad, markerLoad)
            }
            .onChange(of: playerPoint) { _, point in
                if let point { gathering.updatePlayer(point) }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(metadata?.name ?? telemetry.latest?.map.map { "Map ID \($0.id)" } ?? "Live Map")
                    .font(.headline)
                if let name = telemetry.latest?.character?.name, !name.isEmpty {
                    Text(name).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { if telemetry.state == .unpaired { showingPairing = true } } label: {
                Text(telemetry.state.label)
                    .font(.caption2.bold())
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
        .padding(.top, 8)
    }

    private var controls: some View {
        HStack {
            Button { showingLayers = true } label: { Label("Layers", systemImage: "square.3.layers.3d") }
                .buttonStyle(MapControlButtonStyle())
            Spacer()
            Button {
                followPlayer = true
            } label: {
                Label(followPlayer ? "Following" : "Center", systemImage: followPlayer ? "location.fill" : "location")
            }
            .buttonStyle(MapControlButtonStyle())
            Button { showingPairing = true } label: { Image(systemName: "desktopcomputer") }
                .buttonStyle(MapControlButtonStyle())
        }
    }

    private var unavailableArtworkBanner: some View {
        Label("Map artwork unavailable for this area. Live telemetry remains connected.", systemImage: "map")
            .font(.caption)
            .padding(9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var connectionBanner: some View {
        switch telemetry.state {
        case .unpaired:
            VStack(spacing: 8) {
                Label("Connect your gaming PC", systemImage: "desktopcomputer")
                    .font(.headline)
                Text("Scan the bridge QR code, enter its LAN address, or start the built-in simulation.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Connect to PC") { showingPairing = true }.buttonStyle(.borderedProminent).tint(.orange)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
        case .gameNotRunning:
            statusBanner("Guild Wars 2 is not running.", symbol: "gamecontroller")
        case let .positionUnavailable(message):
            statusBanner(message, symbol: "location.slash")
        case .pcOffline:
            statusBanner("Can't reach your PC. Make sure both devices are on the same network.", symbol: "wifi.slash")
        case .connecting:
            statusBanner("Connecting to GW2 Companion Bridge…", symbol: "arrow.triangle.2.circlepath")
        case .live:
            EmptyView()
        }
    }

    private func statusBanner(_ message: String, symbol: String) -> some View {
        Label(message, systemImage: symbol)
            .font(.caption)
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func nearestCard(_ node: GatheringNode) -> some View {
        HStack(spacing: 9) {
            Image(systemName: node.category.symbol).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Nearest node").font(.caption2).foregroundStyle(.secondary)
                Text(node.name).font(.subheadline.bold())
            }
            Spacer()
            if let playerPoint { Text(GatheringGeometry.direction(from: playerPoint, to: node).rawValue).font(.headline) }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
    }

    private var statusColor: Color {
        switch telemetry.state {
        case .live: .green
        case .connecting: .yellow
        default: .orange
        }
    }

    private func loadMetadata(_ id: Int) async {
        do { metadata = try await api.map(id: id) }
        catch { metadata = nil; metadataFailed = true }
    }
}

private struct MapControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
