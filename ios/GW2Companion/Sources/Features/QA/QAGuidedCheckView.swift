import SwiftUI

struct QAGuidedCheckView: View {
    let check: QACheckDefinition
    @EnvironmentObject private var qa: QAResultStore
    @EnvironmentObject private var diagnostics: DeveloperDiagnostics
    @EnvironmentObject private var telemetry: TelemetryStore
    @State private var note: String
    @State private var severity: QASeverity = .p2

    init(check: QACheckDefinition) {
        self.check = check
        _note = State(initialValue: "")
    }

    var body: some View {
        Form {
            Section("Required action") { Text(check.requiredAction) }
            Section("Expected") { Text(check.expected) }
            if let steps = Self.steps[check.id] {
                Section("Steps") {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                    }
                }
            }
            Section("Observed") {
                if check.group == .mumbleLink || check.group == .pcConnection || check.group == .resilience {
                    LabeledContent("Connection", value: telemetry.state.label)
                    LabeledContent("Map ID", value: telemetry.latest?.map?.id.formatted() ?? "—")
                    LabeledContent("Packets/sec", value: "\(telemetry.packetsPerSecond)")
                }
                ForEach(diagnostics.events.suffix(8).reversed()) { event in
                    Text(event.line(formatter: diagnostics.timeFormatter)).font(.caption.monospaced())
                }
            }
            Section("Result") {
                Text("Do not mark Pass just because data exists. Confirm the visual or behavioral check.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Optional note", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                Picker("Severity if failed", selection: $severity) {
                    ForEach(QASeverity.allCases) { value in
                        Text("\(value.title) — \(value.summary)").tag(value)
                    }
                }
                Button("Pass") { qa.record(id: check.id, state: .passed, note: note) }
                    .accessibilityIdentifier("qa.pass")
                Button("Fail", role: .destructive) {
                    qa.record(id: check.id, state: .failed, note: note, severity: severity)
                }
                .accessibilityIdentifier("qa.fail")
                Button("Not Tested") { qa.record(id: check.id, state: .notTested, note: nil) }
                LabeledContent("Current", value: qa.result(for: check.id).state.title)
            }
        }
        .navigationTitle(check.title)
        .onAppear {
            note = qa.result(for: check.id).note ?? ""
            severity = qa.result(for: check.id).severity ?? .p2
        }
    }

    private static let steps: [String: [String]] = [
        "pc.reconnectAfterBridgeRestart": [
            "Confirm LIVE.",
            "Close bridge.",
            "Wait for Reconnecting.",
            "Restart bridge.",
            "Confirm LIVE returns."
        ],
        "resilience.bridgeRestart": [
            "Confirm LIVE.",
            "Close bridge.",
            "Wait for Reconnecting.",
            "Restart bridge.",
            "Confirm LIVE returns.",
            "Record timestamps from the event log."
        ],
        "resilience.gw2Restart": [
            "Start LIVE.",
            "Close Guild Wars 2.",
            "Confirm GW2 not running.",
            "Launch Guild Wars 2.",
            "Enter character.",
            "Confirm LIVE returns."
        ],
        "resilience.wifi": [
            "Confirm LIVE.",
            "Disable Wi-Fi on iPhone.",
            "Wait.",
            "Re-enable Wi-Fi.",
            "Confirm automatic reconnect."
        ],
        "resilience.background": [
            "Confirm LIVE.",
            "Background app for 30 seconds.",
            "Return.",
            "Confirm connection restores.",
            "Confirm map/session remains intact."
        ],
        "resilience.forceQuit": [
            "Start a Session.",
            "Lock one task.",
            "Skip one task.",
            "Force quit app.",
            "Relaunch.",
            "Confirm session, locked, and skipped restore.",
            "Confirm navigation waits for fresh telemetry and PC reconnects."
        ],
        "resilience.characterSwitch": [
            "Play Character A.",
            "Verify profile match.",
            "Return to character select.",
            "Enter Character B.",
            "Confirm live character, profile match, and map refresh with no stale identity."
        ],
        "mapTransition.mapId": [
            "Start on Core map A.",
            "Use a portal or waypoint to map B.",
            "Verify map ID, name, tiles, POIs, player marker, gathering, target, and route."
        ],
        "account.inventoryRefresh": [
            "Note quantity of one material in GW2.",
            "Open Materials in Companion.",
            "Compare quantity.",
            "Change account quantity in game.",
            "Refresh Companion.",
            "Compare again."
        ]
    ]
}
