import Foundation
import Testing
@testable import MMTVL

/// M7h L18: the VIERA SOAP requests (step 1's working path, SOAPACTION and action body) and reply parsing.
struct PanasonicVieraTests {
    private static func envelope(_ action: String) -> String {
        #"<?xml version="1.0" encoding="utf-8"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>"#
            + action + "</s:Body></s:Envelope>"
    }

    private static func reply(_ action: String) -> Data {
        Data("""
            <?xml version="1.0" encoding="utf-8"?>
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
            <s:Body>\(action)</s:Body>
            </s:Envelope>
            """.utf8)
    }

    private static let fault = reply("""
        <s:Fault><faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring><detail>\
        <UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>401</errorCode>\
        <errorDescription>Invalid Action</errorDescription></UPnPError></detail></s:Fault>
        """)

    // MARK: Requests

    @Test func sendKeyMatchesStepOnesRequest() {
        let request = PanasonicViera.sendKey(.power)
        #expect(request.path == "/nrc/control_0")
        #expect(request.headers["SOAPACTION"] == #""urn:panasonic-com:service:p00NetworkControl:1#X_SendKey""#)
        #expect(request.headers["Content-Type"] == #"text/xml; charset="utf-8""#)
        let action = #"<u:X_SendKey xmlns:u="urn:panasonic-com:service:p00NetworkControl:1"><X_KeyEvent>NRC_POWER-ONOFF</X_KeyEvent></u:X_SendKey>"#
        #expect(request.body.contains(action))
        #expect(request.body == Self.envelope(action))
        // QA Q1: compact, like the panasonic_viera library.
        #expect(request.body == #"<?xml version="1.0" encoding="utf-8"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:X_SendKey xmlns:u="urn:panasonic-com:service:p00NetworkControl:1"><X_KeyEvent>NRC_POWER-ONOFF</X_KeyEvent></u:X_SendKey></s:Body></s:Envelope>"#)
        #expect(!request.body.contains("\n"))
    }

    @Test func onlyThePowerKeyExists() {
        #expect(VieraKey.allCases.map(\.rawValue) == ["NRC_POWER-ONOFF"])
    }

    @Test func getVolumeAndGetMuteMatchStepOnesRequests() {
        for (request, action) in [(PanasonicViera.getVolume, "GetVolume"), (PanasonicViera.getMute, "GetMute")] {
            #expect(request.path == "/dmr/control_0")
            #expect(request.headers["SOAPACTION"] == "\"urn:schemas-upnp-org:service:RenderingControl:1#\(action)\"")
            let body = "<u:\(action) xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\"><InstanceID>0</InstanceID><Channel>Master</Channel></u:\(action)>"
            #expect(request.body == Self.envelope(body))
        }
    }

    @Test func urlRequestIsAPOSTToPort55000() throws {
        let request = try #require(PanasonicViera.sendKey(.power).urlRequest(address: "192.168.1.30", timeout: 2))
        #expect(request.url?.absoluteString == "http://192.168.1.30:55000/nrc/control_0")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "SOAPACTION") == #""urn:panasonic-com:service:p00NetworkControl:1#X_SendKey""#)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == #"text/xml; charset="utf-8""#)
        #expect(request.httpBody == Data(PanasonicViera.sendKey(.power).body.utf8))
        #expect(request.timeoutInterval == 2)
    }

    /// Only a LAN IPv4 literal (the address the connection check reached).
    @Test func urlRequestNeedsALANIPv4Address() {
        for address in ["8.8.8.8", "127.0.0.1", "tv.local", "fe80::1", "192.168.1.30/x", "192.168.1.30:80", "", "evil.com"] {
            #expect(PanasonicViera.getVolume.urlRequest(address: address, timeout: 2) == nil, "\(address)")
        }
    }

    // MARK: Replies

