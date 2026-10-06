import CoreImage
import CoreImage.CIFilterBuiltins

/// QR codes for the phone pairing page (M5).
nonisolated enum QRCodeImage {
    static let scale: CGFloat = 10

    /// CIContext is thread-safe; one shared context avoids rebuilding it on every render.
    nonisolated(unsafe) private static let context = CIContext()

    /// Black modules on white, nearest-neighbor scaled ×10, no extra quiet zone (the view pads it).
    static func make(_ string: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(scaled, from: scaled.extent)
    }
}
