import AppKit
import ApplicationServices
import os

/// D35, M7c L1: brings MMTVL forward and checks that it worked. macOS 14+ may refuse `NSApp.activate()`
/// from the background (cooperative activation), so a refused rung is followed by the next one.
final class Foregrounder {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Foreground")

    enum Rung: String { case activate, axFrontmost, hideFrontApp }

    static let checkDelay: Duration = .milliseconds(250)
    /// Step 2 may change the order.
    var rungs: [Rung] = [.activate, .axFrontmost, .hideFrontApp]

    private let windowed: Bool
    private let selfPID: pid_t
    private let frontmostPID: () -> pid_t?
    private let frontmostBundleID: () -> String?
    private let activate: () -> Void
    private let axFrontmost: () -> Bool
    private let hideFrontApp: () -> Bool
    private let sleep: (Duration) async -> Void
    private let clock = ContinuousClock()
    /// A newer call cancels an older one.
    private var generation = 0

    init(windowed: Bool = AppEnvironment.windowedMode,
         selfPID: pid_t = getpid(),
         frontmostPID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
         frontmostBundleID: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
         activate: @escaping () -> Void = { NSApp.activate() },
         axFrontmost: @escaping () -> Bool = { Foregrounder.setAXFrontmost() },
         hideFrontApp: @escaping () -> Bool = { Foregrounder.hideFrontmostRegularApp() },
         sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.windowed = windowed
        self.selfPID = selfPID
        self.frontmostPID = frontmostPID
        self.frontmostBundleID = frontmostBundleID
        self.activate = activate
        self.axFrontmost = axFrontmost
        self.hideFrontApp = hideFrontApp
        self.sleep = sleep
    }

    /// Returns true once MMTVL is frontmost; false when every rung failed or a newer call took over.
    @discardableResult
    func bringForward(reason: String) async -> Bool {
        generation += 1
        let myGeneration = generation
        let start = clock.now
        let before = frontmostBundleID() ?? "none"
        // -windowed: never hide the developer's apps or force the foreground.
        let ladder = windowed ? Array(rungs.prefix(1)) : rungs
        for rung in ladder {
            let tried = perform(rung)
            await sleep(Self.checkDelay)
            guard myGeneration == generation else {
                Self.logger.notice("\(reason, privacy: .public): superseded after \(rung.rawValue, privacy: .public)")
                return false
            }
            let succeeded = frontmostPID() == selfPID
            Self.logger.notice("\(reason, privacy: .public): \(rung.rawValue, privacy: .public) tried=\(tried) frontmost=\(succeeded) (front app before: \(before, privacy: .public))")
            if succeeded {
                Self.logger.notice("\(reason, privacy: .public): in front after \((self.clock.now - start).formatted(.units(allowed: [.milliseconds])), privacy: .public)")
                return true
            }
        }
        Self.logger.notice("\(reason, privacy: .public): every rung failed; front app now \(self.frontmostBundleID() ?? "none", privacy: .public), \((self.clock.now - start).formatted(.units(allowed: [.milliseconds])), privacy: .public)")
        return false
    }

    private func perform(_ rung: Rung) -> Bool {
        switch rung {
        case .activate:
            activate()
            return true
        case .axFrontmost:
            return axFrontmost()
        case .hideFrontApp:
            return hideFrontApp()
        }
    }

    /// Rung 2: AX sets MMTVL frontmost (needs the Accessibility grant, D4).
    static func setAXFrontmost() -> Bool {
        guard AccessibilityPermission.isTrusted else { return false }
        return AXUIElementSetAttributeValue(AXUIElementCreateApplication(getpid()),
                                            kAXFrontmostAttribute as CFString, kCFBooleanTrue) == .success
    }

    /// Rung 3: hides the frontmost regular app other than MMTVL; it keeps running (D18) and its tile unhides it.
    static func hideFrontmostRegularApp() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != getpid(),
              front.activationPolicy == .regular
        else { return false }
        return front.hide()
    }
}
