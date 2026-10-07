import Foundation
import Testing
@testable import MMTVL

struct AirPlayReceiverProbeTests {
    @Test func verifiedHead() {
        let head = "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nServer: AirTunes/980.77.5\r\nX-Apple-ProcessingTime: 0\r\n\r\n"
        #expect(AirPlayReceiverProbe.isAirPlayResponse(Data(head.utf8)))
    }

    @Test func lowercaseHeaderName() {
        #expect(AirPlayReceiverProbe.isAirPlayResponse(Data("HTTP/1.1 200 OK\r\nserver: airtunes/1.0\r\n\r\n".utf8)))
    }

    @Test func otherServers() {
        #expect(!AirPlayReceiverProbe.isAirPlayResponse(Data("HTTP/1.1 200 OK\r\nServer: nginx\r\n\r\n".utf8)))
        #expect(!AirPlayReceiverProbe.isAirPlayResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8)))
    }

    @Test func garbage() {
        #expect(!AirPlayReceiverProbe.isAirPlayResponse(Data([0xFF, 0x00, 0x13])))
        #expect(!AirPlayReceiverProbe.isAirPlayResponse(Data()))
    }
}
