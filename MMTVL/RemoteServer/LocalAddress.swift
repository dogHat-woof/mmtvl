import Darwin

/// The Mac's LAN IPv4 address for the phone URL (L12).
nonisolated enum LocalAddress {
    struct Interface: Equatable, Sendable {
        var name: String
        var ipv4: String
        var isUp: Bool
        var isLoopback: Bool
    }

    /// getifaddrs → AF_INET entries.
    static func interfaces() -> [Interface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return [] }
        defer { freeifaddrs(head) }

        var result: [Interface] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let ok = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                var addr = sin.pointee.sin_addr
                return inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil
            }
            guard ok else { continue }
            let flags = Int32(entry.pointee.ifa_flags)
            result.append(Interface(
                name: String(cString: entry.pointee.ifa_name),
                ipv4: String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self),
                isUp: flags & IFF_UP != 0 && flags & IFF_RUNNING != 0,
                isLoopback: flags & IFF_LOOPBACK != 0
            ))
        }
        return result
    }

    /// en0, then en1, then any other up, non-loopback interface; never 169.254.* (link-local).
    static func pick(_ interfaces: [Interface]) -> String? {
        let usable = interfaces.filter { $0.isUp && !$0.isLoopback && !$0.ipv4.hasPrefix("169.254.") }
        for name in ["en0", "en1"] {
            if let match = usable.first(where: { $0.name == name }) { return match.ipv4 }
        }
        return usable.first?.ipv4
    }

    static func primaryIPv4() -> String? { pick(interfaces()) }
}
