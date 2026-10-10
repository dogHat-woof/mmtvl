import AppKit
import os

/// Relaunch MMTVL from Settings (L11) through a /bin/sh helper that outlives this process.
enum AppRelauncher {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "AppRelauncher")

    /// Waits up to 10 s for `$1` (our PID) to exit, then reopens `$2` as a new instance with the remaining args.
    /// Exits without relaunching if the old process is still alive (avoids two kiosk instances / two event taps).
    nonisolated static let script = """
        i=0
        while /bin/kill -0 "$1" 2>/dev/null; do
          i=$((i+1)); [ "$i" -gt 50 ] && exit 1
          /bin/sleep 0.2
        done
        app="$2"; shift 2
        if [ "$#" -gt 0 ]; then exec /usr/bin/open -n "$app" --args "$@"; else exec /usr/bin/open -n "$app"; fi
        """

    nonisolated static func processArguments(pid: Int32, appPath: String, arguments: [String]) -> [String] {
        ["-c", script, "sh", String(pid), appPath] + arguments
    }

    /// Forwards the launch arguments, so `-windowed YES` stays windowed.
    /// `allowTermination` lifts the kiosk lock's quit guard first (M7c L9).
    static func relaunch(allowTermination: () -> Void = {}) {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = processArguments(
            pid: ProcessInfo.processInfo.processIdentifier,
            appPath: Bundle.main.bundleURL.path,
            arguments: Array(ProcessInfo.processInfo.arguments.dropFirst())
        )
        do {
            try process.run()
        } catch {
            logger.error("Failed to start the relaunch helper: \(error.localizedDescription, privacy: .public)")
            return
        }
        logger.info("Relaunching")
        allowTermination()
        NSApp.terminate(nil)
    }
}
