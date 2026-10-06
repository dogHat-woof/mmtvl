import SwiftUI
import WebKit

/// The YouTube screen: the controller's web view at the window's real size (L4), plus a load-failure overlay.
struct YouTubeView: View {
    let controller: YouTubeController

    var body: some View {
        ZStack {
            Color.black
            if let webView = controller.webView {
                YouTubeWebView(webView: webView)
            }
            if case .failed(let message) = controller.phase {
                failure(message)
            }
        }
        .ignoresSafeArea()
    }

    private func failure(_ message: String) -> some View {
        ZStack {
            Color.black
            VStack(spacing: 24) {
                Text("Can't reach YouTube")
                    .font(Theme.settingsTitleFont)
                    .foregroundStyle(Theme.primaryText)
                Text(message)
                    .font(Theme.settingsDetailFont)
                    .foregroundStyle(Theme.secondaryText)
                Text("Select: try again · Home: leave")
                    .font(Theme.settingsHintFont)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 24)
            }
        }
    }
}

/// Hosts the existing web view instance, so its page survives leaving and returning (L3).
private struct YouTubeWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        // Unbound keys (letters for search) go to leanback natively.
        DispatchQueue.main.async { [webView] in
            webView.window?.makeFirstResponder(webView)
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
