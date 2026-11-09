import Foundation
import os

// M7h step 9 (reopened), L13: the TV over HDMI-CEC, through the DisplayPort AUX tunnel (`CECTunnel`), as a `PowerTV`.
// Off is Standby to all (`4F:36`: the TV and a receiver that follows CEC). On is Image View On (`40:04`), then about
// 300 ms later Active Source (`4F:82:<PA>`, the physical address from the EDID; without one, Image View On only). On
// or off is the TV's answer to Give Device Power Status (`40:8F` → `04:90:<s>`); no answer counts like a network TV
// that doesn't answer. Nothing is sent at launch or by Settings except Test TV's status query, and (step 9c, only
// with Volume Buttons Change TV Volume on) the volume readiness check, which is the same status query.
// Step 9c: TV volume is User Control Pressed (`40:44:41/42/43`) + Released (`40:45`); the level is unknown (TVs
// answer Give Audio Status with Feature Abort), and ready means the last status answer was "on".

/// Main actor.
final class HDMICEC: PowerTV {
    static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "CEC")

    /// "On" waits this long for the tunnel after the displays wake (the proxies vanish while HPD is low).
    static let tunnelWait: Duration = .seconds(5)
    static let tunnelPoll: Duration = .milliseconds(250)
    static let activeSourceDelay: Duration = .milliseconds(300)
    /// Step 9c (security M1): a Released that wasn't sent is tried once more after this.
    static let releaseRetryDelay: Duration = .milliseconds(100)
    /// Step 9c (security L1): while ready for volume, a press re-checks the power status when the last answer is
    /// older than this.
    static let readyRecheckInterval: Duration = .seconds(60)

    private(set) var brand: TVBrand = .none
    /// The last check's answer; nil before the first.
    private(set) var availability: CECAvailability?
    /// Settings → Audio & TV → TV → Status follows it.
    var onAvailabilityChange: () -> Void = {}

    private let link: any CECLink
    private let clock: any ReceiverClock
    private let physicalAddress: () -> CECPhysicalAddress?
    /// The last address the EDID gave (the EDID may be gone while HPD is low).
    private var lastPhysicalAddress: CECPhysicalAddress?
    /// Step 9c: the TV's last power status answer since `configure` (nil: none, or no answer).
    private(set) var lastPowerStatus: CECPowerStatus?
    /// When `lastPowerStatus` was last answered (`clock.now`).
    private var lastPowerStatusAt: Duration?
    /// Security L1: the re-check after a press (tests await it).
    private(set) var recheckTask: Task<Void, Never>?

    init(link: any CECLink = CECTunnel(), clock: any ReceiverClock = SystemReceiverClock(),
         physicalAddress: @escaping () -> CECPhysicalAddress? = EDIDPhysicalAddress.current) {
        self.link = link
        self.clock = clock
        self.physicalAddress = physicalAddress
    }

    /// From `settings.json` `tvBrand`. Sends nothing.
    func configure(brand: TVBrand) {
        if brand != self.brand {
            lastPowerStatus = nil
            lastPowerStatusAt = nil
        }
        self.brand = brand
    }

    var isConfigured: Bool { brand == .cec }

    /// QA major (step 9): decided after the wake, by `powerOn` (it waits up to 5 s for the tunnel and says false if
    /// it isn't ready), never from the state cached before the displays woke.
    var canTurnOn: Bool { isConfigured }

    /// Standby to all isn't a toggle: it's sent whether or not the TV answered.
    var powerOffToggles: Bool { false }

    /// A receiver left on can re-route away from the Mac when CEC wakes the TV (probe 2).
    var checksHDMIAfterPowerOn: Bool { true }

    /// Reads the tunnel's state (read-only).
    @discardableResult
    func refreshAvailability() async -> CECAvailability {
        let new = await link.availability()
        if new != availability {
            availability = new
            onAvailabilityChange()
        }
        return new
    }

    /// After an HDMI hot-plug: the DisplayPort device is opened again on the next use.
    func noteDisplayChange() {
        link.invalidate()
        guard isConfigured else { return }
        Task { await refreshAvailability() }
    }

    /// Test TV and `isOn`: the TV's power status; nil when it didn't answer or the tunnel isn't ready (the tunnel
    /// checks itself and sends nothing then).
    func powerStatus() async -> CECPowerStatus? {
        guard isConfigured else { return nil }
        let status = await link.powerStatus()
        await refreshAvailability()
        if isConfigured {
            lastPowerStatus = status
            if status != nil { lastPowerStatusAt = clock.now }
        }
        return status
    }

    func isOn() async -> Bool {
        await powerStatus()?.isOn ?? false
    }

    @discardableResult
    func powerOff() async -> Bool {
        guard isConfigured else { return false }
        let result = await link.send(.standbyAll)
        note(result)
        // QA minor: the TV is going to standby, so TV volume isn't ready until it answers "on" again.
        lastPowerStatus = nil
        lastPowerStatusAt = nil
        return result == .sent
    }

    /// The displays are already awake (`PowerController`). Waits up to 5 s for the tunnel, then Image View On and
    /// Active Source.
    func powerOn() async -> Bool {
        guard isConfigured else { return false }
        let start = clock.now
        var state = await refreshAvailability()
        while state != .ready, clock.now - start < Self.tunnelWait {
            await clock.sleep(for: Self.tunnelPoll)
            state = await refreshAvailability()
        }
        guard state == .ready else {
            Self.logger.notice("CEC: the tunnel isn't ready \(Self.tunnelWait.components.seconds, privacy: .public) s after the wake (\(String(describing: state), privacy: .public)); not turning the TV on")
            return false
        }
        let address = currentPhysicalAddress()
        let imageViewOn = await link.send(.imageViewOn)
        note(imageViewOn)
        guard imageViewOn == .sent else { return false }
        if let address {
            await clock.sleep(for: Self.activeSourceDelay)
            note(await link.send(.activeSource(address)))
        } else {
            Self.logger.notice("CEC: no physical address in the EDID; Image View On only, no Active Source")
        }
        return true
    }

    /// The Mac's HDMI display is there (the External DisplayPort device can be opened again).
    func hdmiDisplayReturned() async -> Bool {
        link.invalidate()
        return await refreshAvailability() != .noDisplay
    }

    // MARK: Step 9c: TV volume

    /// The TV's own volume over HDMI-CEC: Pressed + Released. True once the Pressed frame was sent (acknowledged);
    /// the TV may still ignore it (unverified: the user's TV plays through the receiver).
    func sendVolumeKey(_ key: CECVolumeKey) async -> Bool {
        guard isConfigured else { return false }
        let pressed = await link.send(.volumeKey(key, to: .tv))
        note(pressed)
        // Security M1: a Pressed that may have gone out is always released (once more after 100 ms if needed).
        if pressed.mayHaveGoneOut {
            let released = await link.send(.released(to: .tv))
            note(released)
            if released != .sent {
                Self.logger.notice("CEC: Released to the TV: \(String(describing: released), privacy: .public); trying once more")
                await clock.sleep(for: Self.releaseRetryDelay)
                note(await link.send(.released(to: .tv)))
            }
        }
        guard pressed == .sent else {
            Self.logger.notice("CEC: the TV didn't take the volume key (\(String(describing: pressed), privacy: .public)); volume takes the next route until it answers")
            lastPowerStatus = nil
            lastPowerStatusAt = nil
            return false
        }
        // Security L1: a TV that went to standby on its own stops being ready; checked after the press.
        recheckIfStale()
        return true
    }

    private func recheckIfStale() {
        guard lastPowerStatus?.isOn == true, recheckTask == nil else { return }
        if let lastPowerStatusAt, clock.now - lastPowerStatusAt < Self.readyRecheckInterval { return }
        recheckTask = Task { [weak self] in
            _ = await self?.powerStatus()
            self?.recheckTask = nil
        }
    }

    // MARK: Private

    private func currentPhysicalAddress() -> CECPhysicalAddress? {
        if let address = physicalAddress() {
            if address != lastPhysicalAddress {
                Self.logger.notice("CEC: physical address \(address.description, privacy: .public) (from the EDID)")
            }
            lastPhysicalAddress = address
        }
        return lastPhysicalAddress
    }

    /// An unavailable tunnel updates the cached state Settings shows.
    private func note(_ result: CECSendResult) {
        guard case .unavailable(let state) = result, state != availability else { return }
        availability = state
        onAvailabilityChange()
    }
}
