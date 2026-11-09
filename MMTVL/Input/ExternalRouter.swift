/// M7h L3: the shared "where does a remote command go" routing for sources that work from any app
/// (the phone remote, D24, and the Siri Remote, D43). Volume and power are handled by the caller before this.
/// The closures keep it testable; the app wires `InputRouter` and `SyntheticInput`.
struct ExternalRouter {
    /// What happened to a command.
    enum Outcome: Equatable {
        /// MMTVL is in front (or was just brought forward): dispatched to it, not global.
        case launcher
        /// Home from another app: dispatched as a global Home.
        case home
        /// Posted to the app in front as a synthetic key.
        case posted(ExternalKey)
        /// The command has no key for other apps (`ExternalKeyMap` returns nil): nothing happens.
        case unmapped
        /// Another app is in front and MMTVL may not post events (Accessibility).
        case needsAccessibility
    }

    /// MMTVL is active, or its window shows and was brought forward (M7c L3, `repairForeground`).
    var isLauncherInFront: () -> Bool
    /// `InputRouter.dispatchFromRemote(_:isGlobal:isRepeat:)` (keeps a command while MMTVL is brought forward).
    var dispatch: (_ command: RemoteCommand, _ isGlobal: Bool, _ isRepeat: Bool) -> Void
    /// `SyntheticInput.canPost`.
    var canPostEvents: () -> Bool
    /// `SyntheticInput.postKey` / `postMediaKey`.
    var postExternal: (ExternalKey) -> Void

    /// L3's last three rungs: MMTVL in front → MMTVL; Home → global Home; else the command's key for the app in front.
    @discardableResult
    func route(_ command: RemoteCommand, isRepeat: Bool = false) -> Outcome {
        if isLauncherInFront() {
            dispatch(command, false, isRepeat)
            return .launcher
        }
        if command == .home {
            dispatch(.home, true, false)
            return .home
        }
        guard canPostEvents() else { return .needsAccessibility }
        guard let key = ExternalKeyMap.key(for: command) else { return .unmapped }
        postExternal(key)
        return .posted(key)
    }
}
