import Testing
@testable import MMTVL

/// M7h step 9 (reopened): the only CEC frames MMTVL sends, the tunnel's write allow-list, and the power status.
struct CECFrameTests {
    @Test func framesAreTheFixedSetFromAddressFour() throws {
        #expect(CECFrame.standbyAll.bytes == [0x4F, 0x36])
        #expect(CECFrame.imageViewOn.bytes == [0x40, 0x04])
        #expect(CECFrame.givePowerStatus.bytes == [0x40, 0x8F])
        let address = try #require(CECPhysicalAddress(high: 0x23, low: 0x00))
        #expect(CECFrame.activeSource(address).bytes == [0x4F, 0x82, 0x23, 0x00])
        #expect(CECFrame.activeSource(address).description == "4F:82:23:00 (Active Source 2.3.0.0)")
        #expect(CECFrame.standbyAll.description == "4F:36 (Standby to all)")
        for frame in [CECFrame.standbyAll, .imageViewOn, .givePowerStatus, .activeSource(address)] {
            #expect(frame.initiatorAddress == 4)
        }
    }

    @Test func txInfoIsLengthRetriesAndSendBit() throws {
        // Probe 2: (len − 1) | (3 << 4) | 0x80.
        #expect(CECFrame.standbyAll.txInfo(retries: 3) == 0xB1)
        #expect(CECFrame.givePowerStatus.txInfo(retries: 3) == 0xB1)
        let address = try #require(CECPhysicalAddress(high: 0x23, low: 0x00))
        #expect(CECFrame.activeSource(address).txInfo(retries: 3) == 0xB3)
        #expect(CECFrame.imageViewOn.txInfo(retries: 0) == 0x81)
    }

    @Test func physicalAddressText() throws {
        #expect(try #require(CECPhysicalAddress(high: 0x23, low: 0x00)).description == "2.3.0.0")
        #expect(try #require(CECPhysicalAddress(high: 0x10, low: 0x00)).description == "1.0.0.0")
        #expect(try #require(CECPhysicalAddress(high: 0x12, low: 0x34)).description == "1.2.3.4")
        #expect(CECPhysicalAddress(high: 0xFF, low: 0xFF) == nil)
        #expect(CECPhysicalAddress(high: 0x00, low: 0x00) == nil)
    }

    // MARK: The allow-lists

    @Test func frameTableAllowsOnlyTheFixedFrames() throws {
        let address = try #require(CECPhysicalAddress(high: 0x23, low: 0x00))
        for frame in [CECFrame.standbyAll, .imageViewOn, .givePowerStatus, .activeSource(address)] {
            #expect(CECFrame.isAllowed(frame.bytes), "\(frame)")
        }
        // Another initiator, another destination, extra or missing operands, other opcodes, a poll.
        for bytes in [[0x5F, 0x36], [0x40, 0x36], [0x4F, 0x36, 0x00], [0x4F, 0x82, 0x23], [0x40, 0x8F, 0x00],
                      [0x45, 0x8F, 0x00], [0x45, 0x44], [0x4F, 0x84, 0x23, 0x00, 0x04], [0x40], []] as [[UInt8]] {
            #expect(!CECFrame.isAllowed(bytes), "\(CECFrame.hex(bytes))")
        }
    }

    // MARK: Step 9c

