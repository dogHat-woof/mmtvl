import Carbon.HIToolbox
import Testing
@testable import MMTVL

/// M7h L15, U1: Power and Power Menu from any app; Cancel hands the screen back to the app the menu opened over.
struct PowerMenuPresenterTests {
    final class System {
        var isActive = false
        var front: FrontApp? = FrontApp(pid: 4242, bundleID: "tv.plex.htpc")
        var bringForwards = 0
        var returns: [FrontApp] = []
        var powerPresses = 0
        /// The kiosk guard's answer at Cancel.
        var mayReturn = true
        var mayReturnAsked: [FrontApp] = []
    }

    /// Exit to Desktop, recorded.
    final class DesktopExit: DesktopExitControl {
        var isExitedToDesktop = false
        var hides = 0
        var ends = 0
        func exitToDesktop() {
            hides += 1
            isExitedToDesktop = true
        }
        func endExitToDesktop() {
            guard isExitedToDesktop else { return }
            ends += 1
            isExitedToDesktop = false
        }
    }

    private let system = System()
    private let desktop = DesktopExit()

    private func make(pin: String? = nil) -> (PowerMenuPresenter, AppRouter) {
        let (settings, _) = makeSettingsModel()
        let router = AppRouter(items: LaunchItem.defaults, launcher: AppLauncher(), settings: settings,
                               youtube: FakeYouTube(), liveTV: FakeLiveTV(), pinStore: .inMemory(pin),
                               tileArt: makeTestTileArt())
        router.onPowerButton = { [system] in system.powerPresses += 1 }
        let presenter = PowerMenuPresenter(
            router: router,
            isLauncherActive: { [system] in system.isActive },
            frontApp: { [system] in system.front },
            bringForward: { [system] in
                system.bringForwards += 1
                system.isActive = true
            },
            returnToApp: { [system] in system.returns.append($0) },
            mayReturn: { [system] in
                system.mayReturnAsked.append($0)
                return system.mayReturn
            },
            desktopExit: desktop
        )
        return (presenter, router)
    }

    @Test func powerMenuOverAnotherAppBringsMMTVLForwardAndCancelGoesBack() {
        let (presenter, router) = make()
        presenter.handle(.powerMenu)
        #expect(router.powerMenu != nil)
        #expect(system.bringForwards == 1)
        #expect(presenter.previousApp == FrontApp(pid: 4242, bundleID: "tv.plex.htpc"))
        _ = router.handle(.back)
        #expect(router.powerMenu == nil)
        #expect(system.returns == [FrontApp(pid: 4242, bundleID: "tv.plex.htpc")])
        #expect(presenter.previousApp == nil)
    }

    @Test func selectingCancelGoesBackToo() {
        let (presenter, router) = make()
        presenter.handle(.powerMenu)
        for _ in 0..<4 { _ = router.handle(.down) }
        _ = router.handle(.select)
        #expect(system.returns.count == 1)
    }

    @Test func openedOverMMTVLCancelStaysInMMTVL() {
        system.isActive = true
        let (presenter, router) = make()
        presenter.handle(.powerMenu)
        #expect(system.bringForwards == 0)
        #expect(presenter.previousApp == nil)
        _ = router.handle(.back)
        #expect(system.returns.isEmpty)
    }

    /// Home, an item or Power closes it without going back, and the app is forgotten.
    @Test func otherClosesDontGoBack() {
        let (presenter, router) = make()
        presenter.handle(.powerMenu)
        _ = router.handle(.home)
        #expect(presenter.previousApp == nil)

        system.isActive = false
        presenter.handle(.powerMenu)
        _ = router.handle(.select)   // Turn Off TV & Receiver
        system.isActive = false
        presenter.handle(.powerMenu)
        presenter.handle(.power)
        #expect(system.powerPresses == 1)
        #expect(system.returns.isEmpty)

        // A menu then opened in MMTVL (a key) doesn't go back to a stale app.
        system.isActive = true
        _ = router.handle(.powerMenu)
        _ = router.handle(.back)
        #expect(system.returns.isEmpty)
    }

    /// A second Power Menu while it's open keeps the app it opened over.
    @Test func reopeningKeepsTheApp() {
        let (presenter, router) = make()
        presenter.handle(.powerMenu)
        presenter.handle(.powerMenu)   // MMTVL is active now
        #expect(system.bringForwards == 1)
        _ = router.handle(.back)
        #expect(system.returns.count == 1)
    }

