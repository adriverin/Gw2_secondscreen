import SwiftUI
import UIKit

struct ConnectionDiagnosticsView: View {
    @EnvironmentObject private var telemetry: TelemetryStore
    var showTechnicalDetails = false

    var body: some View {
        List {
            Section("PC Connection") {
                LabeledContent("Gaming PC", value: telemetry.savedPairing?.bridgeId.map { "Bridge \($0.prefix(8).uppercased())…" } ?? "Not identified")
                LabeledContent("Address", value: telemetry.savedPairing.map { "\($0.host):\($0.port)" } ?? "Not paired")
                LabeledContent("Status", value: telemetry.state.label)
            }
            Section("Guild Wars 2") {
                LabeledContent("Game", value: gameStatus)
                LabeledContent("Telemetry", value: telemetry.state == .connectedLive ? "\(telemetry.packetsPerSecond) packets/sec" : "Not live")
                LabeledContent("Last update", value: lastUpdate)
                LabeledContent("Character", value: redactedCharacter)
                LabeledContent("Map", value: telemetry.latest?.map?.id.formatted() ?? "—")
            }
            if needsTroubleshooting {
                Section("Can’t reach your PC") {
                    Text("1. Confirm this device and the PC are on the same trusted network.\n2. Keep GW2 Companion Bridge running.\n3. Allow the bridge on Private networks in Windows Firewall.\n4. If the PC changed networks, scan the current QR code again.")
                    Button("Try Again") { telemetry.connectSavedPairing() }
                }
            } else if telemetry.state == .connectedNoGW2 {
                Section("Connected to your PC") {
                    Text("Guild Wars 2 is not currently providing telemetry. Launch the game and enter a character.")
                }
            }
            if showTechnicalDetails {
                Section("Protocol") {
                    LabeledContent("App protocol", value: "\(BridgeProtocol.current)")
                    LabeledContent("Telemetry tick", value: telemetry.latest?.uiTick.formatted() ?? "—")
                    LabeledContent("Position available", value: telemetry.latest?.positionAvailable == true ? "Yes" : "No")
                }
            }
        }
        .navigationTitle("Connection")
        .refreshable { telemetry.connectSavedPairing() }
    }

    private var gameStatus: String {
        switch telemetry.state {
        case .connectedLive, .stale, .positionUnavailable: "Running"
        case .connectedNoGW2: "Not running"
        default: "Unknown"
        }
    }
    private var needsTroubleshooting: Bool { [.disconnected, .reconnecting].contains(telemetry.state) }
    private var lastUpdate: String {
        guard let date = telemetry.lastUpdate else { return "Never" }
        let seconds = max(0, Date().timeIntervalSince(date))
        return seconds < 1 ? "Less than a second ago" : "\(Int(seconds)) sec ago"
    }
    private var redactedCharacter: String {
        showTechnicalDetails ? (telemetry.latest?.character?.name ?? "—") : (telemetry.latest?.character == nil ? "—" : "Available (redacted)")
    }
}

struct DiagnosticsExportView: View {
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var telemetry: TelemetryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("The report is redacted by default. It never contains your API key, pairing token, account name, character name, portraits, or inventory contents.")
                }
                Section("Preview") { Text(report).font(.caption.monospaced()).textSelection(.enabled) }
                Section { ShareLink(item: report) { Label("Export Diagnostics", systemImage: "square.and.arrow.up") } }
            }
            .navigationTitle("Diagnostics Report")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private var report: String {
        let payload: [String: Any] = [
            "appVersion": AppBuildInfo.version,
            "build": AppBuildInfo.build,
            "device": UIDevice.current.model,
            "systemVersion": UIDevice.current.systemVersion,
            "bridgeProtocolVersion": BridgeProtocol.current,
            "connectionStatus": telemetry.state.label,
            "bridgeConfigured": telemetry.savedPairing != nil,
            "mapId": telemetry.latest?.map?.id ?? -1,
            "telemetryPacketsPerSecond": telemetry.packetsPerSecond,
            "apiPermissions": account.tokenInfo?.permissions.sorted() ?? [],
            "accountLastRefresh": account.accountLastRefreshedAt?.ISO8601Format() ?? "never",
            "accountUsingSavedData": account.isStale,
            "accountError": account.errorMessage ?? "none",
            "redaction": "account and character names omitted"
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return "Diagnostics could not be generated."
        }
        return String(decoding: data, as: UTF8.self)
    }
}