    @Test func volumePowerAndQueryFramesAreTheFixedSet() {
        #expect(CECFrame.volumeKey(.volumeUp, to: .audioSystem).bytes == [0x45, 0x44, 0x41])
        #expect(CECFrame.volumeKey(.volumeDown, to: .audioSystem).bytes == [0x45, 0x44, 0x42])
        #expect(CECFrame.volumeKey(.mute, to: .audioSystem).bytes == [0x45, 0x44, 0x43])
        #expect(CECFrame.released(to: .audioSystem).bytes == [0x45, 0x45])
        #expect(CECFrame.audioSystemStandby.bytes == [0x45, 0x36])
        #expect(CECFrame.audioSystemPowerOn.bytes == [0x45, 0x44, 0x6D])
        #expect(CECFrame.giveAudioStatus.bytes == [0x45, 0x71])
        #expect(CECFrame.givePowerStatus(to: .audioSystem).bytes == [0x45, 0x8F])
        #expect(CECFrame.givePowerStatus(to: .tv) == .givePowerStatus)
        #expect(CECFrame.giveOSDName.bytes == [0x45, 0x46])
        #expect(CECFrame.volumeKey(.volumeUp, to: .tv).bytes == [0x40, 0x44, 0x41])
        #expect(CECFrame.volumeKey(.volumeDown, to: .tv).bytes == [0x40, 0x44, 0x42])
        #expect(CECFrame.volumeKey(.mute, to: .tv).bytes == [0x40, 0x44, 0x43])
        #expect(CECFrame.released(to: .tv).bytes == [0x40, 0x45])
        #expect(CECFrame.volumeKey(.volumeUp, to: .audioSystem).description == "45:44:41 (Volume Up to the receiver)")
        #expect(CECFrame.volumeKey(.volumeUp, to: .audioSystem).txInfo(retries: 3) == 0xB2)
        for frame in Self.stepNineCFrames {
            #expect(CECFrame.isAllowed(frame.bytes), "\(frame)")
            #expect(frame.initiatorAddress == 4)
        }
    }

    private static let stepNineCFrames: [CECFrame] = [
        .volumeKey(.volumeUp, to: .audioSystem), .volumeKey(.volumeDown, to: .audioSystem),
        .volumeKey(.mute, to: .audioSystem), .released(to: .audioSystem), .audioSystemStandby, .audioSystemPowerOn,
        .giveAudioStatus, .givePowerStatus(to: .audioSystem), .giveOSDName,
        .volumeKey(.volumeUp, to: .tv), .volumeKey(.volumeDown, to: .tv), .volumeKey(.mute, to: .tv),
        .released(to: .tv),
    ]

    /// Every 2-byte frame from any initiator, and every 3-byte one from address 4 (others fail the initiator check
    /// first): exactly the planned set passes; plus longer ones.
    @Test func theTableAllowsExactlyThePlannedFrames() {
        let expected: Set<[UInt8]> = [
            [0x4F, 0x36], [0x40, 0x04], [0x40, 0x8F],
            [0x45, 0x44, 0x41], [0x45, 0x44, 0x42], [0x45, 0x44, 0x43], [0x45, 0x44, 0x6D], [0x45, 0x45], [0x45, 0x36],
            [0x45, 0x71], [0x45, 0x8F], [0x45, 0x46],
            [0x40, 0x44, 0x41], [0x40, 0x44, 0x42], [0x40, 0x44, 0x43], [0x40, 0x45],
        ]
        var allowed: Set<[UInt8]> = []
        for header in 0...255 {
            for opcode in 0...255 {
                let two = [UInt8(header), UInt8(opcode)]
                if CECFrame.isAllowed(two) { allowed.insert(two) }
                guard header >> 4 == 4 else {
                    #expect(!CECFrame.isAllowed(two + [0x41]))
                    continue
                }
                for operand in 0...255 where CECFrame.isAllowed(two + [UInt8(operand)]) {
                    allowed.insert(two + [UInt8(operand)])
                }
            }
        }
        #expect(allowed == expected)
        // Probe 2's other queries, Power (0x40) and the TV's Power On Function, System Audio Mode, a Pressed to all.
        for bytes in [[0x45, 0x44, 0x40], [0x40, 0x44, 0x6D], [0x40, 0x44, 0x40], [0x45, 0x70, 0x23, 0x00], [0x45, 0x7D],
                      [0x45, 0x83], [0x45, 0x8C], [0x40, 0x71], [0x40, 0x46], [0x4F, 0x44, 0x41], [0x45, 0x44, 0x41, 0x00],
                      [0x45, 0x45, 0x00], [0x55, 0x44, 0x41], [0x40, 0x36], [0x45, 0x82, 0x23, 0x00]] as [[UInt8]] {
            #expect(!CECFrame.isAllowed(bytes), "\(CECFrame.hex(bytes))")
        }
        // Active Source is the only 4-byte frame.
        #expect(CECFrame.isAllowed([0x4F, 0x82, 0x12, 0x34]))
        #expect(!CECFrame.isAllowed([0x45, 0x44, 0x41, 0x41]))
    }

