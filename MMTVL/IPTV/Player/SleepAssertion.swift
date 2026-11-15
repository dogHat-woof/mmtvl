import IOKit.pwr_mgt
import os

/// Keeps the display awake while Live TV plays (L15). M7m L23: also, with the system-sleep type, keeps the Mac awake
/// from Power-off to Power-on (`PowerEffects.system`). M7m L24: and, in kiosk mode, for MMTVL's whole run
/// (`AppDelegate`), whoever turned the TV off.
final class SleepAssertion {
    private let logger: Logger
    private let type: String
    private let name: String
    private var assertionID: IOPMAssertionID?

    /// The defaults are Live TV's display-sleep assertion. `category`: where a failure is logged.
    init(type: String = kIOPMAssertionTypePreventUserIdleDisplaySleep, name: String = "MMTVL Live TV",
         category: String = "IPTV") {
        self.type = type
        self.name = name
        logger = Logger(subsystem: "dev.mmtvl.launcher", category: category)
    }

    /// Idempotent. Returns whether an assertion is held now (false after a failed create, or after releasing).
    @discardableResult
    func hold(_ on: Bool) -> Bool {
        if on, assertionID == nil {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                name as CFString,
                &id)
            if result == kIOReturnSuccess {
                assertionID = id
            } else {
                // The type and name are fixed strings (nothing from input or the network).
                logger.error("\(self.type, privacy: .public) assertion failed: \(result)")
            }
        } else if !on, let id = assertionID {
            IOPMAssertionRelease(id)
            assertionID = nil
        }
        return assertionID != nil
    }
}