struct PrivacySummaryView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                privacyRow("Guild Wars 2 API key", "Stored in iOS Keychain, available only while this device is unlocked, and never migrated to another device.", "key.fill")
                privacyRow("Live gameplay position", "Sent only from your PC to this device over your local network.", "location.fill")
                privacyRow("Account data", "Requested directly from ArenaNet over HTTPS.", "lock.shield.fill")
                privacyRow("Cloud storage", "None.", "icloud.slash")
                privacyRow("Analytics", "None.", "chart.bar.xaxis")
                Section("Local network security") {
                    Text("Bridge traffic uses an authenticated but unencrypted local WebSocket. Use it only on a trusted home network. Your API key is never included in bridge traffic.")
                }
            }
            .navigationTitle("Data & Privacy")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
    private func privacyRow(_ title: String, _ text: String, _ symbol: String) -> some View {
        Section(title) { Label(text, systemImage: symbol) }
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                help("Getting Started", "Account and PC setup are both optional. Connect either one from Settings; the public map remains available without them.")
                help("Connecting your GW2 account", "Create a key on ArenaNet’s Applications page with only the recommended permissions. The key stays in iOS Keychain.")
                help("Why a bridge is required", "ArenaNet’s web API has no live position. The small Windows bridge reads official MumbleLink telemetry locally.")
                help("Can’t reach your PC", "Use the same trusted network, keep the bridge open, and allow it on Private networks in Windows Firewall. Scan again after a PC address or pairing change.")
                help("PC connected, GW2 not running", "Launch Guild Wars 2 and enter a character. Loading screens and character select can pause telemetry briefly without requiring action.")
                help("Privacy", "There is no cloud service or analytics. The app does not request GPS permission.")
            }
            .navigationTitle("Help")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
    private func help(_ title: String, _ text: String) -> some View {
        Section(title) { Text(text) }
    }
}

struct MapCalibrationView: View {
    @EnvironmentObject private var telemetry: TelemetryStore
    @EnvironmentObject private var objectives: MapObjectiveStore
    @State private var selectedID: MapObjectiveID?
    @State private var selectedHarness = MapAlignmentLandmarks.kessexHavenWaypoint.name
    private let tolerance = 75.0
    private let projection = ArenaNetTileProjection.shared

