import Foundation
import Network

/// Is macOS's AirPlay Receiver on (M7b L15)?
nonisolated enum AirPlayReceiverState: Equatable, Sendable { case unknown, on, off }

/// Checks the receiver over loopback: ControlCenter answers `GET /info` on TCP 7000 with `Server: AirTunes/…`.
/// A raw connection, so no App Transport Security question; loopback needs no Local Network permission.
enum AirPlayReceiverProbe {
    private static let timeout: TimeInterval = 2
    private static let maxHeadSize = 4096

    static func check() async -> AirPlayReceiverState {
        await withCheckedContinuation { continuation in
            ProbeRun(continuation: continuation).start()
        }
    }

    /// Pure: a response head whose Server header starts with "AirTunes" (case-insensitive).
    nonisolated static func isAirPlayResponse(_ head: Data) -> Bool {
        let text = String(decoding: head, as: UTF8.self)
        for line in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            guard name.caseInsensitiveCompare("server") == .orderedSame else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return value.lowercased().hasPrefix("airtunes")
        }
        return false
    }

    /// One probe: resumes its continuation exactly once (answer, refusal or timeout).
    private final class ProbeRun {
        private let continuation: CheckedContinuation<AirPlayReceiverState, Never>
        private let connection = NWConnection(host: "127.0.0.1", port: 7000, using: .tcp)
        private var buffer = Data()
        private var finished = false

        init(continuation: CheckedContinuation<AirPlayReceiverState, Never>) {
            self.continuation = continuation
        }

        func start() {
            // The handlers keep this run alive until it finishes and cancels the connection.
            connection.stateUpdateHandler = { state in
                MainActor.assumeIsolated { self.changed(to: state) }
            }
            connection.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + AirPlayReceiverProbe.timeout) {
                MainActor.assumeIsolated { self.finish(.unknown) }
            }
        }

        private func changed(to state: NWConnection.State) {
            switch state {
            case .ready:
                let request = "GET /info HTTP/1.1\r\nHost: 127.0.0.1:7000\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(request.utf8), completion: .contentProcessed { _ in })
                receive()
            case .waiting(let error), .failed(let error):
                if case .posix(.ECONNREFUSED) = error {
                    finish(.off)
                } else if case .failed = state {
                    finish(.unknown)
                }
            default:
                break
            }
        }

        private func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: AirPlayReceiverProbe.maxHeadSize) { data, _, isComplete, error in
                MainActor.assumeIsolated {
                    if let data { self.buffer.append(data) }
                    let hasHead = self.buffer.firstRange(of: Data("\r\n\r\n".utf8)) != nil
                    if hasHead || self.buffer.count >= AirPlayReceiverProbe.maxHeadSize || isComplete || error != nil {
                        self.finish(AirPlayReceiverProbe.isAirPlayResponse(self.buffer) ? .on : .unknown)
                    } else {
                        self.receive()
                    }
                }
            }
        }

        private func finish(_ state: AirPlayReceiverState) {
            guard !finished else { return }
            finished = true
            connection.stateUpdateHandler = nil
            connection.cancel()
            continuation.resume(returning: state)
        }
    }
}
