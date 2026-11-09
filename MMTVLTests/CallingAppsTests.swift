import Testing
@testable import MMTVL

struct CallingAppsTests {
    @Test(arguments: ["meet.google.com", "us02web.zoom.us", "teams.microsoft.com", "MEET.GOOGLE.COM", "zoom.us"])
    func callingHosts(host: String) {
        #expect(CallingApps.isCalling(host: host))
    }

    @Test(arguments: ["mail.google.com", "notzoom.us", "youtube.com", "google.com", ""])
    func otherHosts(host: String) {
        #expect(!CallingApps.isCalling(host: host))
    }
}