    /// A key bound to Power Menu with Work in Other Apps, another app in front: the event tap's dispatch reaches
    /// `onGlobalCommand` (AppDelegate's `handleGlobal` → `handleGlobal` here), which opens the menu over that app.
    @Test func aGlobalPowerMenuKeyFromAnotherAppGoesThroughThePresenter() throws {
        let (presenter, router) = make()
        let f13 = InputBinding.Trigger.key(keyCode: UInt16(kVK_F13), modifiers: [])
        let bindings = KeyBindings.defaults.adding(f13, for: .powerMenu).settingGlobal(true, for: f13)
        let input = InputRouter(bindings: bindings)
        input.isActive = { [system] in system.isActive }
        input.handler = { command, isRepeat in router.handle(command, isRepeat: isRepeat) }
        var others: [RemoteCommand] = []
        input.onGlobalCommand = { command in
            if !presenter.handleGlobal(command) { others.append(command) }
        }
        let binding = try #require(bindings.binding(keyCode: UInt16(kVK_F13), modifiers: []))
        #expect(binding.isGlobal)
        #expect(input.dispatch(binding.command, isGlobal: binding.isGlobal))
        #expect(router.powerMenu != nil)
        #expect(system.bringForwards == 1)
        #expect(presenter.previousApp == FrontApp(pid: 4242, bundleID: "tv.plex.htpc"))
        #expect(others.isEmpty)
        // Home isn't the presenter's.
        system.isActive = false
        #expect(!presenter.handleGlobal(.home))
        #expect(!presenter.handleGlobal(.select))
    }

    /// Security (re-review medium): an app the kiosk guard doesn't allow never gets the screen back.
    @Test func cancelStaysInMMTVLWhenTheGuardRefusesTheApp() {
        system.mayReturn = false
        system.front = FrontApp(pid: 77, bundleID: "com.apple.finder")
        let (presenter, router) = make()
        presenter.handle(.powerMenu)
        _ = router.handle(.back)
        #expect(system.mayReturnAsked == [FrontApp(pid: 77, bundleID: "com.apple.finder")])
        #expect(system.returns.isEmpty)
        #expect(presenter.previousApp == nil)
        #expect(router.powerMenu == nil)
    }

    @Test func cancelReturnsToAnAllowedApp() {
        system.front = FrontApp(pid: 88, bundleID: "com.squirrels.Reflector-4")
        let (presenter, router) = make()
        presenter.handle(.powerMenu)
        _ = router.handle(.back)
        #expect(system.returns == [FrontApp(pid: 88, bundleID: "com.squirrels.Reflector-4")])
    }

    /// The real rule, with the real `KioskGuard`: session apps and Reflector, not Finder, while the lock is in force;
    /// anything without the lock (after Exit to Desktop).
    @Test func mayReturnFollowsTheKioskGuard() {
        let kioskGuard = KioskGuard()
        kioskGuard.opened(bundleIDs: ["tv.plex.htpc"])
        let plex = FrontApp(pid: 1, bundleID: "tv.plex.htpc")
        let reflector = FrontApp(pid: 2, bundleID: ReflectorMonitor.bundleID)
        let finder = FrontApp(pid: 3, bundleID: "com.apple.finder")
        let noBundle = FrontApp(pid: 4, bundleID: nil)
        #expect(PowerMenuPresenter.mayReturn(to: plex, isLockInForce: true, kioskGuard: kioskGuard))
        #expect(PowerMenuPresenter.mayReturn(to: reflector, isLockInForce: true, kioskGuard: kioskGuard))
        #expect(!PowerMenuPresenter.mayReturn(to: finder, isLockInForce: true, kioskGuard: kioskGuard))
        #expect(!PowerMenuPresenter.mayReturn(to: noBundle, isLockInForce: true, kioskGuard: kioskGuard))
        #expect(PowerMenuPresenter.mayReturn(to: finder, isLockInForce: false, kioskGuard: kioskGuard))
        // After Home the tile's app is no longer allowed.
        kioskGuard.homePressed()
        #expect(!PowerMenuPresenter.mayReturn(to: plex, isLockInForce: true, kioskGuard: kioskGuard))
    }

