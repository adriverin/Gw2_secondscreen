import SwiftUI
import UIKit

struct QAModeView: View {
    @EnvironmentObject private var telemetry: TelemetryStore
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var today: TodayStore
    @EnvironmentObject private var goals: GoalStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var objectives: MapObjectiveStore
    @EnvironmentObject private var qa: QAResultStore
    @EnvironmentObject private var diagnostics: DeveloperDiagnostics
    @State private var exportText = ""
    @State private var showingExport = false
    @State private var refreshResults: [QADomainRefreshResult] = []
    @State private var isRefreshing = false
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                Text("Developer-only physical validation. Checks stay Not Tested until you explicitly mark Pass or Fail. Existing data never auto-passes a visual check.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let counts = qa.counts
                LabeledContent("Passed", value: "\(counts.passed)")
                LabeledContent("Failed", value: "\(counts.failed)")
                LabeledContent("Not tested", value: "\(counts.notTested)")
            }
            connectionStates
            Section("Live diagnostics") {
                NavigationLink("MumbleLink") { QAMumbleLinkView() }
                    .accessibilityIdentifier("qa.mumble.link")
                NavigationLink("Map Alignment workflow") { QAMapAlignmentView() }
                    .accessibilityIdentifier("qa.mapAlignment")
            }
            inventory
            apiKey
            apiRefresh
            apiMatrix
            timestamps
            mapDiagnostics
            events
            memory
            soak
            ForEach(QACheckGroup.allCases) { group in
                Section(group.title) {
                    ForEach(QACatalog.checks(in: group), id: \.id) { check in
                        NavigationLink {
                            QAGuidedCheckView(check: check)
                        } label: {
                            QACheckSummaryRow(check: check, result: qa.result(for: check.id))
                        }
                        .accessibilityIdentifier("qa.check.\(check.id)")
                    }
                    if group == .mapAlignment {
                        NavigationLink("Map Alignment workflow") { QAMapAlignmentView() }
                    }
                }
            }
            Section("Export") {
                Button("Capture QA Snapshot") { presentExport(full: true) }
                    .accessibilityIdentifier("qa.export")
                Button("Export QA Report") { presentExport(full: false) }
                Button("Export Support Bundle") { presentExport(full: true) }
                ShareLink(item: exportPayload) { Label("Share last export", systemImage: "square.and.arrow.up") }
                    .disabled(exportText.isEmpty)
                Button("Reset QA results", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle("Real Hardware QA")
        .accessibilityIdentifier("qa.screen")
        .toolbar {
            Button("Capture QA Snapshot") { presentExport(full: true) }
                .accessibilityIdentifier("qa.export")
        }
        .sheet(isPresented: $showingExport) {
            NavigationStack {
                ScrollView {
                    Text(exportText).font(.caption.monospaced()).textSelection(.enabled).padding()
                }
                .navigationTitle("QA Snapshot")
                .toolbar {
                    ShareLink(item: exportText)
                    Button("Copy") { UIPasteboard.general.string = exportText }
                }
            }
        }
        .confirmationDialog("Reset all QA results?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { qa.reset() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var connectionStates: some View {
        Section("Connection state") {
            ForEach(Self.stateKeys, id: \.self) { key in
                HStack {
                    Text(key).font(.caption.monospaced())
                    Spacer()
                    if telemetry.state.qaKey == key {
                        Text("CURRENT").font(.caption2.bold()).foregroundStyle(.green)
                    }
                }
                .listRowBackground(telemetry.state.qaKey == key ? Color.green.opacity(0.12) : Color.clear)
            }
            ForEach(diagnostics.transitions.suffix(4).reversed()) { transition in
                Text("\(diagnostics.timeFormatter.string(from: transition.at))  \(transition.from) → \(transition.to)")
                    .font(.caption.monospaced())
            }
        }
    }

    private var mapDiagnostics: some View {
        let snap = diagnostics.mapSnapshot
        return Section("Map tile QA") {
            Text(snap.diagnosticsText).font(.caption.monospaced()).textSelection(.enabled)
            Button("Copy Diagnostics") { UIPasteboard.general.string = snap.diagnosticsText }
                .accessibilityIdentifier("qa.copyDiagnostics")
            NavigationLink("Map Alignment workflow") { QAMapAlignmentView() }
                .accessibilityIdentifier("qa.mapAlignment.link")
        }
    }

    private var inventory: some View {
        Section {
            labeled("Characters loaded", "\(account.characters.count)")
            labeled("Character bag slots", "\(account.qaCharacterBagOccupiedSlots)")
            labeled("Bank occupied slots", "\(account.qaBankOccupiedSlots)")
            labeled("Material entries", "\(account.qaMaterialEntries)")
            labeled("Shared slots", "\(account.qaSharedOccupiedSlots)")
            Text(account.dataSource.qaLabel).font(.caption.bold())
            Button("Open Bank") { navigation.showInventory(.bank) }
            Button("Open Materials") { navigation.showInventory(.materials) }
            Button("Open Shared") { navigation.showInventory(.shared) }
            Button("Open Character Inventory") { navigation.showInventory(.characters) }
        } header: {
            Text("Account inventory")
        }
        .accessibilityIdentifier("qa.inventory")
    }

    private var timestamps: some View {
        Section("Account data timestamps") {
            labeled("Account metadata updated", stamp(account.accountMetadataUpdatedAt))
            labeled("Characters updated", stamp(account.charactersUpdatedAt))
            labeled("Inventory updated", stamp(account.inventoryUpdatedAt))
            labeled("Today updated", stamp(today.lastUpdatedAt))
            labeled("Prices updated", stamp(goals.pricesUpdatedAt))
            labeled("Account source", account.dataSource.qaLabel)
            labeled("Today source", today.dataSource.qaLabel)
        }
    }

    private var apiKey: some View {
        Section {
            permissionRow("Validated", account.connectionState == .connected)
            ForEach(AccountPermission.allCases.filter { $0 != .tradingPost }, id: \.rawValue) { permission in
                permissionRow(permission.rawValue, account.permissions.contains(permission))
            }
            if !account.permissions.contains(.inventories) {
                Text("missing inventories").foregroundStyle(.orange)
            }
            if !account.permissions.contains(.progression) {
                Text("missing progression").foregroundStyle(.orange)
            }
            Text("Limited-key test: create a second ArenaNet key with fewer permissions and replace the current key in Account. The app stores one key. Fixture coverage remains `--phase2-no-inventories` in Debug.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Check Characters") { Task { _ = await account.refreshQADomain(.characters) } }
            Button("Check Inventory") { Task { _ = await account.refreshQADomain(.inventory) } }
            Button("Check Today") { Task { await today.refresh(force: true) } }
            Button("Check Achievements") { Task { _ = await account.refreshQADomain(.achievements) } }
            Button("Check Builds") { Task { _ = await account.refreshQADomain(.builds) } }
        } header: {
            Text("API key")
        }
        .accessibilityIdentifier("qa.api")
    }

    private var apiRefresh: some View {
        Section("Refresh all account QA data") {
            Button("Refresh All Account QA Data") {
                Task {
                    isRefreshing = true
                    var values = await account.refreshAllQADomains()
                    let todayStarted = Date()
                    await today.refresh(force: true)
                    let todayResult = QADomainRefreshResult(
                        domain: .today, success: today.errorMessage == nil, httpStatus: today.errorMessage == nil ? 200 : nil,
                        message: today.errorMessage ?? "OK", usedCache: today.dataSource == .cached, timestamp: todayStarted)
                    DeveloperDiagnostics.shared.recordDomainRefresh(todayResult)
                    values.append(todayResult)
                    refreshResults = values
                    isRefreshing = false
                }
            }
            .disabled(isRefreshing)
            if isRefreshing { ProgressView() }
            ForEach(refreshResults) { result in
                LabeledContent(result.domain.title, value: result.success ? "✓ \(result.message)" : "✗ \(result.message)")
            }
        }
    }

    private var apiMatrix: some View {
        Section("API domain errors") {
            if diagnostics.apiDomains.isEmpty {
                Text("No ArenaNet calls recorded yet.").foregroundStyle(.secondary)
            }
            ForEach(diagnostics.apiDomains.values.sorted { $0.domain < $1.domain }) { status in
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.domain).font(.subheadline.bold())
                    Text("\(status.httpStatus.map(String.init) ?? "—") \(status.message)\(status.usedCache ? "  CACHED" : "")")
                        .font(.caption.monospaced())
                }
            }
        }
    }

