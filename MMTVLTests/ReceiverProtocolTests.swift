import Foundation
import Testing
@testable import MMTVL

/// M7h L11, *Receiver protocols*: each codec's bytes and reply parsing.
struct ReceiverProtocolTests {
    private static let allCommands: [ReceiverCommand] = [
        .powerOn, .powerOff, .queryPower, .volumeUp, .volumeDown, .queryVolume, .mute(true), .mute(false), .queryMute,
    ]

    /// Checks every command against the table, as text.
    private func expectEncodings(_ codec: any ReceiverProtocol, _ expected: [ReceiverCommand: String],
                                 sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(Set(expected.keys) == Set(Self.allCommands), sourceLocation: sourceLocation)
        for (command, text) in expected {
            #expect(codec.encode(command) == Array(text.utf8), "\(command)", sourceLocation: sourceLocation)
        }
    }

    // MARK: Encoding

    @Test func pioneerEncodes() {
        expectEncodings(PioneerProtocol(), [
            .powerOn: "PO\r", .powerOff: "PF\r", .queryPower: "?P\r",
            .volumeUp: "VU\r", .volumeDown: "VD\r", .queryVolume: "?V\r",
            .mute(true): "MO\r", .mute(false): "MF\r", .queryMute: "?M\r",
        ])
    }

    @Test func onkyoEncodes() {
        expectEncodings(OnkyoProtocol(), [
            .powerOn: "!1PWR01\r", .powerOff: "!1PWR00\r", .queryPower: "!1PWRQSTN\r",
            .volumeUp: "!1MVLUP\r", .volumeDown: "!1MVLDOWN\r", .queryVolume: "!1MVLQSTN\r",
            .mute(true): "!1AMT01\r", .mute(false): "!1AMT00\r", .queryMute: "!1AMTQSTN\r",
        ])
    }

    @Test func denonEncodes() {
        expectEncodings(DenonProtocol(), [
            .powerOn: "PWON\r", .powerOff: "PWSTANDBY\r", .queryPower: "PW?\r",
            .volumeUp: "MVUP\r", .volumeDown: "MVDOWN\r", .queryVolume: "MV?\r",
            .mute(true): "MUON\r", .mute(false): "MUOFF\r", .queryMute: "MU?\r",
        ])
    }

    @Test func yamahaEncodes() {
        expectEncodings(YamahaProtocol(), [
            .powerOn: "@MAIN:PWR=On\r\n", .powerOff: "@MAIN:PWR=Standby\r\n", .queryPower: "@MAIN:PWR=?\r\n",
            .volumeUp: "@MAIN:VOL=Up\r\n", .volumeDown: "@MAIN:VOL=Down\r\n", .queryVolume: "@MAIN:VOL=?\r\n",
            .mute(true): "@MAIN:MUTE=On\r\n", .mute(false): "@MAIN:MUTE=Off\r\n", .queryMute: "@MAIN:MUTE=?\r\n",
        ])
    }

    @Test func anthemEncodes() {
        expectEncodings(AnthemProtocol(), [
            .powerOn: "Z1POW1;", .powerOff: "Z1POW0;", .queryPower: "Z1POW?;",
            .volumeUp: "Z1VUP;", .volumeDown: "Z1VDN;", .queryVolume: "Z1VOL?;",
            .mute(true): "Z1MUT1;", .mute(false): "Z1MUT0;", .queryMute: "Z1MUT?;",
        ])
    }

    @Test func nadEncodes() {
        expectEncodings(NADProtocol(), [
            .powerOn: "\rMain.Power=On\r", .powerOff: "\rMain.Power=Off\r", .queryPower: "\rMain.Power?\r",
            .volumeUp: "\rMain.Volume+\r", .volumeDown: "\rMain.Volume-\r", .queryVolume: "\rMain.Volume?\r",
            .mute(true): "\rMain.Mute=On\r", .mute(false): "\rMain.Mute=Off\r", .queryMute: "\rMain.Mute?\r",
        ])
    }

    // MARK: Settings per brand

