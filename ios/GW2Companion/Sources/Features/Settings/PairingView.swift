import SwiftUI
import VisionKit
import AVFoundation

struct PairingView: View {
    @EnvironmentObject private var telemetry: TelemetryStore
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var port = "38291"
    @State private var token = ""
    @State private var errorMessage: String?
    @State private var showingScanner = false
    var onConnected: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { requestCameraAndScan() } label: { Label("Scan Bridge QR Code", systemImage: "qrcode.viewfinder") }
                        .disabled(!DataScannerViewController.isSupported || !DataScannerViewController.isAvailable)
                } footer: {
                    Text(DataScannerViewController.isSupported && DataScannerViewController.isAvailable
                         ? "The bridge and iPhone must be on the same local network."
                         : "QR scanning is unavailable on this device. Enter the bridge details manually.")
                }
                Section("Manual connection") {
                    TextField("PC IP address", text: $host).textInputAutocapitalization(.never).keyboardType(.numbersAndPunctuation)
                    TextField("Port", text: $port).keyboardType(.numberPad)
                    SecureField("Pairing token", text: $token)
                        .textContentType(.oneTimeCode)
                        .textInputAutocapitalization(.never)
                    Button("Connect to PC") { connect() }
                }
                if UserDefaults.standard.bool(forKey: "developer.mode.enabled") {
                Section("Developer") {
                    if telemetry.isSimulating {
                        Button("Stop simulated movement") { telemetry.stopSimulation(); dismiss() }
                    } else {
                        Button("Start simulated movement") { telemetry.startSimulation(); dismiss() }
                    }
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
                        onConnected?()
                        dismiss()
                    } catch { errorMessage = error.userFacingMessage(fallback: "That QR code could not be read."); showingScanner = false }
                } onError: { message in
                    errorMessage = message
                    showingScanner = false
                }
                .ignoresSafeArea()
            }
        }
    }

    private func connect() {
        guard let portValue = Int(port) else { errorMessage = "Enter a valid port."; return }
        do {
            try telemetry.pair(BridgePairing(host: host, port: portValue, token: token))
            onConnected?()
            dismiss()
        } catch { errorMessage = error.userFacingMessage(fallback: "Can’t connect to your gaming PC. Check the connection details and try again.") }
    }

    private func requestCameraAndScan() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: showingScanner = true
        case .notDetermined:
            Task {
                if await AVCaptureDevice.requestAccess(for: .video) { showingScanner = true }
                else { errorMessage = "Camera access is off. Enable it in Settings, or enter the bridge details manually." }
            }
        case .denied, .restricted:
            errorMessage = "Camera access is off. Enable it in Settings, or enter the bridge details manually."
        @unknown default:
            errorMessage = "The camera is unavailable. Enter the bridge details manually."
        }
    }
}
