import SwiftUI
import UIKit

struct LiveMapView: View {
    let api: GW2APIClient
    @EnvironmentObject private var telemetry: TelemetryStore
    @EnvironmentObject private var gathering: GatheringStore
    @EnvironmentObject private var overlays: MapOverlayStore
    @State private var metadata: GW2MapMetadata?
    @State private var metadataFailed = false
    @State private var followPlayer = true
    @State private var showingLayers = false
    @State private var showingPairing = false
    @State private var selectedLandmark: MapLandmark?

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
        return GatheringGeometry.nearest(to: playerPoint, among: gathering.visibleNodes.filter { !gathering.harvested.contains($0.id) })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NativeTileMapView(
                    player: playerPoint,
                    heading: heading,
                    metadata: metadata,
                    nodes: gathering.visibleNodes,
                    landmarks: overlays.visibleLandmarks,
                    visited: gathering.visited,
                    harvested: gathering.harvested,
                    followPlayer: $followPlayer,
                    onToggleHarvested: gathering.toggleHarvested,
                    onSelectLandmark: { selectedLandmark = $0 })
                    .ignoresSafeArea(edges: .top)

                VStack(spacing: 10) {
                    header
                    connectionBanner
                    if metadataFailed { unavailableArtworkBanner }
                    overlayStatusBanner
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
            .sheet(item: $selectedLandmark) { LandmarkDetailView(landmark: $0) }
            .task(id: telemetry.latest?.map?.id) {
                guard let mapId = telemetry.latest?.map?.id else {
                    metadata = nil
                    gathering.clear()
                    overlays.clear()
                    return
                }
                await loadMap(mapId)
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
    private var overlayStatusBanner: some View {
        switch overlays.state {
        case .loading:
            statusBanner("Loading map landmarks…", symbol: "map")
        case .loaded where overlays.landmarks.isEmpty:
            statusBanner("No official landmarks were returned for this map and floor.", symbol: "map")
        case let .unavailable(message):
            statusBanner("Landmarks unavailable: \(message)", symbol: "exclamationmark.triangle")
        default:
            switch gathering.availability {
            case .unavailable:
                statusBanner("Known gathering locations are not yet available for this map.", symbol: "leaf")
            case .failed:
                statusBanner("Gathering locations could not be loaded.", symbol: "exclamationmark.triangle")
            default:
                EmptyView()
            }
        }
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
        case .bridgeOffline:
            statusBanner("Can't reach your PC. Make sure both devices are on the same network.", symbol: "wifi.slash")
        case .connecting:
            statusBanner("Connecting to GW2 Companion Bridge…", symbol: "arrow.triangle.2.circlepath")
        case .reconnecting:
            statusBanner("Connection lost. Reconnecting automatically…", symbol: "arrow.triangle.2.circlepath")
        case .pairAgain:
            VStack(spacing: 8) {
                statusBanner("The bridge pairing changed. Scan its QR code again.", symbol: "qrcode")
                Button("Pair again") { showingPairing = true }.buttonStyle(.borderedProminent).tint(.orange)
            }
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
        case .connecting, .reconnecting: .yellow
        default: .orange
        }
    }

    private func loadMap(_ id: Int) async {
        metadataFailed = false
        do {
            let loadedMetadata = try await api.map(id: id)
            guard telemetry.latest?.map?.id == id else { return }
            metadata = loadedMetadata
            async let landmarkLoad: Void = overlays.load(provider: api, metadata: loadedMetadata)
            async let gatheringLoad: Void = gathering.load(
                mapId: id, metadata: loadedMetadata, simulation: telemetry.isSimulating)
            _ = await (landmarkLoad, gatheringLoad)
        } catch is CancellationError {
            return
        } catch {
            guard telemetry.latest?.map?.id == id else { return }
            metadata = nil
            metadataFailed = true
            gathering.clear()
            overlays.clear()
        }
    }
}

private struct LandmarkDetailView: View {
    let landmark: MapLandmark
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(landmark.name, systemImage: landmark.kind.symbol).font(.headline)
                    Text(landmark.kind.title).foregroundStyle(.secondary)
                }
                if let chatLink = landmark.chatLink, !chatLink.isEmpty {
                    Section("In-game chat link") {
                        Text(chatLink).textSelection(.enabled).monospaced()
                        Button(copied ? "Copied" : "Copy chat link") {
                            UIPasteboard.general.string = chatLink
                            copied = true
                        }
                    }
                }
            }
            .navigationTitle("Map marker")
            .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium])
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