    private var events: some View {
        Section("Network event log") {
            ForEach(diagnostics.events.suffix(12).reversed()) { event in
                Text(event.line(formatter: diagnostics.timeFormatter)).font(.caption.monospaced())
            }
            Button("Copy Event Log") { UIPasteboard.general.string = diagnostics.copiedEventLog }
            Button("Clear Event Log") { diagnostics.clearEvents() }
        }
    }

    private var memory: some View {
        let snap = MemoryDiagnostics.snapshot(
            telemetryPacketsPerSecond: telemetry.packetsPerSecond,
            activeMapMarkers: objectives.visibleObjectives.count,
            activeObjectives: objectives.objectives.count)
        return Section("Memory") {
            labeled("Tile cache count", "\(snap.tileCacheCount)")
            labeled("Image memory cache count", "\(snap.imageMemoryCacheCount)")
            labeled("Map icon count", "\(snap.mapIconCount)")
            labeled("Active map markers", "\(snap.activeMapMarkers)")
            labeled("Active objectives", "\(snap.activeObjectives)")
            labeled("Telemetry rate", "\(snap.telemetryPacketsPerSecond)/s")
            labeled("Available memory", snap.availableMemoryBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) } ?? "—")
            Text(TelemetryPublishAudit.summary).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var soak: some View {
        Section("Long-session soak (developer)") {
            Text("Runs a deterministic 30-minute movement, map change, disconnect, reconnect, and character-change script. It does not replace a real play session.")
                .font(.caption).foregroundStyle(.secondary)
            if telemetry.isSoaking {
                Button("Stop soak") { telemetry.stopSimulation() }
            } else {
                Button("Start 30-minute soak") { telemetry.startSoakSimulation() }
            }
        }
    }