    @Test func serialSettingsAndTiming() {
        #expect(PioneerProtocol().serial == SerialSettings(baud: 9600, dataBits: 8, parity: .none, stopBits: 1))
        #expect(OnkyoProtocol().serial.baud == 9600)
        #expect(DenonProtocol().serial.baud == 9600)
        #expect(YamahaProtocol().serial.baud == 9600)
        #expect(AnthemProtocol().serial.baud == 115_200)
        #expect(NADProtocol().serial.baud == 115_200)
        #expect(PioneerProtocol().minimumGap == .milliseconds(100))
        #expect(OnkyoProtocol().minimumGap > .milliseconds(50))
        let pioneer = PioneerProtocol().wakeRule
        #expect(pioneer.powerOnCount == 2)
        #expect(pioneer.powerOnRepeatGap >= .milliseconds(100))
        #expect(pioneer.onOpen == [0x0D])
        #expect(DenonProtocol().wakeRule.pauseAfterPowerOn == .seconds(1))
        #expect(OnkyoProtocol().wakeRule == ReceiverWakeRule())
    }

    @Test func brandsHaveTheirCodecs() {
        #expect(ReceiverBrand.none.codec == nil)
        #expect(ReceiverBrand.supported == [.pioneer, .onkyo, .denon, .yamaha, .anthem, .nad])
        for brand in ReceiverBrand.supported {
            #expect(brand.codec?.brand == brand)
        }
    }

    /// L12: Test and Find never send anything that changes the receiver.
    @Test func probeQueriesAreOnlyQueries() {
        for brand in ReceiverBrand.supported {
            let queries = brand.codec?.probeQueries ?? []
            #expect(queries == [.queryPower, .queryVolume, .queryMute], "\(brand)")
            #expect(queries.allSatisfy { $0.isQuery }, "\(brand)")
        }
        #expect(ReceiverCommand.queryPower.isQuery)
        #expect(!ReceiverCommand.powerOn.isQuery)
        #expect(!ReceiverCommand.mute(false).isQuery)
        #expect(!ReceiverCommand.volumeDown.isQuery)
    }

    // MARK: Parsing

    @Test func pioneerParses() {
        let codec = PioneerProtocol()
        #expect(codec.parse(line: "PWR0") == .power(true))
        #expect(codec.parse(line: "PWR1") == .power(false))
        #expect(codec.parse(line: "VOL61") == .volume(raw: 61, dB: -20))
        #expect(codec.parse(line: "VOL81") == .volume(raw: 81, dB: 0))
        #expect(codec.parse(line: "VOL161") == .volume(raw: 161, dB: 0))
        #expect(codec.parse(line: "VOL121") == .volume(raw: 121, dB: -20))
        // QA minor 5: −∞ at the bottom, distinct from "no dB".
        #expect(codec.parse(line: "VOL00") == .volume(raw: 0, dB: -.infinity))
        #expect(codec.parse(line: "VOL000") == .volume(raw: 0, dB: -.infinity))
        #expect(codec.parse(line: "MUT1") == .muted(false))
        #expect(codec.parse(line: "MUT0") == .muted(true))
        #expect(codec.parse(line: "VOL61\r\n") == .volume(raw: 61, dB: -20))
    }

    /// Step 1: garbage before a reply, and lines not in the protocol.
    @Test func pioneerIgnoresGarbageAndUnknownLines() {
        let codec = PioneerProtocol()
        let garbage = String(decoding: [0x50, 0xFF, 0xFF, 0xFF, 0xFF] + Array("PWR0".utf8), as: UTF8.self)
        #expect(codec.parse(line: garbage) == .power(true))
        for line in ["SR0219", "LM219", "SR0000", "LM128", "SR0009", "R", "FN19", "", "PWR", "VOL1", "VOL1611",
                     "!1PWR01", "@MAIN:PWR=On", "PWR0X"] {
            #expect(codec.parse(line: line) == nil, "\(line)")
        }
    }

    @Test func onkyoParses() {
        let codec = OnkyoProtocol()
        #expect(codec.parse(line: "!1MVL28\u{1A}") == .volume(raw: 40, dB: nil))
        #expect(codec.parse(line: "!1MVL28") == .volume(raw: 40, dB: nil))
        #expect(codec.parse(line: "!1PWR01") == .power(true))
        #expect(codec.parse(line: "!1PWR00\u{1A}\r\n") == .power(false))
        #expect(codec.parse(line: "!1AMT01") == .muted(true))
        #expect(codec.parse(line: "!1AMT00") == .muted(false))
        #expect(codec.parse(line: "!1MVLN/A") == nil)
        #expect(codec.parse(line: "!1PWRN/A") == nil)
        #expect(codec.parse(line: "!1SLI01") == nil)
        #expect(codec.parse(line: "PWR0") == nil)
    }

