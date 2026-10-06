import AppKit
import SwiftUI

/// The phone remote's home-screen icon: the `Logo` asset scaled to a size (M7b L10).
enum PhoneRemoteIcon {
    private static var cache: [Int: Data] = [:]

    /// PNG data, rendered once per size with ImageRenderer (scale 1) and cached.
    static func png(size: Int) -> Data? {
        if let data = cache[size] { return data }
        let renderer = ImageRenderer(content:
            Image("Logo")
                .resizable()
                .interpolation(.high)
                .frame(width: CGFloat(size), height: CGFloat(size))
        )
        renderer.scale = 1
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return nil }
        cache[size] = data
        return data
    }
}
