import AppKit
import CoreGraphics

/// M7n step 4a: the refresh rate of the screen a Live TV player's video is on, for mpv's `display-fps-override`.
/// With the render API mpv isn't told the display's rate, so `video-sync=display-resample` falls back to audio timing
/// unless MMTVL sets it (step 3b: 59.94 fps video on a 60.00 Hz screen repeated a frame every ~16.7 s).
nonisolated enum DisplayRefresh {
    /// Rates mpv is given; anything else (0, NaN, absurd) sets no override.
    static let usableRange = 1.0...240.0

    /// The display mode's rate (exact, e.g. 59.94) when usable, else `NSScreen.maximumFramesPerSecond` when usable
    /// (displays whose mode reports 0), else nil.
    static func usableRate(modeRate: Double, maximumFPS: Int) -> Double? {
        if modeRate.isFinite, usableRange.contains(modeRate) { return modeRate }
        let fallback = Double(maximumFPS)
        return usableRange.contains(fallback) ? fallback : nil
    }

    /// The value for mpv's `display-fps-override`: the rate, or "0" (mpv's default: no override) for nil.
    static func overrideValue(for rate: Double?) -> String {
        rate.map { "\($0)" } ?? "0"
    }

    /// The screen's usable rate, from its current display mode, else its maximum frames per second.
    @MainActor static func rate(of screen: NSScreen) -> Double? {
        let modeRate: Double
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
           let mode = CGDisplayCopyDisplayMode(CGDirectDisplayID(number.uint32Value)) {
            modeRate = mode.refreshRate
        } else {
            modeRate = 0
        }
        return usableRate(modeRate: modeRate, maximumFPS: screen.maximumFramesPerSecond)
    }
}