    @Test func denonParses() {
        let codec = DenonProtocol()
        #expect(codec.parse(line: "MV805") == .volume(raw: 805, dB: 0.5))
        #expect(codec.parse(line: "MV80") == .volume(raw: 80, dB: 0))
        #expect(codec.parse(line: "MV60") == .volume(raw: 60, dB: -20))
        #expect(codec.parse(line: "MV00") == .volume(raw: 0, dB: -.infinity))
        #expect(codec.parse(line: "MVMAX 98") == nil)
        #expect(codec.parse(line: "PWON") == .power(true))
        #expect(codec.parse(line: "PWSTANDBY") == .power(false))
        #expect(codec.parse(line: "MUON") == .muted(true))
        #expect(codec.parse(line: "MUOFF") == .muted(false))
        #expect(codec.parse(line: "ZMON") == nil)
        #expect(codec.parse(line: "SICD") == nil)
    }

    @Test func yamahaParses() {
        let codec = YamahaProtocol()
        #expect(codec.parse(line: "@MAIN:VOL=-35.5") == .volume(raw: -355, dB: -35.5))
        #expect(codec.parse(line: "@MAIN:PWR=On") == .power(true))
        #expect(codec.parse(line: "@MAIN:PWR=Standby") == .power(false))
        #expect(codec.parse(line: "@MAIN:MUTE=On") == .muted(true))
        #expect(codec.parse(line: "@MAIN:MUTE=Off") == .muted(false))
        #expect(codec.parse(line: "@MAIN:MUTE=Att -20 dB") == .muted(true))
        #expect(codec.parse(line: "@UNDEFINED") == nil)
        #expect(codec.parse(line: "@RESTRICTED") == nil)
        #expect(codec.parse(line: "@ZONE2:VOL=-40.0") == nil)
    }

    @Test func anthemParses() {
        let codec = AnthemProtocol()
        #expect(codec.parse(line: "Z1VOL-35") == .volume(raw: -350, dB: -35))
        #expect(codec.parse(line: "Z1POW1") == .power(true))
        #expect(codec.parse(line: "Z1POW0") == .power(false))
        #expect(codec.parse(line: "Z1MUT1") == .muted(true))
        #expect(codec.parse(line: "Z1MUT0;") == .muted(false))
        #expect(codec.parse(line: "!RZ1VOL?") == nil)
        #expect(codec.parse(line: "Z2POW1") == nil)
    }

    @Test func nadParses() {
        let codec = NADProtocol()
        #expect(codec.parse(line: "Main.Volume=-30") == .volume(raw: -300, dB: -30))
        #expect(codec.parse(line: "Main.Power=On") == .power(true))
        #expect(codec.parse(line: "Main.Power=Off") == .power(false))
        #expect(codec.parse(line: "Main.Mute=On") == .muted(true))
        #expect(codec.parse(line: "Main.Mute=Off") == .muted(false))
        #expect(codec.parse(line: "Main.Source=1") == nil)
    }

    // MARK: Line splitting

    @Test func splitterSplitsOnAnyDelimiterAcrossChunks() {
        var splitter = SerialLineSplitter(delimiters: PioneerProtocol().lineDelimiters)
        #expect(splitter.append(Array("R\r\nPWR".utf8)) == ["R"])
        #expect(splitter.append(Array("0\r\nVOL61\r\n".utf8)) == ["PWR0", "VOL61"])
        #expect(splitter.append(Array("\r\n\r\n".utf8)).isEmpty)

        var onkyo = SerialLineSplitter(delimiters: OnkyoProtocol().lineDelimiters)
        #expect(onkyo.append(Array("!1MVL28\u{1A}!1PWR01\u{1A}\r\n".utf8)) == ["!1MVL28", "!1PWR01"])

        var anthem = SerialLineSplitter(delimiters: AnthemProtocol().lineDelimiters)
        #expect(anthem.append(Array("Z1POW1;Z1VOL-35;".utf8)) == ["Z1POW1", "Z1VOL-35"])
    }

