import SwiftUI

struct QAMapAlignmentView: View {
    @EnvironmentObject private var telemetry: TelemetryStore
    @EnvironmentObject private var objectives: MapObjectiveStore
    @EnvironmentObject private var qa: QAResultStore
    @State private var selectedObjectiveID: MapObjectiveID?
    @State private var selectedKind = AlignmentKind.coreTyriaWaypoint
    @State private var note = ""
    @State private var severity: QASeverity = .p1

    private let projection = ArenaNetTileProjection.shared

    enum AlignmentKind: String, CaseIterable, Identifiable {
        case coreTyriaWaypoint, poi, edge, expansion
        var id: String { rawValue }
        var title: String {
            switch self {
            case .coreTyriaWaypoint: "Core Tyria waypoint"
            case .poi: "POI"
            case .edge: "Map edge"
            case .expansion: "Expansion map if artwork exists"
            }
        }
        var checkID: String {
            switch self {
            case .coreTyriaWaypoint: "map.coreTyriaWaypoint"
            case .poi: "map.poi"
            case .edge: "map.edge"
            case .expansion: "map.expansionArtwork"
            }
        }
        var objectiveType: MapObjectiveType? {
            switch self {
            case .coreTyriaWaypoint: .waypoint
            case .poi: .landmark
            case .edge, .expansion: nil
            }
        }
    }

    var body: some View {
        List {
            Section("Step 1") {
                Text("Stand directly on a waypoint in Guild Wars 2.")
            }
            Section("Step 2") {
                Picker("Check", selection: $selectedKind) {
                    ForEach(AlignmentKind.allCases) { kind in Text(kind.title).tag(kind) }
                }
                Picker("Official landmark", selection: $selectedObjectiveID) {
                    Text("Select…").tag(nil as MapObjectiveID?)
                    ForEach(landmarks) { objective in
                        Text(objective.name).tag(objective.id as MapObjectiveID?)
                    }
                }
            }
            if let measurement {
                Section("PLAYER") {
                    LabeledContent("X", value: fmt(measurement.player.x))
                    LabeledContent("Y", value: fmt(measurement.player.y))
                }
                Section("WAYPOINT") {
                    LabeledContent("X", value: fmt(measurement.landmark.x))
                    LabeledContent("Y", value: fmt(measurement.landmark.y))
                }
                Section("DELTA") {
                    LabeledContent("X", value: fmt(measurement.dx))
                    LabeledContent("Y", value: fmt(measurement.dy))
                    LabeledContent("DISTANCE", value: fmt(measurement.distance))
                }
                Section("Step 3") {
                    Text("Does the player marker visually overlap the waypoint on the background artwork?")
                    Text("Numeric distance is a hint only. You must confirm overlap. No hidden offset is applied.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Optional note", text: $note, axis: .vertical)
                    Picker("Severity if failed", selection: $severity) {
                        ForEach(QASeverity.allCases) { Text($0.title).tag($0) }
                    }
                    Button("Pass") {
                        qa.record(id: selectedKind.checkID, state: .passed, note: note)
                    }
                    .accessibilityIdentifier("qa.alignment.pass")
                    Button("Fail", role: .destructive) {
                        qa.record(id: selectedKind.checkID, state: .failed, note: note, severity: severity)
                    }
                    .accessibilityIdentifier("qa.alignment.fail")
                    LabeledContent("Current", value: qa.result(for: selectedKind.checkID).state.title)
                }
            } else {
                Section {
                    Text("Fresh LIVE telemetry and a landmark on the current map are required.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Coverage") {
                Text(DeveloperDiagnostics.shared.mapSnapshot.diagnosticsText)
                    .font(.caption.monospaced())
            }
        }
        .navigationTitle("Map Alignment")
        .accessibilityIdentifier("qa.mapAlignment.screen")
    }

    private var landmarks: [MapObjective] {
        let type = selectedKind.objectiveType
        return objectives.objectives
            .filter { type == nil || $0.type == type }
            .sorted { $0.name < $1.name }
    }

    private var measurement: MapAlignmentMeasurement? {
        guard telemetry.state == .connectedLive, let player = telemetry.latest?.player,
              let selectedObjectiveID,
              let objective = landmarks.first(where: { $0.id == selectedObjectiveID }) else { return nil }
        return MapAlignmentMeasurement.measure(
            player: ContinentPoint(x: player.continentX, y: player.continentY),
            landmark: objective.coordinate,
            continentID: 1,
            floor: 1,
            projection: projection)
    }

    private func fmt(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(3)))
    }
}
