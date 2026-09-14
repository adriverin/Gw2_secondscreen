import SwiftUI
import VisionKit

@available(iOS 16.0, *)
struct PairingScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onError: onError) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        do { try controller.startScanning() }
        catch { onError("The camera could not start. Check Camera access in Settings and try again.") }
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) { }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        let onError: (String) -> Void
        init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onCode = onCode
            self.onError = onError
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case let .barcode(barcode) = item, let value = barcode.payloadStringValue { onCode(value) }
        }
    }
}