    @Test func splitterDropsOverlongLines() {
        var splitter = SerialLineSplitter(delimiters: [0x0D])
        splitter.maximumLength = 8
        #expect(splitter.append(Array("0123456789ABCDEF".utf8)).isEmpty)
        #expect(splitter.append(Array("GH\rPWR0\r".utf8)) == ["PWR0"])
    }

    @Test func pioneerGarbageBytesParseAfterSplitting() {
        var splitter = SerialLineSplitter(delimiters: PioneerProtocol().lineDelimiters)
        let lines = splitter.append([0x50, 0xFF, 0xFF, 0xFF, 0xFF] + Array("PWR0\r\n".utf8))
        #expect(lines.count == 1)
        #expect(lines.first.flatMap(PioneerProtocol().parse(line:)) == .power(true))
    }

    @Test func serialPortInfoNames() {
        #expect(SerialPortInfo(path: "/dev/cu.usbserial-XXXXXXXX", usbProductName: "FT232R USB UART").displayName
                    == "USB serial port (FT232R USB UART)")
        #expect(SerialPortInfo(path: "/dev/cu.usbserial-XXXXXXXX", usbProductName: nil).isUSB)
        #expect(!SerialPortInfo(path: "/dev/cu.Bluetooth-Incoming-Port", usbProductName: nil).isUSB)
        #expect(SerialPortInfo(path: "/dev/cu.debug-console", usbProductName: nil).displayName == "Serial port")
    }

    // MARK: Network (L17)

    @Test func eachBrandsDefaultNetworkPort() {
        let expected: [ReceiverBrand: [UInt16]] = [
            .pioneer: [23, 8102], .onkyo: [60128], .denon: [23], .yamaha: [50000], .anthem: [14999], .nad: [23],
        ]
        #expect(Set(expected.keys) == Set(ReceiverBrand.supported))
        for brand in ReceiverBrand.supported {
            let codec = brand.codec!
            #expect(codec.networkPorts(override: nil) == expected[brand], "\(brand)")
            #expect(codec.networkPort == expected[brand]?.first, "\(brand)")
            #expect(codec.networkFraming == (brand == .onkyo ? .eISCP : .plain), "\(brand)")
        }
    }

    @Test func receiverNetworkPortOverridesTheBrandsPorts() throws {
        #expect(PioneerProtocol().networkPorts(override: 8102) == [8102])
        #expect(OnkyoProtocol().networkPorts(override: 6000) == [6000])
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"receiverNetworkPort": 2323}"#.utf8))
        #expect(DenonProtocol().networkPorts(override: settings.validatedReceiverNetworkPort) == [2323])
        let none = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(YamahaProtocol().networkPorts(override: none.validatedReceiverNetworkPort) == [50000])
    }

    /// Onkyo ISCP v1.15: "ISCP", header size 16 and data size (32-bit big-endian), version 1, 3 reserved bytes.
    @Test func eISCPFramesPowerOn() {
        let message = OnkyoProtocol().encode(.powerOn)
        #expect(message == Array("!1PWR01\r".utf8))
        let framed = EISCP.frame(message)
        #expect(framed.count == 16 + 8)
        #expect(Array(framed[0..<4]) == Array("ISCP".utf8))
        #expect(Array(framed[4..<8]) == [0, 0, 0, 16])
        #expect(Array(framed[8..<12]) == [0, 0, 0, 8])
        #expect(Array(framed[12..<16]) == [0x01, 0, 0, 0])
        #expect(Array(framed[16...]) == message)
        // The TCP transport frames through the decoder; plain brands go out as on serial.
        #expect(ReceiverStreamDecoder(framing: .eISCP, delimiters: OnkyoProtocol().lineDelimiters).frame(message) == framed)
        let pioneer = PioneerProtocol().encode(.queryPower)
        #expect(ReceiverStreamDecoder(framing: .plain, delimiters: PioneerProtocol().lineDelimiters).frame(pioneer) == pioneer)
    }

    private static func onkyoDecoder() -> ReceiverStreamDecoder {
        ReceiverStreamDecoder(framing: .eISCP, delimiters: OnkyoProtocol().lineDelimiters)
    }

    @Test func eISCPReplyUnframes() {
        var decoder = Self.onkyoDecoder()
        let lines = decoder.append(EISCP.frame(Array("!1PWR01\u{1A}\r\n".utf8)))
        #expect(lines == ["!1PWR01"])
        #expect(OnkyoProtocol().parse(line: lines[0]) == .power(true))
        // A message without its own delimiter is still one line.
        #expect(decoder.append(EISCP.frame(Array("!1AMT00".utf8))) == ["!1AMT00"])
    }

    @Test func eISCPReplySplitAcrossReads() {
        var decoder = Self.onkyoDecoder()
        let framed = EISCP.frame(Array("!1MVL28\u{1A}".utf8))
        #expect(decoder.append(framed[0..<3]).isEmpty)     // inside "ISCP"
        #expect(decoder.append(framed[3..<10]).isEmpty)    // inside the header
        #expect(decoder.append(framed[10..<19]).isEmpty)   // inside the data
        let lines = decoder.append(framed[19...])
        #expect(lines == ["!1MVL28"])
        #expect(OnkyoProtocol().parse(line: lines[0]) == .volume(raw: 40, dB: nil))
    }

    @Test func twoEISCPRepliesInOneRead() {
        var decoder = Self.onkyoDecoder()
        let bytes = EISCP.frame(Array("!1PWR00\u{1A}".utf8)) + EISCP.frame(Array("!1AMT01\u{1A}\r\n".utf8))
        #expect(decoder.append(bytes) == ["!1PWR00", "!1AMT01"])
    }

    @Test func eISCPSkipsNoiseAndBogusHeaders() {
        var decoder = Self.onkyoDecoder()
        // Garbage before a header is dropped.
        #expect(decoder.append(Array("xx\u{0}".utf8) + EISCP.frame(Array("!1PWR01\u{1A}".utf8))) == ["!1PWR01"])
        // A header claiming more than the maximum data size isn't waited for.
        var bogus = EISCP.frame([])
        bogus[8...11] = [0, 0x10, 0, 0]   // 1 MiB
        #expect(decoder.append(bogus + EISCP.frame(Array("!1AMT00\u{1A}".utf8))) == ["!1AMT00"])
    }

    @Test func plainNetworkRepliesSplitLikeSerial() {
        var decoder = ReceiverStreamDecoder(framing: .plain, delimiters: PioneerProtocol().lineDelimiters)
        #expect(decoder.append(Array("PWR0\r\nVOL".utf8)) == ["PWR0"])
        #expect(decoder.append(Array("61\r\n".utf8)) == ["VOL61"])
    }

    // MARK: Step 10 security: implausible dB

    /// A huge dB used to trap in `Int((dB * 10).rounded())`; now it's ignored before any conversion.
    @Test func implausibleDecibelsAreIgnored() {
        for text in ["1e18", "-1e300", "99999999999999999999", "inf", "-inf", "nan", "30.5", "-100.5"] {
            #expect(ReceiverLine.decibels(Substring(text)) == nil, "\(text)")
        }
        #expect(ReceiverLine.decibels("-100") == .volume(raw: -1000, dB: -100))
        #expect(ReceiverLine.decibels("30") == .volume(raw: 300, dB: 30))
        #expect(ReceiverLine.decibels(" -35.5 ") == .volume(raw: -355, dB: -35.5))
    }

    @Test func dBBrandsIgnoreImplausibleVolumes() {
        #expect(NADProtocol().parse(line: "Main.Volume=1e18") == nil)
        #expect(NADProtocol().parse(line: "Main.Volume=-1e300") == nil)
        #expect(YamahaProtocol().parse(line: "@MAIN:VOL=1e18") == nil)
        #expect(YamahaProtocol().parse(line: "@MAIN:VOL=99999999999999999999") == nil)
        #expect(AnthemProtocol().parse(line: "Z1VOL1e18") == nil)
        #expect(AnthemProtocol().parse(line: "Z1VOL-1e300") == nil)
        #expect(AnthemProtocol().parse(line: "Z1VOL-35") == .volume(raw: -350, dB: -35))
    }
}
