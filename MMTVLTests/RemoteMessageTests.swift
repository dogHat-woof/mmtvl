import Foundation
import Testing
@testable import MMTVL

struct RemoteMessageTests {
    private func decode(_ json: String) -> ClientMessage? {
        ClientMessage.decode(Data(json.utf8))
    }

    @Test func decodesEveryClientMessage() {
        #expect(decode(#"{"type":"hello","token":"abc"}"#) == .hello(token: "abc"))
        #expect(decode(#"{"type":"pair","code":"1234","name":"iPhone"}"#) == .pair(code: "1234", name: "iPhone"))
        #expect(decode(#"{"type":"command","command":"up"}"#) == .command(.up))
        #expect(decode(#"{"type":"command","command":"playPause"}"#) == .command(.playPause))
        #expect(decode(#"{"type":"textBegin"}"#) == .textBegin)
        #expect(decode(#"{"type":"submit"}"#) == .submit)
        #expect(decode(#"{"type":"text","value":"star wa"}"#) == .text("star wa"))
        #expect(decode(#"{"type":"volume","action":"up"}"#) == .volume(.up))
        #expect(decode(#"{"type":"volume","action":"mute"}"#) == .volume(.mute))
    }

    @Test func decodesPointerMessages() {
        #expect(decode(#"{"type":"pointer","dx":3.5,"dy":-2}"#) == .pointer(.move(dx: 3.5, dy: -2)))
        #expect(decode(#"{"type":"scroll","dx":0,"dy":12}"#) == .pointer(.scroll(dx: 0, dy: 12)))
        #expect(decode(#"{"type":"click","button":"left"}"#) == .pointer(.click(.left)))
        #expect(decode(#"{"type":"click","button":"right"}"#) == .pointer(.click(.right)))
        #expect(decode(#"{"type":"pointer","dx":1000,"dy":-1000}"#) == .pointer(.move(dx: 1000, dy: -1000)))
    }

    @Test func rejectsInvalidPointerMessages() {
        #expect(decode(#"{"type":"pointer","dx":3}"#) == nil)
        #expect(decode(#"{"type":"scroll","dy":3}"#) == nil)
        #expect(decode(#"{"type":"pointer","dx":5000,"dy":0}"#) == nil)
        #expect(decode(#"{"type":"scroll","dx":0,"dy":-1000.5}"#) == nil)
        #expect(decode(#"{"type":"click","button":"middle"}"#) == nil)
        #expect(decode(#"{"type":"click"}"#) == nil)
    }

    @Test func rejectsInvalidClientMessages() {
        #expect(decode(#"{"type":"jump"}"#) == nil)
        #expect(decode(#"{"type":"command","command":"jump"}"#) == nil)
        #expect(decode(#"{"type":"hello"}"#) == nil)
        #expect(decode(#"{"type":"pair","code":"1234"}"#) == nil)
        #expect(decode(#"{"type":"text"}"#) == nil)
        #expect(decode(#"{"type":"volume","action":"loud"}"#) == nil)
        #expect(decode(#"{"token":"abc"}"#) == nil)
        #expect(decode("not json") == nil)
    }

    private func object(_ message: ServerMessage) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: message.encoded()) as? NSDictionary)
    }

    private func object(_ json: String) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)
    }

    @Test func encodesEveryServerMessage() throws {
        #expect(try object(.welcome) == object(#"{"type":"welcome"}"#))
        #expect(try object(.authFailed) == object(#"{"type":"authFailed"}"#))
        #expect(try object(.paired(token: "tok")) == object(#"{"token":"tok","type":"paired"}"#))
        #expect(try object(.pairFailed("Wrong code")) == object(#"{"message":"Wrong code","type":"pairFailed"}"#))
        #expect(try object(.toast("Hi")) == object(#"{"message":"Hi","type":"toast"}"#))
        #expect(try object(.status(frontApp: "Plex HTPC", launcherActive: false))
            == object(#"{"frontApp":"Plex HTPC","launcherActive":false,"type":"status"}"#))
        #expect(try object(.volume(level: 0.5, muted: false)) == object(#"{"level":0.5,"muted":false,"type":"volume"}"#))
        #expect(try object(.volume(level: nil, muted: nil)) == object(#"{"type":"volume"}"#))
    }

    @Test func encodingSortsKeys() {
        let json = String(decoding: ServerMessage.status(frontApp: "Plex HTPC", launcherActive: false).encoded(), as: UTF8.self)
        #expect(json == #"{"frontApp":"Plex HTPC","launcherActive":false,"type":"status"}"#)
    }
}
