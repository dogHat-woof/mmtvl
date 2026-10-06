/// How `RemoteCommand`s reach YouTube's TV UI ("leanback"): JavaScript key events (L1).
/// Leanback acts on synthetic events, so one path serves keyboard, controllers and the phone remote.
nonisolated enum YouTubeKeyMap {
    static let messageHandlerName = "mmtvl"

    /// Leanback key codes, verified 2026-10-05. 179/228/227 are the TV media keys (play/pause, FF, rewind);
    /// FF/rewind open leanback's scrub mode, Select resumes there. Home never reaches the page.
    static func keyCode(for command: RemoteCommand) -> Int? {
        switch command {
        case .up: 38
        case .down: 40
        case .left: 37
        case .right: 39
        case .select: 13
        case .back: 27
        case .playPause: 179
        case .fastForward: 228
        case .rewind: 227
        case .home: nil
        }
    }

    /// keydown + keyup on `document`. Ends in `'ok'` because evaluateJavaScript reports `undefined` as an error.
    static func dispatchScript(keyCode: Int) -> String {
        "for (const t of ['keydown', 'keyup']) { const e = new Event(t); e.keyCode = \(keyCode); document.dispatchEvent(e); } 'ok'"
    }

    /// Injected at document start, main frame only: leanback's exit calls window.close(), which becomes a message.
    static let exitHookScript = "window.close = function () { window.webkit.messageHandlers.\(messageHandlerName).postMessage('close'); };"

    /// Injected at document start, main frame only: the page always looks visible, so leaving YouTube and coming
    /// back doesn't count as an app resume (leanback otherwise shows "Welcome back" / offers instead of the
    /// page left; M3 Deviations, user choice). Same idea as VacuumTube's pause-on-blur.js. Playback is paused natively.
    static let alwaysVisibleScript = """
        Object.defineProperty(document, 'hidden', { get: () => false });
        Object.defineProperty(document, 'webkitHidden', { get: () => false });
        Object.defineProperty(document, 'visibilityState', { get: () => 'visible' });
        Object.defineProperty(document, 'webkitVisibilityState', { get: () => 'visible' });
        for (const type of ['visibilitychange', 'webkitvisibilitychange']) {
            document.addEventListener(type, (e) => e.stopImmediatePropagation(), true);
        }
        """

    /// Injected at document start, main frame only (M5 L9): MMTVL's own volume for every media element,
    /// also ones created later (media events don't bubble, so a capture listener on `document`).
    static let volumeScript = """
        (() => {
          let level = 1, muted = false;
          const apply = (v) => { v.volume = level; v.muted = muted; };
          window.__mmtvlSetVolume = (l, m) => { level = l; muted = m; document.querySelectorAll('video, audio').forEach(apply); };
          for (const t of ['play', 'loadedmetadata']) {
            document.addEventListener(t, (e) => { if (e.target instanceof HTMLMediaElement) apply(e.target); }, true);
          }
        })();
        """

    /// Sets the page volume (level 0…100). Ends in `'ok'` like `dispatchScript`.
    static func setVolumeScript(level: Int, muted: Bool) -> String {
        "window.__mmtvlSetVolume && window.__mmtvlSetVolume(\(Double(level) / 100), \(muted)); 'ok'"
    }
}
