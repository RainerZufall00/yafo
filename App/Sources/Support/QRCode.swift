import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI
import VisionKit

/// QR-Code als Bild, immer schwarz auf weiß (auch im Dunkelmodus), damit Kameras ihn sicher lesen.
struct QRCodeImage: View {
    let text: String

    var body: some View {
        if let image = Self.make(text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityLabel(Text("QR code"))
        }
    }

    private static func make(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// Kamerabild, das QR-Codes erkennt (`DataScannerViewController`). Meldet jeden gelesenen Text;
/// ob er etwas taugt, entscheidet der Aufrufer.
struct QRScanner: UIViewControllerRepresentable {
    enum Access {
        case granted
        /// Zugriff abgelehnt oder eingeschränkt: in den Einstellungen änderbar.
        case denied
        /// Gerät ohne passende Kamera (Simulator, Mac).
        case unsupported
    }

    let onScan: (String) -> Void

    /// Fragt beim ersten Mal nach der Kamera.
    static func requestAccess() async -> Access {
        guard DataScannerViewController.isSupported else { return .unsupported }
        guard await AVCaptureDevice.requestAccess(for: .video), DataScannerViewController.isAvailable else {
            return .denied
        }
        return .granted
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced,
                                                recognizesMultipleItems: false,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for case .barcode(let barcode) in addedItems {
                if let text = barcode.payloadStringValue { onScan(text) }
            }
        }
    }
}
