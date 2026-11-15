import Foundation

// M7j step 3 (L1, L2, L5): the tuners' lineups as Live TV channels.

nonisolated enum AntennaLineup {
    /// Every antenna channel's group (L2, L3).
    static let group = "Antenna"
    /// An antenna channel's id is this plus its GuideNumber (`antenna:5.1`, L1).
    static let idPrefix = "antenna:"
    /// A GuideNumber's major and minor parts are at most this many digits each.
    static let maximumNumberDigits = 5
    /// At most this many entries are kept per device (security low 3); later ones are dropped uncounted.
    static let maximumChannelsPerDevice = 1000

    /// The channels of `devices`' lineups, in GuideNumber order, numbered from `firstNumber` (the playlist's count
    /// + 1, L2).
    ///
    /// - Devices are taken in DeviceID order, and the first one carrying a GuideNumber in a kept entry wins (L1);
    ///   within a lineup, the first kept entry with a number wins.
    /// - An entry is kept when its GuideNumber is `<digits>` or `<digits>.<digits>`, it's available (not
    ///   `Enabled: 0` or `Subscribed: 0`), its `URL` is http on its device's host (`HDHomeRunDevice.isHTTPOnDevice`),
    ///   and it isn't copy protected (L5).
    /// - `leftOut` counts the **protected** (DRM) GuideNumbers no kept entry carries, for Settings' "N protected
    ///   channels left out". Unavailable entries, malformed GuideNumbers and URLs that aren't http on the device's
    ///   host are left out without being counted: they aren't protected channels, and a real tuner never sends
    ///   the last two. So are a device's entries after its first `maximumChannelsPerDevice` kept ones.
    /// - `sharedNumbers` (step 10, security N2) counts the GuideNumbers a later device would also have kept (an
    ///   entry kept by these rules) after an earlier device kept them: the first device's channel is used, and the
    ///   library logs the count.
    static func channels(devices: [(HDHomeRunDevice, [HDHomeRunLineupEntry])],
                         firstNumber: Int) -> (channels: [Channel], leftOut: Int, sharedNumbers: Int) {
        var kept: [String: (entry: HDHomeRunLineupEntry, device: HDHomeRunDevice, url: URL)] = [:]
        var protected = Set<String>()
        var shared = Set<String>()
        for (device, entries) in devices.sorted(by: { $0.0.id < $1.0.id }) {
            var keptOnDevice = 0
            for entry in entries {
                guard keptOnDevice < maximumChannelsPerDevice else { break }
                let number = entry.guideNumber
                guard isGuideNumber(number), entry.isAvailable else { continue }
                if let first = kept[number] {
                    if first.device.id != device.id, !entry.isDRM, let url = URL(string: entry.url),
                       device.isHTTPOnDevice(url) {
                        shared.insert(number)
                    }
                    continue
                }
                if entry.isDRM {
                    protected.insert(number)
                    continue
                }
                guard let url = URL(string: entry.url), device.isHTTPOnDevice(url) else { continue }
                kept[number] = (entry, device, url)
                keptOnDevice += 1
            }
        }
        let numbers = kept.keys.sorted(by: compareGuideNumbers)
        let channels = numbers.enumerated().map { offset, number -> Channel in
            let (entry, device, url) = kept[number]!
            let name = HDHomeRunDiscovery.displayText(entry.guideName)
            return Channel(
                id: idPrefix + number,
                number: firstNumber + offset,
                name: name.isEmpty ? "Channel \(number)" : name,
                group: group,
                tvgID: nil,
                tvgName: nil,
                logoURL: nil,
                streamURL: url,
                source: .antenna(deviceID: device.id),
                guideNumber: number
            )
        }
        return (channels, protected.subtracting(numbers).count, shared.count)
    }

    /// `<major>` or `<major>.<minor>`, ASCII digits only, each part 1…`maximumNumberDigits` long ("5.1", "702").
    /// Anything else is dropped: the number becomes an id and a key in MMTVL's files.
    static func isGuideNumber(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count) else { return false }
        return parts.allSatisfy { part in
            (1...maximumNumberDigits).contains(part.utf8.count) && part.utf8.allSatisfy { (0x30...0x39).contains($0) }
        }
    }

    /// GuideNumber order: numeric major, then numeric minor (2.2 < 2.10 < 4.1; "5" before "5.1"). Text that isn't
    /// a GuideNumber sorts after every number, by its characters.
    static func compareGuideNumbers(_ lhs: String, _ rhs: String) -> Bool {
        switch (parts(lhs), parts(rhs)) {
        case let (left?, right?):
            if left.major != right.major { left.major < right.major }
            else if left.minor != right.minor { (left.minor ?? -1) < (right.minor ?? -1) }
            else { lhs < rhs }   // "5.01" and "5.1": a stable order for numbers that read the same
        case (.some, nil): true
        case (nil, .some): false
        case (nil, nil): lhs < rhs
        }
    }

    private static func parts(_ number: String) -> (major: Int, minor: Int?)? {
        guard isGuideNumber(number) else { return nil }
        let parts = number.split(separator: ".")
        guard let major = Int(parts[0]) else { return nil }
        guard parts.count == 2 else { return (major, nil) }
        guard let minor = Int(parts[1]) else { return nil }
        return (major, minor)
    }
}