    @Test func receiverPowerStatusAndNameReplies() {
        #expect(CECPowerStatus.parseReply([0x54, 0x90, 0x00], pattern: .audioSystemPowerStatus) == .on)
        #expect(CECPowerStatus.parseReply([0x54, 0x90, 0x01], pattern: .audioSystemPowerStatus) == .standby)
        // The TV's answer isn't the receiver's, and the other way round.
        #expect(CECPowerStatus.parseReply([0x04, 0x90, 0x00], pattern: .audioSystemPowerStatus) == nil)
        #expect(CECPowerStatus.parseReply([0x54, 0x90, 0x00]) == nil)
        #expect(CECPowerStatus.parseReply([0x5F, 0x90, 0x00], pattern: .audioSystemPowerStatus) == nil)
        #expect(CECPowerStatus.parseReply([0x54, 0x47, 0x00], pattern: .audioSystemOSDName) == nil)
        #expect(CECReplyPattern.powerStatus(from: .tv) == .reportPowerStatus)
        #expect(CECReplyPattern.powerStatus(from: .audioSystem) == .audioSystemPowerStatus)

        let name = [0x54, 0x47] + Array("VSX-01TXH".utf8)
        #expect(CECOSDName.parseReply(name) == "VSX-01TXH")
        #expect(CECOSDName.parseReply([0x54, 0x47, 0x20, 0x41, 0x0A, 0x42, 0xFF, 0x20]) == "AB")
        #expect(CECOSDName.parseReply([0x54, 0x47] + Array(repeating: 0x41, count: 20)) == String(repeating: "A", count: 14))
        #expect(CECOSDName.parseReply([0x54, 0x47, 0x00, 0x7F]) == nil)
        #expect(CECOSDName.parseReply([0x54, 0x47]) == nil)
        #expect(CECOSDName.parseReply([0x04, 0x47, 0x41]) == nil)   // from the TV
        #expect(CECOSDName.parseReply([0x5F, 0x47, 0x41]) == nil)   // not to us
    }

    /// `x:7A:<status>`: bit 7 mute, bits 0–6 volume 0…100, 0x7F unknown (101…126 reserved, also unknown).
    @Test func reportAudioStatusParsing() {
        #expect(CECAudioStatus.parseReply([0x54, 0x7A, 0x2D]) == CECAudioStatus(muted: false, volume: 45))
        #expect(CECAudioStatus.parseReply([0x5F, 0x7A, 0xAD]) == CECAudioStatus(muted: true, volume: 45))   // to all
        #expect(CECAudioStatus.parseReply([0x54, 0x7A, 0x00]) == CECAudioStatus(muted: false, volume: 0))
        #expect(CECAudioStatus.parseReply([0x54, 0x7A, 0x64]) == CECAudioStatus(muted: false, volume: 100))
        #expect(CECAudioStatus.parseReply([0x54, 0x7A, 0x7F]) == CECAudioStatus(muted: false, volume: nil))
        #expect(CECAudioStatus.parseReply([0x54, 0x7A, 0xFF]) == CECAudioStatus(muted: true, volume: nil))
        #expect(CECAudioStatus.parseReply([0x54, 0x7A, 0x65]) == CECAudioStatus(muted: false, volume: nil))
        #expect(CECAudioStatus.parseReply([0x54, 0x7A, 0x7E]) == CECAudioStatus(muted: false, volume: nil))
        // Not from the receiver, not to us or all, another opcode, cut short or too long.
        for bytes in [[0x04, 0x7A, 0x2D], [0x51, 0x7A, 0x2D], [0x54, 0x7B, 0x2D], [0x54, 0x7A], [0x54, 0x7A, 0x2D, 0x00],
                      []] as [[UInt8]] {
            #expect(CECAudioStatus.parseReply(bytes) == nil, "\(CECFrame.hex(bytes))")
        }
        #expect(CECReplyPattern.reportAudioStatus.matches([0x5F, 0x7A, 0x00]))
        #expect(!CECReplyPattern.reportPowerStatus.matches([0x0F, 0x90, 0x00]))
    }

    @Test func replyPatternMatchesInitiatorOpcodeAndUs() {
        #expect(CECReplyPattern.reportPowerStatus.matches([0x04, 0x90, 0x00]))
        #expect(!CECReplyPattern.reportPowerStatus.matches([0x05, 0x90, 0x00]))   // to address 5
        #expect(!CECReplyPattern.reportPowerStatus.matches([0x54, 0x90, 0x00]))   // from the receiver
        #expect(!CECReplyPattern.reportPowerStatus.matches([0x04, 0x84, 0x00]))
        #expect(!CECReplyPattern.reportPowerStatus.matches([0x04]))
    }