    /// Security low: a bundle id must be known and match (two nils don't).
    @Test func sameAppNeedsAMatchingBundleID() {
        let plex = FrontApp(pid: 1, bundleID: "tv.plex.htpc")
        #expect(PowerMenuPresenter.isSameApp(plex, runningBundleID: "tv.plex.htpc", isTerminated: false))
        #expect(!PowerMenuPresenter.isSameApp(plex, runningBundleID: "tv.plex.htpc", isTerminated: true))
        #expect(!PowerMenuPresenter.isSameApp(plex, runningBundleID: "com.apple.finder", isTerminated: false))
        #expect(!PowerMenuPresenter.isSameApp(plex, runningBundleID: nil, isTerminated: false))
        #expect(!PowerMenuPresenter.isSameApp(FrontApp(pid: 1, bundleID: nil), runningBundleID: nil, isTerminated: false))
    }

    /// QA minor: the power menu's show doesn't end Exit to Desktop (the lock stays off); every other show does.
    @Test func thePowerMenuDoesntEndExitToDesktop() {
        #expect(!KioskWindowController.endsExitToDesktop(reason: KioskWindowController.powerMenuReason))
        for reason in ["home", "wake", "appQuit", "mirroringEnded", "cast", "guard", "quit"] {
            #expect(KioskWindowController.endsExitToDesktop(reason: reason), "\(reason)")
        }
    }

    // MARK: After Exit to Desktop (re-review medium)

    /// Opens the menu over a desktop app (Finder) after Exit to Desktop.
    private func exitedMenu(_ presenter: PowerMenuPresenter, _ router: AppRouter) {
        desktop.isExitedToDesktop = true
        system.front = FrontApp(pid: 77, bundleID: "com.apple.finder")
        presenter.handle(.powerMenu)
        #expect(router.powerMenu != nil)
    }

    @Test func afterExitToDesktopAnItemOrPowerHidesMMTVLAgain() {
        let (presenter, router) = make()
        exitedMenu(presenter, router)
        _ = router.handle(.select)   // Turn Off TV & Receiver
        #expect(desktop.hides == 1)
        #expect(desktop.ends == 0)
        #expect(system.returns.isEmpty)

        exitedMenu(presenter, router)
        presenter.handle(.power)
        #expect(desktop.hides == 2)
        #expect(system.powerPresses == 1)

        // The guard's or a cast's goHome.
        exitedMenu(presenter, router)
        router.goHome()
        #expect(desktop.hides == 3)
        #expect(desktop.ends == 0)
    }

    @Test func afterExitToDesktopHomeEndsTheExit() {
        let (presenter, router) = make()
        exitedMenu(presenter, router)
        _ = router.handle(.home)
        #expect(desktop.ends == 1)
        #expect(!desktop.isExitedToDesktop)
        #expect(desktop.hides == 0)
        #expect(router.screen == .home)
    }

    @Test func afterExitToDesktopCancelGoesBackThenHides() {
        let (presenter, router) = make()
        exitedMenu(presenter, router)
        _ = router.handle(.back)
        #expect(system.returns == [FrontApp(pid: 77, bundleID: "com.apple.finder")])
        #expect(desktop.hides == 1)

        // Opened in MMTVL (⌘Tab after the exit): no app to go back to; hidden all the same.
        system.isActive = true
        presenter.handle(.powerMenu)
        _ = router.handle(.back)
        #expect(system.returns.count == 1)
        #expect(desktop.hides == 2)
    }

    /// Relaunch's PIN screen needs MMTVL in front: the exit ends instead (the lock comes back).
    @Test func afterExitToDesktopThePINScreenEndsTheExit() {
        let (presenter, router) = make(pin: "1357")
        exitedMenu(presenter, router)
        for _ in 0..<2 { _ = router.handle(.down) }
        _ = router.handle(.select)   // Relaunch MMTVL
        #expect(router.screen == .pin(.relaunch))
        #expect(desktop.ends == 1)
        #expect(desktop.hides == 0)
    }

    /// Not exited: closes never hide or end anything.
    @Test func withoutExitToDesktopClosesDontTouchIt() {
        let (presenter, router) = make()
        presenter.handle(.powerMenu)
        _ = router.handle(.select)
        presenter.handle(.powerMenu)
        _ = router.handle(.home)
        presenter.handle(.powerMenu)
        _ = router.handle(.back)
        #expect(desktop.hides == 0)
        #expect(desktop.ends == 0)
    }

    @Test func powerGoesToTheRouter() {
        let (presenter, _) = make()
        presenter.handle(.power)
        presenter.handle(.select)
        #expect(system.powerPresses == 1)
        #expect(system.bringForwards == 0)
    }
}