    @Test func volumeAndMuteParse() throws {
        let volume = Self.reply(#"<u:GetVolumeResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1"><CurrentVolume>12</CurrentVolume></u:GetVolumeResponse>"#)
        #expect(try PanasonicViera.parseVolume(status: 200, body: volume) == 12)
        let mute = Self.reply(#"<u:GetMuteResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1"><CurrentMute>0</CurrentMute></u:GetMuteResponse>"#)
        #expect(try PanasonicViera.parseMute(status: 200, body: mute) == false)
        let muted = Self.reply("<u:GetMuteResponse><CurrentMute>1</CurrentMute></u:GetMuteResponse>")
        #expect(try PanasonicViera.parseMute(status: 200, body: muted) == true)
        let sendKey = Self.reply(#"<u:X_SendKeyResponse xmlns:u="urn:panasonic-com:service:p00NetworkControl:1"></u:X_SendKeyResponse>"#)
        #expect(throws: Never.self) { try PanasonicViera.parseSendKey(status: 200, body: sendKey) }
        // QA Q3: any 200 without a fault is success, whatever the body.
        #expect(throws: Never.self) { try PanasonicViera.parseSendKey(status: 200, body: Data()) }
        #expect(throws: Never.self) { try PanasonicViera.parseSendKey(status: 200, body: Data("OK".utf8)) }
    }

    @Test func aFaultIsAnError() {
        let expected = VieraError.fault(code: "401", description: "Invalid Action")
        #expect(throws: expected) { try PanasonicViera.parseSendKey(status: 500, body: Self.fault) }
        #expect(throws: expected) { try PanasonicViera.parseVolume(status: 500, body: Self.fault) }
        #expect(throws: expected) { try PanasonicViera.parseMute(status: 200, body: Self.fault) }
        let plain = Self.reply("<s:Fault><faultcode>s:Server</faultcode><faultstring>Busy</faultstring></s:Fault>")
        #expect(throws: VieraError.fault(code: "s:Server", description: "Busy")) {
            try PanasonicViera.parseSendKey(status: 500, body: plain)
        }
    }

    @Test func otherRepliesAreErrors() {
        let volume = Self.reply("<u:GetVolumeResponse><CurrentVolume>12</CurrentVolume></u:GetVolumeResponse>")
        #expect(throws: VieraError.status(404)) { try PanasonicViera.parseVolume(status: 404, body: volume) }
        #expect(throws: VieraError.badResponse) { try PanasonicViera.parseVolume(status: 200, body: Data("12".utf8)) }
        #expect(throws: VieraError.status(500)) { try PanasonicViera.parseSendKey(status: 500, body: Data()) }
        for bad in ["", "-1", "101", "loud"] {
            let body = Self.reply("<u:GetVolumeResponse><CurrentVolume>\(bad)</CurrentVolume></u:GetVolumeResponse>")
            #expect(throws: VieraError.badResponse) { try PanasonicViera.parseVolume(status: 200, body: body) }
        }
        let mute = Self.reply("<u:GetMuteResponse><CurrentMute>maybe</CurrentMute></u:GetMuteResponse>")
        #expect(throws: VieraError.badResponse) { try PanasonicViera.parseMute(status: 200, body: mute) }
        let huge = Data(repeating: 0x20, count: PanasonicViera.maximumResponseSize + 1)
        #expect(throws: VieraError.badResponse) { try PanasonicViera.parseVolume(status: 200, body: huge) }
    }

    // MARK: HTTP (stubbed)

    @Test func httpSendsToTheLANAddressOnly() async throws {
        let url = "http://192.168.1.31:55000/dmr/control_0"
        StubDescriptionProtocol.serve(url, body: Self.reply("<u:GetVolumeResponse><CurrentVolume>12</CurrentVolume></u:GetVolumeResponse>"))
        let session = StubDescriptionProtocol.session()
        let reply = try await VieraHTTP.send(PanasonicViera.getVolume, to: "192.168.1.31", session: session)
        #expect(reply.status == 200)
        #expect(try PanasonicViera.parseVolume(status: reply.status, body: reply.body) == 12)
        #expect(StubDescriptionProtocol.wasRequested(url))

        await #expect(throws: VieraError.unreachable) {
            _ = try await VieraHTTP.send(PanasonicViera.getVolume, to: "8.8.4.4", session: session)
        }
        #expect(!StubDescriptionProtocol.wasRequested("http://8.8.4.4:55000/dmr/control_0"))
    }

    // MARK: Step 9c: SetVolume, SetMute

    @Test func setVolumeAndSetMuteEnvelopes() {
        let volume = PanasonicViera.setVolume(13)
        #expect(volume.path == "/dmr/control_0")
        #expect(volume.headers["SOAPACTION"] == #""urn:schemas-upnp-org:service:RenderingControl:1#SetVolume""#)
        #expect(volume.body == Self.envelope(#"<u:SetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1"><InstanceID>0</InstanceID><Channel>Master</Channel><DesiredVolume>13</DesiredVolume></u:SetVolume>"#))
        let mute = PanasonicViera.setMute(true)
        #expect(mute.path == "/dmr/control_0")
        #expect(mute.headers["SOAPACTION"] == #""urn:schemas-upnp-org:service:RenderingControl:1#SetMute""#)
        #expect(mute.body == Self.envelope(#"<u:SetMute xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1"><InstanceID>0</InstanceID><Channel>Master</Channel><DesiredMute>1</DesiredMute></u:SetMute>"#))
        #expect(PanasonicViera.setMute(false).body.contains("<DesiredMute>0</DesiredMute>"))
        #expect(!volume.body.contains("\n"))
    }

    @Test func setVolumeIsClampedToTheTVsRange() {
        for (asked, sent) in [(-5, 0), (0, 0), (100, 100), (101, 100), (Int.max, 100), (Int.min, 0)] {
            #expect(PanasonicViera.setVolume(asked).body.contains("<DesiredVolume>\(sent)</DesiredVolume>"), "\(asked)")
        }
    }

    @Test func setRepliesParse() throws {
        try PanasonicViera.parseSet(status: 200, body: Self.reply(#"<u:SetVolumeResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1"/>"#))
        try PanasonicViera.parseSet(status: 200, body: Data())
        #expect(throws: VieraError.fault(code: "401", description: "Invalid Action")) {
            try PanasonicViera.parseSet(status: 500, body: Self.fault)
        }
        #expect(throws: VieraError.status(500)) { try PanasonicViera.parseSet(status: 500, body: Data()) }
    }
}