    @Test func allowListIsTheTXBufferAndTXInfoWithTheSendBit() {
        #expect(CECTunnel.writeAllowed(0x3020, [0x4F, 0x36]))
        #expect(CECTunnel.writeAllowed(0x3020, [UInt8](repeating: 0, count: 16)))
        #expect(CECTunnel.writeAllowed(0x302F, [0x00]))
        #expect(CECTunnel.writeAllowed(0x3003, [0xB1]))
        #expect(CECTunnel.writeAllowed(0x3003, [0x80]))
        // Past the TX buffer, too long, empty, TX info without the send bit or with two bytes.
        #expect(!CECTunnel.writeAllowed(0x3020, [UInt8](repeating: 0, count: 17)))
        #expect(!CECTunnel.writeAllowed(0x3021, [UInt8](repeating: 0, count: 16)))
        #expect(!CECTunnel.writeAllowed(0x302F, [0x00, 0x00]))
        #expect(!CECTunnel.writeAllowed(0x3020, []))
        #expect(!CECTunnel.writeAllowed(0x3003, [0x31]))
        #expect(!CECTunnel.writeAllowed(0x3003, [0xB1, 0x00]))
        #expect(!CECTunnel.writeAllowed(0x3002, [0x80, 0x4F, 0x36]))
    }

    @Test func everyOtherAddressIsRefused() {
        let allowed = Set<UInt32>(0x3020...0x302F).union([0x3003])
        var addresses = Array(UInt32(0x0000)...UInt32(0x00FF)) + Array(UInt32(0x2F00)...UInt32(0x31FF))
        addresses += [0x3001, 0x3004, 0x300E, 0x300F, 0x0600, 0xFFFF, 0x1_3020, UInt32.max, UInt32.max - 1]
        for address in addresses where !allowed.contains(address) {
            for bytes in [[0xFF], [0x80], [0x01], [0x00, 0x00]] as [[UInt8]] {
                #expect(!CECTunnel.writeAllowed(address, bytes), "\(CECTunnel.hexAddress(address))")
            }
        }
        // The owner's registers, by name: control, the mask, the IRQ flags.
        for address in [CECTunnel.Register.control, CECTunnel.Register.maskLow, CECTunnel.Register.maskHigh,
                        CECTunnel.Register.irqFlags, CECTunnel.Register.capability, CECTunnel.Register.rxInfo,
                        CECTunnel.Register.rxBuffer] {
            #expect(!CECTunnel.writeAllowed(address, [0x01]))
            #expect(!CECTunnel.writeAllowed(address, [0x81]))
        }
    }

    // MARK: Report Power Status

    @Test func powerStatusParsing() {
        #expect(CECPowerStatus.parseReply([0x04, 0x90, 0x00]) == .on)
        #expect(CECPowerStatus.parseReply([0x04, 0x90, 0x01]) == .standby)
        #expect(CECPowerStatus.parseReply([0x04, 0x90, 0x02]) == .standbyToOn)
        #expect(CECPowerStatus.parseReply([0x04, 0x90, 0x03]) == .onToStandby)
        #expect(CECPowerStatus.on.isOn)
        #expect(CECPowerStatus.standbyToOn.isOn)
        #expect(!CECPowerStatus.standby.isOn)
        #expect(!CECPowerStatus.onToStandby.isOn)
        // Other values, other frames, cut short, not from the TV or not to us.
        #expect(CECPowerStatus.parseReply([0x04, 0x90, 0x04]) == nil)
        #expect(CECPowerStatus.parseReply([0x04, 0x90, 0xFF]) == nil)
        #expect(CECPowerStatus.parseReply([0x04, 0x90]) == nil)
        #expect(CECPowerStatus.parseReply([]) == nil)
        #expect(CECPowerStatus.parseReply([0x5F, 0x72, 0x01]) == nil)
        #expect(CECPowerStatus.parseReply([0x0F, 0x90, 0x00]) == nil)
        #expect(CECPowerStatus.parseReply([0x54, 0x90, 0x00]) == nil)
    }
}
