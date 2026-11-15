import Foundation
import Testing
@testable import MMTVL

/// M6b L2: labels show a guide file's name, never a query or a token-like path segment.
struct GuideSourceTests {
    @Test func guideFileName() {
        let source = GuideSource(url: URL(string: "https://guide-source.online/guide-source/guide-source_US2.xml.gz")!, isFromPlaylist: false)
        #expect(source.label == "guide-source.online · guide-source_US2.xml.gz")
        #expect(source.shortLabel == "guide-source_US2")
        #expect(source.id == IPTVLibrary.hash(source.url))
    }

    @Test func queryIsNeverShown() {
        let source = GuideSource(url: URL(string: "https://host.example/xmltv.php?username=u&password=p")!, isFromPlaylist: true)
        #expect(source.label == "host.example")
        #expect(source.shortLabel == "host.example")
    }

    @Test func tokenLikePathIsNotShown() {
        let source = GuideSource(url: URL(string: "https://provider.example/app2/abcdefghij12345678")!, isFromPlaylist: false)
        #expect(source.label == "provider.example")
        #expect(source.shortLabel == "provider.example")
    }

    @Test func longFileNameIsNotShown() {
        let name = String(repeating: "a", count: 66) + ".xml"
        let source = GuideSource(url: URL(string: "https://guide.example/\(name)")!, isFromPlaylist: false)
        #expect(source.label == "guide.example")
    }

    @Test func plainXML() {
        let source = GuideSource(url: URL(string: "https://guide.example/custom.xml")!, isFromPlaylist: false)
        #expect(source.label == "guide.example · custom.xml")
        #expect(source.shortLabel == "custom")
    }

    /// M7j L10: SiliconDust's guide URL (its query is a token) labels as the host only, and its id is the bare
    /// endpoint's hash, never the tokened URL's.
    @Test func antennaGuideURLShowsTheHostOnly() {
        let source = GuideSource(url: AntennaFixtures.guideURL, isFromPlaylist: false)
        #expect(source.label == "api.hdhomerun.com")
        #expect(source.shortLabel == "api.hdhomerun.com")
        #expect(source.id != AntennaGuide.sourceID)
        #expect(GuideSource(url: AntennaGuide.endpoint, isFromPlaylist: false).id == AntennaGuide.sourceID)
    }
}
