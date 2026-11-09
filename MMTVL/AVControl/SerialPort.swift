import Darwin
import Foundation
import IOKit
import IOKit.serial
import os

/// A serial port macOS lists (`/dev/cu.*`).
nonisolated struct SerialPortInfo: Equatable, Sendable {
    /// `/dev/cu.…`. It can name the adapter's serial number: log it at debug level only.
    var path: String
    /// The USB product name ("FT232R USB UART"), when IOKit has one.
    var usbProductName: String?
    /// On USB (not Bluetooth or the debug console): a USB product name, or `usb` in the device name.
    var isUSB: Bool

    init(path: String, usbProductName: String?) {
        self.path = path
        self.usbProductName = usbProductName
        isUSB = usbProductName != nil || path.lowercased().contains("usb")
    }

    /// For logs and Settings: "USB serial port (FT232R USB UART)", "USB serial port" or "Serial port".
    var displayName: String {
        guard isUSB else { return "Serial port" }
        return usbProductName.map { "USB serial port (\($0))" } ?? "USB serial port"
    }
}

/// Splits received bytes into lines on any of the delimiters; empty lines are dropped. Pure.
nonisolated struct SerialLineSplitter: Sendable {
    let delimiters: Set<UInt8>
    /// A line longer than this is dropped, up to the next delimiter (noise, or a stuck line).
    var maximumLength = 512
    private var pending: [UInt8] = []
    private var overflowed = false

    init(delimiters: Set<UInt8>) {
        self.delimiters = delimiters
    }

    mutating func append(_ bytes: some Sequence<UInt8>) -> [String] {
        var lines: [String] = []
        for byte in bytes {
            if delimiters.contains(byte) {
                if !pending.isEmpty, !overflowed { lines.append(String(decoding: pending, as: UTF8.self)) }
                pending.removeAll(keepingCapacity: true)
                overflowed = false
            } else if overflowed {
                continue
            } else if pending.count < maximumLength {
                pending.append(byte)
            } else {
                pending.removeAll(keepingCapacity: true)
                overflowed = true
            }
        }
        return lines
    }
}

nonisolated enum SerialPortError: Error, Equatable {
    case openFailed(Int32)
    case configureFailed(Int32)
}

/// M7h L11: a POSIX serial port (raw, no flow control), read with a `DispatchSourceRead` on the main queue.
/// `onLine` gets each received line; `onClose` once, when the port goes away (the adapter was unplugged).
final class SerialPort: ReceiverTransport {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Receiver")

    let name: String
    var onLine: ((String) -> Void)?
    var onClose: (() -> Void)?

    private var fd: Int32
    private var source: DispatchSourceRead?
    private var splitter: SerialLineSplitter

