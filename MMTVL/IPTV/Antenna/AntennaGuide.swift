import Foundation

// M7j step 8 (L10, L11, L12): the antenna channels' guide, SiliconDust's free XMLTV service (2 days). Its URL carries
// the tuners' DeviceAuth, a token: it's built at import time from a fresh `discover.json`, held in a local, and
// never logged, stored (the guide's id is the hash of the bare endpoint) or shown. Only the host is logged.

nonisolated enum AntennaGuide {
    /// SiliconDust's XMLTV endpoint, without the query.
    static let endpoint = URL(string: "https://api.hdhomerun.com/api/xmltv")!
    /// The guide's id in `guide.sqlite` and `iptv-state.json`: the endpoint's hash, so no token is in it.
    static let sourceID = IPTVLibrary.hash(endpoint)
    /// Match Guide's label for its channels.
    static let label = "HDHomeRun"

    /// After a failure, the next try.
    static let retryAfterFailure: TimeInterval = 3600
    /// Refresh Now imports it only when the last import is older than this.
    static let minimumManualInterval: TimeInterval = 3600
    /// The next download is this many hours after a success, uniformly at random (SiliconDust asks for 20–28 h).
    static let nextDueHours: ClosedRange<Double> = 20...28

    /// Security L3: the largest body MMTVL keeps (URLSession has already undone its gzip, so this is the XML; the
    /// real 2-day file is 7.2 MB) and the largest gunzipped file (if it's served as a raw `.gz`).
    static let maximumDownloadBytes = 64 * 1024 * 1024
    static let maximumUnzippedBytes = 64 * 1024 * 1024

    /// One tuner's DeviceAuth is at most this long (the user's tuner sends 24 characters).
    static let maximumDeviceAuthLength = 64
    /// And at least this long.
    static let minimumDeviceAuthLength = 8
    /// Base64 and its URL-safe form (step 2 security L5): anything else means no download.
    private static let deviceAuthCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=_-".utf8)
    /// Only ASCII letters and digits are left as they are in the query; `+`, `/`, `=` and the rest are
    /// percent-encoded (`URLComponents` would leave `+`, which a server reads as a space).
    private static let unreservedInQuery = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")

    /// Step 2 security L5: a DeviceAuth MMTVL puts in the query is 8…64 ASCII base64 (or URL-safe base64)
    /// characters.
    static func isValidDeviceAuth(_ auth: String) -> Bool {
        (minimumDeviceAuthLength...maximumDeviceAuthLength).contains(auth.utf8.count)
            && auth.utf8.allSatisfy { deviceAuthCharacters.contains($0) }
    }

    /// `https://api.hdhomerun.com/api/xmltv?DeviceAuth=<every tuner's DeviceAuth, concatenated in the given (DeviceID)
    /// order, percent-encoded>`; nil when there is none or any of them isn't valid (`isValidDeviceAuth`). A token:
    /// never log, store or show the result.
    static func url(deviceAuths: [String]) -> URL? {
        guard !deviceAuths.isEmpty, deviceAuths.allSatisfy(isValidDeviceAuth),
              let encoded = deviceAuths.joined().addingPercentEncoding(withAllowedCharacters: unreservedInQuery)
        else { return nil }
        return URL(string: endpoint.absoluteString + "?DeviceAuth=" + encoded)
    }

    /// 20–28 hours after `date`; `random` gives a number in 0..<1.
    static func nextDue(after date: Date, random: () -> Double = { Double.random(in: 0..<1) }) -> Date {
        let fraction = min(max(random(), 0), 1)
        let hours = nextDueHours.lowerBound + (nextDueHours.upperBound - nextDueHours.lowerBound) * fraction
        return date.addingTimeInterval(hours * 3600)
    }

    /// The override for `channel` (L12: its id `antenna:5.1`, then its name, ignoring case), lowercased; "" means no
    /// guide. `overrides` keys are as read from `epg-overrides.json`.
    static func overrideTarget(for channel: Channel, in overrides: [String: String]) -> String? {
        guard !overrides.isEmpty else { return nil }
        var lower: [String: String] = [:]
        for (key, value) in overrides { lower[key.lowercased()] = value.lowercased() }
        return lower[channel.overrideKey.lowercased()] ?? lower[channel.name.lowercased()]
    }

    /// L10: antenna channels → the guide's channel ids (lowercased), the first rule that hits:
    /// 1. an override (`overrideTarget`) naming a channel in this guide ("" = no guide);
    /// 2. a display-name exactly equal to the channel's GuideNumber ("5.1");
    /// 3. the channel's normalized name equal to a normalized display-name, only when no other antenna channel has
    ///    that name, and only against guide channels no other lineup channel claims by number (none of their
    ///    display-names is another antenna channel's GuideNumber), so a channel without its own guide channel never
    ///    gets another station's listings.
    static func match(_ antennaChannels: [Channel], to epgChannels: [EPGChannel],
                      overrides: [String: String] = [:]) -> [Channel.ID: String] {
        var ids: Set<String> = []
        var byNumber: [String: String] = [:]
        for epg in epgChannels {
            let id = epg.id.lowercased()
            ids.insert(id)
            for name in epg.names {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if byNumber[trimmed] == nil { byNumber[trimmed] = id }
            }
        }
        let numbers = Set(antennaChannels.compactMap(\.guideNumber))
        // Security L4: each display-name normalized (and trimmed) once, not once per antenna channel.
        let normalizedNames = epgChannels.map { Set($0.names.map(EPGMatcher.normalize)) }
        let trimmedNames = epgChannels.map { $0.names.map { $0.trimmingCharacters(in: .whitespaces) } }
        var nameCounts: [String: Int] = [:]
        for channel in antennaChannels {
            let key = EPGMatcher.normalize(channel.name)
            if !key.isEmpty { nameCounts[key, default: 0] += 1 }
        }

        var result: [Channel.ID: String] = [:]
        for channel in antennaChannels {
            // 1.
            if let target = overrideTarget(for: channel, in: overrides) {
                if target.isEmpty { continue }
                if ids.contains(target) {
                    result[channel.id] = target
                    continue
                }
            }
            // 2.
            if let number = channel.guideNumber, let id = byNumber[number] {
                result[channel.id] = id
                continue
            }
            // 3.
            let key = EPGMatcher.normalize(channel.name)
            guard !key.isEmpty, nameCounts[key] == 1 else { continue }
            let own = channel.guideNumber
            let candidate = epgChannels.indices.first { index in
                normalizedNames[index].contains(key)
                    && !trimmedNames[index].contains { $0 != own && numbers.contains($0) }
            }
            if let candidate { result[channel.id] = epgChannels[candidate].id.lowercased() }
        }
        return result
    }
}
