import SwiftUI
import VisionKit

struct PairingView: View {
    @EnvironmentObject private var telemetry: TelemetryStore
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var port = "38291"
    @State private var token = ""
    @State private var errorMessage: String?
    @State private var showingScanner = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { showingScanner = true } label: { Label("Scan QR code", systemImage: "qrcode.viewfinder") }
                        .disabled(!DataScannerViewController.isSupported || !DataScannerViewController.isAvailable)
                } footer: {
                    Text("The bridge and iPhone must be on the same local network.")
                }
                Section("Manual connection") {
                    TextField("PC IP address", text: $host).textInputAutocapitalization(.never).keyboardType(.numbersAndPunctuation)
                    TextField("Port", text: $port).keyboardType(.numberPad)
                    SecureField("Pairing token", text: $token)
                        .textContentType(.oneTimeCode)
                        .textInputAutocapitalization(.never)
                    Button("Connect to PC") { connect() }
                }
                Section("Developer") {
                    if telemetry.isSimulating {
                        Button("Stop simulated movement") { telemetry.stopSimulation(); dismiss() }
                    } else {
                        Button("Start simulated movement") { telemetry.startSimulation(); dismiss() }
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
                Section { Button("Forget paired PC", role: .destructive) { telemetry.forgetPairing() } }
            }
            .navigationTitle("Connect to PC")
            .toolbar { Button("Done") { dismiss() } }
            .sheet(isPresented: $showingScanner) {
                PairingScannerView { value in
                    do {
                        let pairing = try BridgePairing.decodeQR(value)
                        try telemetry.pair(pairing)
                        showingScanner = false
                        dismiss()
                    } catch { errorMessage = error.localizedDescription; showingScanner = false }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func connect() {
        guard let portValue = Int(port) else { errorMessage = "Enter a valid port."; return }
        do {
            try telemetry.pair(BridgePairing(host: host, port: portValue, token: token))
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
