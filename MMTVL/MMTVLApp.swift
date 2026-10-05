import SwiftUI

@main
struct MMTVLApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The launcher window is owned by AppKit (D1), not SwiftUI.
        Settings { EmptyView() }
    }
}
