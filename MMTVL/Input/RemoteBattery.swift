import Foundation
import IOKit.ps
import os

/// M7f L8: the Siri Remote's battery, from macOS's accessory power sources.
/// The public `IOPSCopyPowerSourcesInfo` lists only internal batteries and UPSs; the private
/// `IOPSCopyPowerSourcesByType(0)` (exported by IOKit, reached with `dlsym`) also lists Bluetooth accessories.
/// The remote is matched by vendor and product id, never by name or serial number (the name is the serial).
nonisolated enum RemoteBattery {
    /// Apple's Siri Remote product ids (its driver's ProductIDArray), vendor 76.
    static let productIDs: Set<Int> = [614, 621, 788, 789]
    static let appleVendorID = 76

    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "RemoteBattery")

    /// The lowest percent of every connected Siri Remote; nil without one.
    static func level(from descriptions: [[String: Any]]) -> Int? {
        descriptions.compactMap { description -> Int? in
            guard description[kIOPSTypeKey] as? String == "Accessory Source",
                  intValue(description["Vendor ID"]) == appleVendorID,
                  let product = intValue(description["Product ID"]), productIDs.contains(product),
                  let current = intValue(description[kIOPSCurrentCapacityKey]),
                  let max = intValue(description[kIOPSMaxCapacityKey]), max > 0
            else { return nil }
            let percent = (Double(current) * 100 / Double(max)).rounded()
            return Int(Swift.min(Swift.max(percent, 0), 100))
        }.min()
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int: int
        case let number as NSNumber: number.intValue
        default: nil
        }
    }

    private typealias CopyByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?

    private static let copyByType: CopyByType? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "IOPSCopyPowerSourcesByType") else {
            logger.notice("IOPSCopyPowerSourcesByType not found; no remote battery")
            return nil
        }
        return unsafeBitCast(symbol, to: CopyByType.self)
    }()

    private static let firstReadLogged = OSAllocatedUnfairLock(initialState: false)

    /// Reads the private IOPSCopyPowerSourcesByType(0) through dlsym, then the public
    /// IOPSGetPowerSourceDescription. nil when the symbol is missing or nothing matches.
    static func current() -> Int? {
        guard let copyByType, let blob = copyByType(0)?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        let descriptions = list.compactMap {
            IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any]
        }
        let level = level(from: descriptions)
        if let level, firstReadLogged.withLock({ logged in defer { logged = true }; return !logged }) {
            logger.notice("Siri Remote battery \(level)%")
        }
        return level
    }
}
