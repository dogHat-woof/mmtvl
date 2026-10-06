import Foundation

/// What Match Guide sets for one channel (M6b L6).
nonisolated enum GuideMatchChoice: Hashable, Sendable {
    /// No override: the automatic rules (M4 L6).
    case automatic
    /// Override "": no guide data.
    case none
    case epg(EPGRef)
}

/// One guide channel offered by Match Guide (M6b L9).
nonisolated struct GuideCandidate: Identifiable, Equatable, Sendable {
    var ref: EPGRef
    /// First display name, else the EPG id.
    var name: String
    /// GuideSource.shortLabel.
    var sourceLabel: String
    var id: EPGRef { ref }
}

/// What the Match Guide menu shows for one channel (M6b L9).
nonisolated struct GuideMatchOptions: Equatable, Sendable {
    /// .automatic (no override applies), .none (""), .epg(current) (an override that resolved).
    var choice: GuideMatchChoice
    /// The channel's match in use (library.epgMatches).
    var current: EPGRef?
    /// The current match first, then the suggestions without it.
    var candidates: [GuideCandidate]
}
