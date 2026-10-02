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
            .background(GWPalette.background.ignoresSafeArea())
            .sheet(isPresented: $showingPairing) { PairingView(onConnected: { finish() }) }
        }
        .interactiveDismissDisabled()
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Image(systemName: "map.fill").font(.system(size: 72)).foregroundStyle(GWPalette.accent)
                .accessibilityHidden(true)
            Text("Your second screen for Tyria").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("Your account knows what you need. Your live map helps you get it.").font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14) {
                onboardingRow(1, "Connect your Guild Wars 2 account")
                onboardingRow(2, "Connect your gaming PC")
                onboardingRow(3, "Start playing")
            }
            .padding(.vertical)
            Button("Get Started") { step = 1 }
                .buttonStyle(GWPrimaryButtonStyle())
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
            Text("Run GW2 Companion Bridge on your gaming PC, then scan its QR code to follow your character live. Both devices use your home network.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            NavigationLink("How your connection stays private") { PrivacySummaryView() }
                .font(.subheadline)
            Button("Scan Bridge QR Code") { showingPairing = true }
                .buttonStyle(GWPrimaryButtonStyle())
            Button("Enter Details Manually") { showingPairing = true }.buttonStyle(.bordered)
            Button("Skip for Now") { finish() }.foregroundStyle(.secondary)
        }
    }

    private var readyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 68)).foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Ready for Tyria").font(.largeTitle.bold())
            Text(summaryText).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Start Using GW2 Companion") { finish() }
                .buttonStyle(GWPrimaryButtonStyle())
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
                .buttonStyle(GWPrimaryButtonStyle()).disabled(apiKey.isEmpty || isChecking)
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
