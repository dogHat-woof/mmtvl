import Foundation

// M7h L18: Panasonic VIERA (2012–2018) network control, as verified on a TC-P55VT50 in step 1. SOAP over HTTP to port
// 55000, no pairing. Bodies are fixed strings built from `VieraKey` and constants (step 9c: a clamped volume number
// and a mute bit), never from input. Pure.

/// The remote keys MMTVL sends. Only power for now; never a key string from input.
nonisolated enum VieraKey: String, CaseIterable, Sendable {
    /// Toggles: only sent when the TV answers (L14), since in standby it can't be reached anyway.
    case power = "NRC_POWER-ONOFF"
}

/// One SOAP request: `POST http://<tv>:55000<path>`.
nonisolated struct VieraRequest: Equatable, Sendable {
    var path: String
    /// Without quotes ("urn:…#X_SendKey"); the header carries it quoted.
    var soapAction: String
    var body: String

    var headers: [String: String] {
        ["Content-Type": "text/xml; charset=\"utf-8\"", "SOAPACTION": "\"\(soapAction)\""]
    }

    /// The request to `address`, a LAN IPv4 literal (the address the connection check reached); nil otherwise.
    func urlRequest(address: String, timeout: TimeInterval) -> URLRequest? {
        guard WakeOnLAN.ipv4(address) != nil, LANAddress.isLANIPLiteral(address),
              let url = URL(string: "http://\(address):\(PanasonicViera.port)\(path)")
        else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = Data(body.utf8)
        return request
    }
}

nonisolated enum VieraError: Error, Equatable, Sendable {
    /// A SOAP fault (UPnP `errorCode`/`errorDescription`, else `faultcode`/`faultstring`).
    case fault(code: String?, description: String?)
    /// Not the expected XML or value.
    case badResponse
    /// Another HTTP status without a fault.
    case status(Int)
    /// No LAN address to send to (the TV is off, or its address isn't on the LAN).
    case unreachable
}

nonisolated enum PanasonicViera {
    static let port: UInt16 = 55000
    /// L18: Find TV's SSDP search target.
    static let searchTarget = "urn:panasonic-com:device:p00RemoteController:1"
    static let networkControlPath = "/nrc/control_0"
    static let renderingControlPath = "/dmr/control_0"
    static let networkControlService = "urn:panasonic-com:service:p00NetworkControl:1"
    static let renderingControlService = "urn:schemas-upnp-org:service:RenderingControl:1"
    /// A reply larger than this is refused.
    static let maximumResponseSize = 64 * 1024

    static func sendKey(_ key: VieraKey) -> VieraRequest {
        VieraRequest(path: networkControlPath, soapAction: "\(networkControlService)#X_SendKey",
                     body: envelope("<u:X_SendKey xmlns:u=\"\(networkControlService)\"><X_KeyEvent>\(key.rawValue)</X_KeyEvent></u:X_SendKey>"))
    }

    static let getVolume = renderingControl("GetVolume")
    static let getMute = renderingControl("GetMute")

    /// The TV's volume range (RenderingControl's `CurrentVolume`).
    static let volumeRange = 0...100

    /// Step 9c: `SetVolume` to `volume`, clamped to 0…100 (the number is the only value in the body).
    static func setVolume(_ volume: Int) -> VieraRequest {
        let clamped = min(volumeRange.upperBound, max(volumeRange.lowerBound, volume))
        return renderingControl("SetVolume", extra: "<DesiredVolume>\(clamped)</DesiredVolume>")
    }

    /// Step 9c: `SetMute` on or off ("1"/"0").
    static func setMute(_ muted: Bool) -> VieraRequest {
        renderingControl("SetMute", extra: "<DesiredMute>\(muted ? 1 : 0)</DesiredMute>")
    }

    private static func renderingControl(_ action: String, extra: String = "") -> VieraRequest {
        VieraRequest(path: renderingControlPath, soapAction: "\(renderingControlService)#\(action)",
                     body: envelope("<u:\(action) xmlns:u=\"\(renderingControlService)\"><InstanceID>0</InstanceID><Channel>Master</Channel>\(extra)</u:\(action)>"))
    }

    /// A SOAP 1.1 envelope around one action, compact (no whitespace between elements), as the `panasonic_viera`
    /// library sends it (QA Q1).
    static func envelope(_ action: String) -> String {
        #"<?xml version="1.0" encoding="utf-8"?>"#
            + #"<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">"#
            + "<s:Body>\(action)</s:Body></s:Envelope>"
    }

    // MARK: Responses

    /// `X_SendKey`: success is a 200 without a fault, whatever the body (QA Q3: an empty one too).
    static func parseSendKey(status: Int, body: Data) throws(VieraError) {
        _ = try fields(status: status, body: body, requiresEnvelope: false)
    }

    /// Step 9c: `SetVolume` / `SetMute`: success is a 200 without a fault, like `X_SendKey`.
    static func parseSet(status: Int, body: Data) throws(VieraError) {
        _ = try fields(status: status, body: body, requiresEnvelope: false)
    }

    /// `GetVolume` → `CurrentVolume` (0…100).
    static func parseVolume(status: Int, body: Data) throws(VieraError) -> Int {
        guard let text = try fields(status: status, body: body)["CurrentVolume"], let volume = Int(text),
              (0...100).contains(volume)
        else { throw .badResponse }
        return volume
    }

    /// `GetMute` → `CurrentMute` ("0"/"1", or "false"/"true").
    static func parseMute(status: Int, body: Data) throws(VieraError) -> Bool {
        switch try fields(status: status, body: body)["CurrentMute"]?.lowercased() {
        case "1", "true": return true
        case "0", "false": return false
        default: throw .badResponse
        }
    }

    /// The response's leaf elements (local names → trimmed text), after checking for a fault and the status.
    private static func fields(status: Int, body: Data,
                               requiresEnvelope: Bool = true) throws(VieraError) -> [String: String] {
        guard body.count <= maximumResponseSize else { throw .badResponse }
        let parsed = SOAPResponseParser.parse(body)
        if parsed.hasFault {
            throw .fault(code: parsed.fields["errorCode"] ?? parsed.fields["faultcode"],
                         description: parsed.fields["errorDescription"] ?? parsed.fields["faultstring"])
        }
        guard status == 200 else { throw .status(status) }
        guard parsed.isSOAP || !requiresEnvelope else { throw .badResponse }
        return parsed.fields
    }
}

/// Reads a SOAP reply: whether it's an `Envelope`, whether it holds a `Fault`, and its leaf elements' text (first
/// of each name, at most 256 characters). No external entities.
nonisolated private final class SOAPResponseParser: NSObject, XMLParserDelegate {
    private static let maximumValueLength = 256

    private(set) var fields: [String: String] = [:]
    private(set) var hasFault = false
    private(set) var isSOAP = false
    private var text = ""

    static func parse(_ data: Data) -> SOAPResponseParser {
        let delegate = SOAPResponseParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        _ = parser.parse()
        return delegate
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch Self.localName(elementName) {
        case "Envelope": isSOAP = true
        case "Fault": hasFault = true
        default: break
        }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard text.count < Self.maximumValueLength else { return }
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = Self.localName(elementName)
        let value = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumValueLength))
        if !value.isEmpty, fields[name] == nil { fields[name] = value }
        text = ""
    }

    private static func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }
}
