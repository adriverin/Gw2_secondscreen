import SwiftUI

struct OnboardingFlow: View {
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var telemetry: TelemetryStore
    @EnvironmentObject private var navigation: AppNavigation
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarding.completed.v1") private var completed = false
    @State private var step = 0
    @State private var showingPairing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 12)
                switch step {
                case 0: welcome
                case 1: accountStep
                case 2: pcStep
                default: readyStep
                }
                Spacer()
            }
            .frame(maxWidth: 620)
            .padding(28)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground).ignoresSafeArea())
            .sheet(isPresented: $showingPairing) { PairingView(onConnected: { step = 3 }) }
        }
        .interactiveDismissDisabled()
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Image(systemName: "map.fill").font(.system(size: 72)).foregroundStyle(GWPalette.accent)
                .accessibilityHidden(true)
            Text("Welcome to GW2 Companion").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("Your second screen for Tyria.").font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14) {
                onboardingRow(1, "Connect your Guild Wars 2 account")
                onboardingRow(2, "Connect your gaming PC")
                onboardingRow(3, "Start playing")
            }
            .padding(.vertical)
            Button("Get Started") { step = 1 }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(GWPalette.accent)
        }
    }

    private var accountStep: some View {
        AccountSetupForm {
            step = 2
        } skip: {
            step = 2
        }
    }

    private var pcStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "desktopcomputer").font(.system(size: 58)).foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Connect Your Gaming PC").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("Guild Wars 2 does not expose live player position through its web API. GW2 Companion Bridge reads the game’s official MumbleLink telemetry locally and sends it to this device over your home network.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 9) {
                Label("No game automation", systemImage: "checkmark.shield")
                Label("No packet interception", systemImage: "checkmark.shield")
                Label("No API key sent to the PC", systemImage: "checkmark.shield")
                Label("No cloud server", systemImage: "checkmark.shield")
            }
            Button("Scan Bridge QR Code") { showingPairing = true }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(.orange)
            Button("Enter Details Manually") { showingPairing = true }.buttonStyle(.bordered)
            Button("Skip for Now") { step = 3 }.foregroundStyle(.secondary)
        }
    }

    private var readyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 68)).foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Ready for Tyria").font(.largeTitle.bold())
            Text(summaryText).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Start Using GW2 Companion") { finish() }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(GWPalette.accent)
        }
    }

    private var summaryText: String {
        if account.connectionState == .connected && telemetry.savedPairing != nil {
            return "Your account and gaming PC are connected. Launch Guild Wars 2 to see your live position."
        }
        if account.connectionState == .connected { return "Your account is connected. You can add live position from Settings whenever you’re ready." }
        if telemetry.savedPairing != nil { return "Your gaming PC is paired. Account features can be added later from Settings." }
        return "You can browse the map now and connect your account or PC later from Settings."
    }

    private func onboardingRow(_ number: Int, _ title: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)").font(.headline).frame(width: 34, height: 34).background(GWPalette.accent.opacity(0.18), in: Circle())
            Text(title).font(.headline)
        }
        .accessibilityElement(children: .combine)
    }

    private func finish() {
        navigation.selectedTab = account.connectionState == .connected && telemetry.savedPairing == nil ? .session : .map
        completed = true
        dismiss()
    }
}

struct AccountSetupForm: View {
    @EnvironmentObject private var account: AccountStore
    @State private var apiKey = ""
    @State private var isChecking = false
    @State private var errorMessage: String?
    @State private var showingHelp = false
    let connected: () -> Void
    var skip: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 58)).foregroundStyle(GWPalette.accent)
                    .accessibilityHidden(true)
                Text("Connect Your Guild Wars 2 Account").font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text("Your API key lets the app show characters, inventory, builds, equipment, Wizard’s Vault, goals, and crafting progress.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("Your key is stored only in this device’s Keychain. It is never sent to the Windows bridge.")
                    .font(.subheadline).multilineTextAlignment(.center)
                SecureField("ArenaNet API key", text: $apiKey)
                    .textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("ArenaNet API key")
                Button { Task { await validate() } } label: {
                    if isChecking { ProgressView("Checking key…").frame(maxWidth: .infinity) }
                    else { Text("Enter API Key").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(apiKey.isEmpty || isChecking)
                Button("How to Create an API Key") { showingHelp = true }
                if let errorMessage { GWErrorBanner(message: errorMessage, stale: false) }
                if let skip { Button("Skip for Now", action: skip).foregroundStyle(.secondary) }
            }
        }
        .sheet(isPresented: $showingHelp) { APIKeyHelpView() }
    }

    private func validate() async {
        isChecking = true
        defer { isChecking = false }
        do {
            try await account.connect(apiKey: apiKey)
            apiKey = ""
            errorMessage = nil
            connected()
        } catch {
            errorMessage = error.userFacingMessage(fallback: "The API key could not be checked. Try again.")
        }
    }
}

struct APIKeyHelpView: View {
    @Environment(\.dismiss) private var dismiss
    private let recommended: [AccountPermission] = [.account, .characters, .inventories, .builds, .progression, .unlocks, .wallet]

    var body: some View {
        NavigationStack {
            List {
                Section("Create a key") {
                    Text("Open ArenaNet’s Applications page, create a new key, and enable the permissions below. Paste the key back into GW2 Companion.")
                    Link("Open ArenaNet Applications", destination: URL(string: "https://account.arena.net/applications")!)
                }
                Section {
                    ForEach(recommended) { permission in
                        HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text(permission.rawValue).textSelection(.enabled) }
                            .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Recommended permissions")
                } footer: {
                    Text("Trading Post account history is not used, so the tradingpost permission is not requested.")
                }
            }
            .navigationTitle("API Key Help")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
