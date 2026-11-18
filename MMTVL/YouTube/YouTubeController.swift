import Observation
import WebKit
import os

/// What the router needs from YouTube; tests use a fake.
protocol YouTubeHosting: AnyObject {
    /// Creates the web view and loads the start URL on first call; later calls keep the current state (L3).
    func open()
    func send(_ command: RemoteCommand)
    /// Pauses all media (Home, wake). No-op before the first open.
    func pause()
    /// Opens YouTube on `https://www.youtube.com/tv?<query>` (a cold cast, M7b L2), creating the web view if needed.
    func launch(query: String)
    /// Loads the start URL again (M7m L7: the tile menu's Reload YouTube). No-op before the first open.
    func reload()
    /// True once the web view exists (an open or a cast); the tile menu offers Reload YouTube only then.
    var hasOpened: Bool { get }
    /// Leanback exited (window.close / webViewDidClose). May be called several times in a row.
    var onExit: (() -> Void)? { get set }
}

/// Owns the one YouTube TV web view (D5, D21). It is created on first open and kept alive while away.
@Observable
final class YouTubeController: YouTubeHosting {
    enum Phase: Equatable {
        case idle, loading, ready
        case failed(String)
    }

    fileprivate static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "YouTube")

    private(set) var phase: Phase = .idle
    private(set) var webView: WKWebView?
    var hasOpened: Bool { webView != nil }
    @ObservationIgnored var onExit: (() -> Void)?
    @ObservationIgnored private let userAgent: String
    @ObservationIgnored private let delegate = YouTubeWebDelegate()
    /// MMTVL's own volume (M5 L9); re-applied after every load.
    @ObservationIgnored private var volumeLevel = 100
    @ObservationIgnored private var volumeMuted = false
    /// M7b L5: inject the DIAL shim when the web view is created.
    @ObservationIgnored private let castEnabled: Bool
    /// M7b L8: leanback constructed its DialServer since the last load.
    @ObservationIgnored private(set) var isDIALReady = false

    init(userAgent: String, castEnabled: Bool = false) {
        self.userAgent = userAgent
        self.castEnabled = castEnabled
        delegate.controller = self
    }

    func open() {
        guard webView == nil else { return }
        makeWebViewIfNeeded()
        load()
    }

    func launch(query: String) {
        makeWebViewIfNeeded()
        Self.logger.info("Opening YouTube for a cast")
        load(YouTubeConfig.launchURL(query: query))
    }

    private func makeWebViewIfNeeded() {
        guard webView == nil else { return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        for source in [YouTubeKeyMap.exitHookScript, YouTubeKeyMap.alwaysVisibleScript, YouTubeKeyMap.volumeScript] {
            configuration.userContentController.addUserScript(WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        configuration.userContentController.add(delegate, name: YouTubeKeyMap.messageHandlerName)
        if castEnabled {
            configuration.userContentController.addUserScript(WKUserScript(
                source: YouTubeDIAL.shimScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
            configuration.userContentController.add(delegate, name: YouTubeDIAL.messageHandlerName)
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = userAgent
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        webView.allowsBackForwardNavigationGestures = false
        webView.underPageBackgroundColor = .black
        #if DEBUG
        // L12: Safari → Develop can inspect leanback.
        webView.isInspectable = true
        #endif
        self.webView = webView
        Self.logger.info("Opening YouTube with user agent \(self.userAgent, privacy: .public)")
    }

    func send(_ command: RemoteCommand) {
        if case .failed = phase {
            if command == .select { reload() }
            return
        }
        guard let webView, let keyCode = YouTubeKeyMap.keyCode(for: command) else { return }
        // Back at leanback's top level (e.g. the signed-out welcome page) makes leanback exit itself,
        // through the window.close hook, so no special case is needed (M3 Deviations, step 4).
        webView.evaluateJavaScript(YouTubeKeyMap.dispatchScript(keyCode: keyCode)) { _, error in
            if let error {
                Self.logger.debug("Key \(keyCode) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func pause() {
        webView?.pauseAllMediaPlayback(completionHandler: nil)
    }

    /// M5 L9: the phone's in-app volume. Not on `YouTubeHosting`; AppDelegate calls the concrete class.
    func setVolume(_ level: Int, muted: Bool) {
        volumeLevel = level
        volumeMuted = muted
        applyVolume()
    }

    private func applyVolume() {
        webView?.evaluateJavaScript(YouTubeKeyMap.setVolumeScript(level: volumeLevel, muted: volumeMuted)) { _, error in
            if let error {
                Self.logger.error("Setting the volume failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Loads the start URL again (resets the leanback route). No-op before the first open.
    func reload() {
        guard webView != nil else { return }
        load()
    }

    /// Removes all website data from the default store (signs every account out), then reloads.
    func clearData() async {
        await WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
        Self.logger.info("Cleared YouTube website data")
        reload()
    }

    private func load(_ url: URL = YouTubeConfig.startURL) {
        phase = .loading
        isDIALReady = false
        webView?.load(URLRequest(url: url))
    }

    // MARK: DIAL (M7b L1, L8)

    private static let dialTimeout: TimeInterval = 3

    /// Hands a DIAL request to leanback's own handlers. nil when leanback isn't ready, has no handler,
    /// fails or doesn't answer within 3 s (the server then answers natively). Never logs the body.
    func handleDIAL(_ request: DIALAppRequest) async -> DIALAppResponse? {
        guard isDIALReady, let webView else { return nil }
        let arguments: [String: Any] = [
            "app": request.app, "method": request.method, "path": request.path,
            "body": request.body, "host": request.host,
        ]
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce()
            webView.callAsyncJavaScript(YouTubeDIAL.handleScript, arguments: arguments, in: nil, in: .page) { result in
                MainActor.assumeIsolated {
                    guard once.claim() else { return }
                    switch result {
                    case .success(let value):
                        continuation.resume(returning: YouTubeDIAL.response(fromJavaScript: value))
                    case .failure(let error):
                        Self.logger.error("DIAL request failed in the page: \(error.localizedDescription, privacy: .public)")
                        continuation.resume(returning: nil)
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.dialTimeout) {
                MainActor.assumeIsolated {
                    guard once.claim() else { return }
                    Self.logger.error("DIAL request timed out in the page")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    fileprivate func dialDidBecomeReady() {
        guard !isDIALReady else { return }
        isDIALReady = true
        Self.logger.info("Leanback registered its DIAL handlers")
    }

    fileprivate func navigationDidStart() {
        isDIALReady = false
    }

    // MARK: Delegate callbacks

    fileprivate func didFinishLoading() {
        phase = .ready
        // A reload resets the page's values.
        if volumeLevel != 100 || volumeMuted { applyVolume() }
    }

    fileprivate func didFail(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        Self.logger.error("YouTube failed to load: \(error.localizedDescription, privacy: .public)")
        isDIALReady = false
        phase = .failed(error.localizedDescription)
    }

    fileprivate func contentProcessDidTerminate() {
        Self.logger.error("YouTube web content process terminated; reloading")
        isDIALReady = false
        reload()
    }

    fileprivate func pageDidExit() {
        Self.logger.info("YouTube exited")
        onExit?()
    }

    /// The page's native messages (`mmtvl`: leanback exited; `mmtvlDial`: its DIAL handlers are ready), from the
    /// sending frame's main-frame flag and security origin. Others are ignored silently (security review item 8).
    func receiveMessage(name: String, body: Any, isMainFrame: Bool, scheme: String, host: String) {
        guard YouTubeConfig.acceptsMessage(isMainFrame: isMainFrame, scheme: scheme, host: host) else { return }
        switch name {
        case YouTubeKeyMap.messageHandlerName:
            pageDidExit()
        case YouTubeDIAL.messageHandlerName:
            let body = body as? [String: Any]
            if body?["type"] as? String == "ready", body?["app"] as? String == DIALRouting.appName {
                dialDidBecomeReady()
            }
        default:
            break
        }
    }
}

/// WebKit delegates. Separate object holding the controller weakly, because the
/// user content controller retains its message handler (no retain cycle).
private final class YouTubeWebDelegate: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var controller: YouTubeController?

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        guard YouTubeConfig.allowsNavigation(to: url, isMainFrame: isMainFrame) else {
            YouTubeController.logger.info("Blocked navigation to \(LogURL.host(url), privacy: .public)")
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        controller?.navigationDidStart()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        controller?.didFinishLoading()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        controller?.didFail(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        controller?.didFail(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        controller?.contentProcessDidTerminate()
    }

    func webViewDidClose(_ webView: WKWebView) {
        controller?.pageDidExit()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        YouTubeController.logger.info("Ignored popup to \(LogURL.host(navigationAction.request.url), privacy: .public)")
        return nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        controller?.receiveMessage(name: message.name, body: message.body, isMainFrame: message.frameInfo.isMainFrame,
                                   scheme: origin.protocol, host: origin.host)
    }
}

/// Resumes a continuation exactly once (a page answer races the timeout).
private final class ResumeOnce {
    private var claimed = false

    func claim() -> Bool {
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
