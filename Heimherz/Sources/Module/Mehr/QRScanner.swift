import SwiftUI
import VisionKit

/// Liest QR-Codes mit der Kamera (`DataScannerViewController`). Meldet jeden neu erkannten Code als Text.
/// Im Simulator und ohne Kamera-Erlaubnis gibt es keinen Scanner (`istMoeglich` ist falsch): dann bleibt das Einfügen.
struct QRScanner: UIViewControllerRepresentable {
    let beiCode: (String) -> Void

    static var istMoeglich: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Koordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Koordinator { Koordinator(beiCode: beiCode) }

    @MainActor final class Koordinator: NSObject, DataScannerViewControllerDelegate {
        let beiCode: (String) -> Void

        init(beiCode: @escaping (String) -> Void) {
            self.beiCode = beiCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let code) = item, let text = code.payloadStringValue {
                    beiCode(text)
                    return
                }
            }
        }
    }
}
