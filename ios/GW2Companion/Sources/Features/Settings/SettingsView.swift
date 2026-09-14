import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var telemetry: TelemetryStore
    @EnvironmentObject private var goals: GoalStore
    @EnvironmentObject private var sessions: SessionStore
    @EnvironmentObject private var objectives: MapObjectiveStore
    @AppStorage("developer.mode.enabled") private var developerMode = false
    @AppStorage("onboarding.completed.v1") private var onboardingCompleted = false
    @State private var showingPairing = false
    @State private var showingAccount = false
    @State private var showingHelp = false
    @State private var showingPrivacy = false
    @State private var showingDiagnostics = false
    @State private var confirmation: DestructiveAction?
    @State private var versionTaps = 0

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    Button { showingAccount = true } label: {
                        settingsRow("Guild Wars 2 Account", detail: account.account?.name ?? (account.connectionState == .connected ? "Connected" : "Not connected"), symbol: "person.crop.circle")
                    }
                    if account.connectionState == .connected {
                        NavigationLink("Permissions") { PermissionDetailsView() }
                    }
                }
                Section("PC") {
                    Button { showingPairing = true } label: {
                        settingsRow("Gaming PC", detail: telemetry.savedPairing.map { "\($0.host):\($0.port)" } ?? "Not paired", symbol: "desktopcomputer")
                    }
                    NavigationLink("Connection Diagnostics") { ConnectionDiagnosticsView() }
                }
                Section("Data") {
                    Button("Clear Cached Game Data") { confirmation = .cache }
                    Button("Delete Local Goals & History", role: .destructive) { confirmation = .localHistory }
                }
                Section("Privacy") {
                    Button("Data & Privacy") { showingPrivacy = true }
                    Button("Export Diagnostics") { showingDiagnostics = true }
                }
                Section("Help") { Button("Getting Started & Troubleshooting") { showingHelp = true } }
                Section("About") {
                    Button { unlockDeveloperMode() } label: {
                        settingsRow("GW2 Companion", detail: AppBuildInfo.versionAndBuild, symbol: "info.circle")
                    }.buttonStyle(.plain)
                    LabeledContent("Bridge Protocol", value: "\(BridgeProtocol.current)")
                    Text("GW2 Companion is an unofficial companion application and is not affiliated with or endorsed by ArenaNet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if developerMode {
                    Section("Developer") {
                        NavigationLink("Diagnostics") { ConnectionDiagnosticsView(showTechnicalDetails: true) }
                        NavigationLink("Map Calibration") { MapCalibrationView() }
                        Button(telemetry.isSimulating ? "Stop Telemetry Simulation" : "Start Telemetry Simulation") {
                            telemetry.isSimulating ? telemetry.stopSimulation() : telemetry.startSimulation()
                        }
                        Button("Disable Developer Mode") { developerMode = false }
                    }
                }
                Section {
                    Button("Reset App", role: .destructive) { confirmation = .reset }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingPairing) { PairingView() }
            .sheet(isPresented: $showingAccount) { NavigationStack { AccountSetupForm(connected: { showingAccount = false }) } }
            .sheet(isPresented: $showingPrivacy) { PrivacySummaryView() }
            .sheet(isPresented: $showingHelp) { HelpView() }
            .sheet(isPresented: $showingDiagnostics) { DiagnosticsExportView() }
            .confirmationDialog(confirmation?.title ?? "", isPresented: Binding(
                get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }
            ), titleVisibility: .visible) {
                if let confirmation {
                    Button(confirmation.button, role: .destructive) { perform(confirmation) }
                    Button("Cancel", role: .cancel) { self.confirmation = nil }
                }
            } message: { Text(confirmation?.message ?? "") }
        }
    }

    private func settingsRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack { Label(title, systemImage: symbol); Spacer(); Text(detail).foregroundStyle(.secondary) }
            .contentShape(Rectangle())
    }

    private func unlockDeveloperMode() {
        versionTaps += 1
        if versionTaps >= 7 { developerMode = true; versionTaps = 0 }
    }

    private func perform(_ action: DestructiveAction) {
        defer { confirmation = nil }
        switch action {
        case .cache: AppDataReset.clearCaches()
        case .localHistory:
            goals.deleteAllLocalGoals()
            sessions.deleteAllLocalSessionsAndHistory()
            AppDataReset.clearLocalHistory()
        case .reset:
            Task { try? await account.disconnect() }
            telemetry.forgetPairing()
            goals.deleteAllLocalGoals()
            sessions.deleteAllLocalSessionsAndHistory()
            AppDataReset.resetDefaults()
            onboardingCompleted = false
        }
    }
}

private enum DestructiveAction: Equatable {
    case cache, localHistory, reset
    var title: String { self == .cache ? "Clear cached game data?" : self == .localHistory ? "Delete goals and history?" : "Reset GW2 Companion?" }
    var button: String { self == .cache ? "Clear Cache" : self == .localHistory ? "Delete Goals & History" : "Reset App" }
    var message: String {
        switch self {
        case .cache: "Downloaded metadata and images will be removed. Your API key, PC pairing, goals, and history are kept."
        case .localHistory: "Local goals, sessions, and history will be permanently deleted. Account and PC connections are kept."
        case .reset: "This removes the API key, PC pairing, caches, local goals, sessions, and preferences."
        }
    }
}

enum AppDataReset {
    static func clearCaches(fileManager: FileManager = .default) {
        guard let root = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        for name in ["GW2CompanionMetadata", "GW2MapIcons-v1"] {
            try? fileManager.removeItem(at: root.appending(path: name, directoryHint: .isDirectory))
        }
    }

    static func clearLocalHistory(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where
            key.hasPrefix("phase4.goals.v1.") || key.hasPrefix("phase5.session.v1.") {
            defaults.removeObject(forKey: key)
        }
    }

    static func resetDefaults(defaults: UserDefaults = .standard) {
        clearCaches()
        for key in defaults.dictionaryRepresentation().keys { defaults.removeObject(forKey: key) }
    }
}

enum AppBuildInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown" }
    static var versionAndBuild: String { "Version \(version) (\(build))" }
}

struct PermissionDetailsView: View {
    @EnvironmentObject private var account: AccountStore
    var body: some View {
        List {
            ForEach(AccountPermission.allCases, id: \.rawValue) { permission in
                PermissionRow(permission: permission, granted: account.permissions.contains(permission))
            }
        }
        .navigationTitle("API Permissions")
    }
}

private struct PermissionRow: View {
    let permission: AccountPermission
    let granted: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(permission.title, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? Color.primary : Color.orange)
            if !granted { Text(permission.affectedFeatures).font(.caption).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(permission.title), \(granted ? "granted" : "missing"). \(granted ? "" : permission.affectedFeatures)")
    }
}

extension AccountPermission {
    var affectedFeatures: String {
        switch self {
        case .account: "Affects account identity and account-wide status."
        case .characters: "Affects the character roster."
        case .inventories: "Affects character inventories, bank, material storage, and shared inventory."
        case .builds: "Affects equipment and build tabs."
        case .wallet: "Affects wallet balances."
        case .progression: "Affects achievements, Wizard’s Vault, and daily or weekly completion."
        case .unlocks: "Affects recipes, skins, and mini unlocks."
        case .tradingPost: "Not currently used by GW2 Companion."
        }
    }
}