    /// Opens `path` (`/dev/cu.…`, never `tty.*`, which waits for carrier) with `settings`. `name` is for logs.
    init(path: String, name: String, settings: SerialSettings, delimiters: Set<UInt8>) throws(SerialPortError) {
        let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw .openFailed(errno) }
        guard Self.configure(fd, settings) else {
            let code = errno
            Darwin.close(fd)
            throw .configureFailed(code)
        }
        self.fd = fd
        self.name = name
        splitter = SerialLineSplitter(delimiters: delimiters)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.readAvailable() }
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        self.source = source
        source.resume()
    }

    isolated deinit {
        close()
    }

    var isOpen: Bool { source != nil }

    /// Writes all of `bytes` (a command is a few bytes; the driver's buffer takes them at once).
    @discardableResult
    func write(_ bytes: [UInt8]) -> Bool {
        guard isOpen else { return false }
        var offset = 0
        var attempts = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if written > 0 {
                offset += written
            } else if written < 0, errno == EAGAIN || errno == EINTR, attempts < 50 {
                attempts += 1
                usleep(2000)
            } else {
                Self.logger.error("Serial write failed: \(String(cString: strerror(errno)), privacy: .public)")
                return false
            }
        }
        return true
    }

    func close() {
        guard let source else { return }
        // The cancel handler closes the descriptor later on the main queue; give up exclusive use now so the port
        // can be opened again at once (Find Receiver opens it once per brand).
        _ = ioctl(fd, TIOCNXCL)
        source.cancel()
        self.source = nil
    }

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 256)
        while isOpen {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                for line in splitter.append(buffer[0..<count]) { onLine?(line) }
                continue
            }
            if count < 0, errno == EAGAIN || errno == EINTR { return }
            // 0 (end of file) or an error such as ENXIO: the adapter is gone.
            close()
            let onClose = self.onClose
            self.onClose = nil
            onClose?()
            return
        }
    }

    /// Raw mode, the baud rate, data bits, parity and stop bits; no flow control; exclusive use.
    private static func configure(_ fd: Int32, _ settings: SerialSettings) -> Bool {
        guard ioctl(fd, TIOCEXCL) == 0 else { return false }
        var options = termios()
        guard tcgetattr(fd, &options) == 0 else { return false }
        cfmakeraw(&options)
        guard cfsetspeed(&options, speed_t(settings.baud)) == 0 else { return false }
        var cflag = options.c_cflag
        cflag &= ~tcflag_t(CSIZE | PARENB | PARODD | CSTOPB)
        cflag &= ~tcflag_t(CCTS_OFLOW | CRTS_IFLOW)
        cflag |= tcflag_t(CLOCAL | CREAD)
        switch settings.dataBits {
        case 7: cflag |= tcflag_t(CS7)
        default: cflag |= tcflag_t(CS8)
        }
        switch settings.parity {
        case .none: break
        case .even: cflag |= tcflag_t(PARENB)
        case .odd: cflag |= tcflag_t(PARENB | PARODD)
        }
        if settings.stopBits == 2 { cflag |= tcflag_t(CSTOPB) }
        options.c_cflag = cflag
        options.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
        guard tcsetattr(fd, TCSANOW, &options) == 0 else { return false }
        tcflush(fd, TCIOFLUSH)
        return true
    }

    /// The `cu.*` serial ports macOS lists (IOKit), USB ports first, then by path.
    static func available() -> [SerialPortInfo] {
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary? else { return [] }
        matching[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var ports: [SerialPortInfo] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let path = IORegistryEntryCreateCFProperty(service, kIOCalloutDeviceKey as CFString,
                                                             kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String,
                path.hasPrefix("/dev/cu.") else { continue }
            let product = IORegistryEntrySearchCFProperty(
                service, kIOServicePlane, "USB Product Name" as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? String
            ports.append(SerialPortInfo(path: path, usbProductName: product))
        }
        return ports.sorted { ($0.isUSB ? 0 : 1, $0.path) < ($1.isUSB ? 0 : 1, $1.path) }
    }

    /// The port to open for `receiverSerialPort`: a `/dev/cu.*` path as given (listed or not); nil, or any other
    /// path (a hand-edited `tty.*` waits for carrier), means Automatic, the first USB port listed. Pure.
    static func port(for path: String?, available ports: [SerialPortInfo]) -> SerialPortInfo? {
        if let path {
            let name = path.dropFirst("/dev/".count)
            if path.hasPrefix("/dev/cu."), !name.contains("/") {
                return ports.first { $0.path == path } ?? SerialPortInfo(path: path, usbProductName: nil)
            }
            logger.debug("receiverSerialPort isn't a /dev/cu.* port; using the first USB serial port")
        }
        return ports.first(where: \.isUSB)
    }

    /// L11: `ReceiverController`'s factory: opens `path`, or the first USB serial port when nil, with the codec's
    /// settings. Logs the port by its USB product name, never its path (it can carry the adapter's serial number).
    static func receiverTransport(path: String?, codec: any ReceiverProtocol) -> (any ReceiverTransport)? {
        guard let info = port(for: path, available: available()) else {
            logger.debug("No USB serial port")
            return nil
        }
        do {
            let port = try SerialPort(path: info.path, name: info.displayName, settings: codec.serial,
                                      delimiters: codec.lineDelimiters)
            logger.debug("Opened \(info.displayName, privacy: .public) at \(codec.serial.baud, privacy: .public) baud")
            return port
        } catch {
            let code: Int32 = switch error {
            case .openFailed(let code), .configureFailed(let code): code
            }
            logger.debug("Can't open \(info.displayName, privacy: .public): \(String(cString: strerror(code)), privacy: .public)")
            return nil
        }
    }
}