    var body: some View {
        List {
            Section {
                Text("Stand directly at a known official waypoint in Guild Wars 2, then select that waypoint below. This tool reports the raw difference and never applies hidden correction offsets.")
            }
            Section("Official waypoint") {
                Picker("Waypoint", selection: $selectedID) {
                    Text("Select…").tag(nil as MapObjectiveID?)
                    ForEach(waypoints) { waypoint in Text(waypoint.name).tag(waypoint.id as MapObjectiveID?) }
                }
            }
            if let measurement {
                Section("CURRENT CONTINENT") {
                    LabeledContent("Player X", value: measurement.player.x.formatted(.number.precision(.fractionLength(3))))
                    LabeledContent("Player Y", value: measurement.player.y.formatted(.number.precision(.fractionLength(3))))
                    LabeledContent("Objective X", value: measurement.objective.x.formatted(.number.precision(.fractionLength(3))))
                    LabeledContent("Objective Y", value: measurement.objective.y.formatted(.number.precision(.fractionLength(3))))
                    LabeledContent("Delta X", value: measurement.dx.formatted(.number.precision(.fractionLength(3))))
                    LabeledContent("Delta Y", value: measurement.dy.formatted(.number.precision(.fractionLength(3))))
                    LabeledContent("Distance", value: measurement.distance.formatted(.number.precision(.fractionLength(2))))
                    Label(measurement.distance <= tolerance ? "Alignment appears correct" : "Alignment needs investigation",
                          systemImage: measurement.distance <= tolerance ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(measurement.distance <= tolerance ? .green : .orange)
                }
                Section("TILE WORLD") {
                    LabeledContent("Player X", value: measurement.playerTile.x.formatted(.number.precision(.fractionLength(3))))
                    LabeledContent("Player Y", value: measurement.playerTile.y.formatted(.number.precision(.fractionLength(3))))
                    LabeledContent("EoD tile offset X", value: measurement.eodOffset.x.formatted())
                    LabeledContent("EoD tile offset Y", value: measurement.eodOffset.y.formatted())
                    LabeledContent("Tile z", value: "\(measurement.tile.zoom)")
                    LabeledContent("Tile x", value: "\(measurement.tile.x)")
                    LabeledContent("Tile y", value: "\(measurement.tile.y)")
                    LabeledContent("Map ID", value: "\(telemetry.latest?.map?.id ?? -1)")
                    LabeledContent("Continent", value: "\(measurement.config.continentID)")
                    LabeledContent("Floor", value: "\(telemetry.latest?.map?.id == nil ? 1 : 1)")
                    LabeledContent("API max zoom", value: "\(measurement.config.advertisedMaxZoom)")
                    LabeledContent("Projection reference zoom", value: "\(measurement.config.referenceZoom)")
                }
                Section { ShareLink(item: report(measurement)) { Label("Export Calibration Report", systemImage: "square.and.arrow.up") } }
            } else {
                Section { Text("Fresh live telemetry and a waypoint on the current map are required.").foregroundStyle(.secondary) }
            }
            Section("Alignment harness") {
                Picker("Landmark", selection: $selectedHarness) {
                    ForEach(MapAlignmentLandmarks.coreTyria, id: \.name) { Text($0.name).tag($0.name) }
                }
                if let landmark = MapAlignmentLandmarks.coreTyria.first(where: { $0.name == selectedHarness }) {
                    NavigationLink("Render tiles + \(landmark.name)") {
                        MapAlignmentHarnessView(
                            landmark: landmark,
                            metadata: harnessMetadata(for: landmark))
                    }
                }
            }
        }
        .navigationTitle("Map Calibration")
    }

    private func harnessMetadata(for landmark: MapAlignmentLandmarks.Landmark) -> GW2MapMetadata {
        switch landmark.mapID {
        case 15: MapAlignmentLandmarks.queensdaleMetadata
        case 23: MapAlignmentLandmarks.kessexHillsMetadata
        case 50: MapAlignmentLandmarks.lionsArchMetadata
        case 53: MapAlignmentLandmarks.sparkflyFenMetadata
        default: MapAlignmentLandmarks.kessexHillsMetadata
        }
    }

    private var waypoints: [MapObjective] {
        objectives.objectives.filter { $0.type == .waypoint }.sorted { $0.name < $1.name }
    }
    private var measurement: (
        player: ContinentPoint, objective: ContinentPoint, dx: Double, dy: Double, distance: Double,
        playerTile: TileWorldCoordinate, eodOffset: (x: Double, y: Double), tile: TileIndex,
        config: TileProjectionConfiguration
    )? {
        guard telemetry.state == .connectedLive, let player = telemetry.latest?.player,
              let selectedID, let objective = waypoints.first(where: { $0.id == selectedID }) else { return nil }
        let p = ContinentPoint(x: player.continentX, y: player.continentY)
        let o = objective.coordinate
        let continentID = 1
        let config = projection.configuration(continentID: continentID)
        let tileWorld = projection.tileWorldCoordinate(from: p, continentID: continentID, mapFloor: 1)
            ?? TileWorldCoordinate(x: p.x, y: p.y)
        let tile = projection.tileIndex(from: tileWorld, zoom: config.referenceZoom, continentID: continentID)
            ?? TileIndex(zoom: config.referenceZoom, x: -1, y: -1)
        return (
            p, o, p.x - o.x, p.y - o.y, ObjectiveDistanceEngine.distance(from: p, to: o),
            tileWorld,
            (config.usesLegacyTileOrigin ? EndOfDragonsShift.deltaX : 0,
             config.usesLegacyTileOrigin ? EndOfDragonsShift.deltaY : 0),
            tile, config)
    }
    private func report(_ value: (
        player: ContinentPoint, objective: ContinentPoint, dx: Double, dy: Double, distance: Double,
        playerTile: TileWorldCoordinate, eodOffset: (x: Double, y: Double), tile: TileIndex,
        config: TileProjectionConfiguration
    )) -> String {
        let payload: [String: Any] = [
            "mapId": telemetry.latest?.map?.id ?? -1,
            "character": "redacted",
            "continent": [value.player.x, value.player.y],
            "tileWorld": [value.playerTile.x, value.playerTile.y],
            "eodOffset": [value.eodOffset.x, value.eodOffset.y],
            "tile": ["z": value.tile.zoom, "x": value.tile.x, "y": value.tile.y],
            "referenceZoom": value.config.referenceZoom,
            "advertisedMaxZoom": value.config.advertisedMaxZoom,
            "objective": [value.objective.x, value.objective.y],
            "delta": [value.dx, value.dy],
            "distance": value.distance,
            "timestamp": Date().ISO8601Format()
        ]
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "Calibration report unavailable"
    }
}