    private func presentExport(full: Bool) {
        let secrets = QAExportFactory.secrets(account: account, telemetry: telemetry)
        let document = QASupportBundle.make(
            context: QAExportFactory.context(
                telemetry: telemetry, account: account, today: today, goals: goals,
                objectives: objectives, qa: qa, diagnostics: diagnostics, secrets: secrets),
            now: Date())
        exportText = full ? QASupportBundle.readableText(document) + "\n\n" + QASupportBundle.jsonString(document)
            : QASupportBundle.jsonString(document)
        showingExport = true
    }

    private var exportPayload: String { exportText.isEmpty ? "No export yet." : exportText }

    private func permissionRow(_ title: String, _ granted: Bool) -> some View {
        Label(title, systemImage: granted ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(granted ? Color.primary : Color.orange)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
    }

    private func stamp(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .standard) ?? "never"
    }

    private static let stateKeys = [
        "disconnected", "connecting", "connectedNoGW2", "connectedLive", "stale",
        "reconnecting", "pairingInvalid", "protocolMismatch", "unpaired", "positionUnavailable"
    ]
}

struct QACheckSummaryRow: View {
    let check: QACheckDefinition
    let result: QACheckResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: result.state.symbol)
                    .foregroundStyle(result.state == .passed ? .green : result.state == .failed ? .red : .secondary)
                Text(check.title)
                Spacer()
                Text(result.state.title).font(.caption).foregroundStyle(.secondary)
            }
            Text(check.requiredAction).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if result.state == .failed, let severity = result.severity {
                Text(severity.title).font(.caption2.bold()).foregroundStyle(.orange)
            }
        }
    }
}
