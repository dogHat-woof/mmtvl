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
    @ObservationIgnored var onExit: (() -> Void)?
    @ObservationIgnored private let userAgent: String
    @ObservationIgnored private let delegate = YouTubeWebDelegate()

    init(userAgent: String) {
        self.userAgent = userAgent
        delegate.controller = self
    }

    func open() {
        guard webView == nil else { return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        for source in [YouTubeKeyMap.exitHookScript, YouTubeKeyMap.alwaysVisibleScript] {
            configuration.userContentController.addUserScript(WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        configuration.userContentController.add(delegate, name: YouTubeKeyMap.messageHandlerName)

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
        load()
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

    private func load() {
        phase = .loading
        webView?.load(URLRequest(url: YouTubeConfig.startURL))
    }

    // MARK: Delegate callbacks

    fileprivate func didFinishLoading() {
        phase = .ready
    }

    fileprivate func didFail(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        Self.logger.error("YouTube failed to load: \(error.localizedDescription, privacy: .public)")
        phase = .failed(error.localizedDescription)
    }

    fileprivate func contentProcessDidTerminate() {
        Self.logger.error("YouTube web content process terminated; reloading")
        reload()
    }

    fileprivate func pageDidExit() {
        Self.logger.info("YouTube exited")
        onExit?()
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
            YouTubeController.logger.info("Blocked navigation to \(url.absoluteString, privacy: .public)")
            return .cancel
        }
        return .allow
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
        YouTubeController.logger.info("Ignored popup to \(navigationAction.request.url?.absoluteString ?? "?", privacy: .public)")
        return nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        controller?.pageDidExit()
    }
}
