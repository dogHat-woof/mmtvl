import IOKit.pwr_mgt
import os

/// Keeps the display awake while Live TV plays (L15).
final class SleepAssertion {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "IPTV")
    private var assertionID: IOPMAssertionID?

    /// Idempotent.
    func hold(_ on: Bool) {
        if on, assertionID == nil {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "MMTVL Live TV" as CFString,
                &id)
            if result == kIOReturnSuccess {
                assertionID = id
            } else {
                Self.logger.error("Display sleep assertion failed: \(result)")
            }
        } else if !on, let id = assertionID {
            IOPMAssertionRelease(id)
            assertionID = nil
        }
    }
}
