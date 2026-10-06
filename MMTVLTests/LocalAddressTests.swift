import Testing
@testable import MMTVL

struct LocalAddressTests {
    private typealias Interface = LocalAddress.Interface

    private func up(_ name: String, _ ip: String) -> Interface {
        Interface(name: name, ipv4: ip, isUp: true, isLoopback: false)
    }

    @Test func prefersEn0ThenEn1() {
        #expect(LocalAddress.pick([up("bridge0", "10.0.0.1"), up("en1", "192.168.1.3"), up("en0", "192.168.1.2")]) == "192.168.1.2")
        #expect(LocalAddress.pick([up("bridge0", "10.0.0.1"), up("en1", "192.168.1.3")]) == "192.168.1.3")
        #expect(LocalAddress.pick([up("en5", "10.0.0.5")]) == "10.0.0.5")
    }

    @Test func skipsLoopbackDownAndLinkLocal() {
        let interfaces = [
            Interface(name: "lo0", ipv4: "127.0.0.1", isUp: true, isLoopback: true),
            Interface(name: "en0", ipv4: "192.168.1.2", isUp: false, isLoopback: false),
            up("en1", "169.254.10.2"),
            up("utun3", "10.8.0.2"),
        ]
        #expect(LocalAddress.pick(interfaces) == "10.8.0.2")
        #expect(LocalAddress.pick(Array(interfaces.prefix(3))) == nil)
        #expect(LocalAddress.pick([]) == nil)
    }

    @Test func realInterfacesDoNotCrash() {
        _ = LocalAddress.interfaces()
        _ = LocalAddress.primaryIPv4()
    }
}
