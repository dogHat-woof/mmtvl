import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import MMTVL

struct KeyBindingsTests {
    private let bindings = KeyBindings.defaults

    @Test(arguments: [
        (kVK_UpArrow, RemoteCommand.up),
        (kVK_DownArrow, .down),
        (kVK_LeftArrow, .left),
        (kVK_RightArrow, .right),
        (kVK_Return, .select),
        (kVK_ANSI_KeypadEnter, .select),
        (kVK_Escape, .back),
        (kVK_Delete, .back),
        (kVK_Space, .playPause),
        (kVK_Home, .home),
    ])
    func mapsKey(keyCode: Int, expected: RemoteCommand) {
        #expect(bindings.command(keyCode: UInt16(keyCode), modifiers: []) == expected)
    }

    @Test func arrowKeysWithFunctionFlagStillMap() {
        // Arrow key events carry .function and .numericPad flags.
        #expect(bindings.command(keyCode: UInt16(kVK_LeftArrow), modifiers: [.function, .numericPad]) == .left)
    }

    @Test func commandModifiedKeysPassThrough() {
        #expect(bindings.command(keyCode: UInt16(kVK_RightArrow), modifiers: [.command]) == nil)
        #expect(bindings.command(keyCode: UInt16(kVK_Return), modifiers: [.command, .shift]) == nil)
    }

    @Test func homeKeyIsGlobal() throws {
        let binding = try #require(bindings.binding(keyCode: UInt16(kVK_Home), modifiers: []))
        #expect(binding.command == .home)
        #expect(binding.isGlobal)
    }

    @Test func mediaPlayPause() {
        #expect(bindings.binding(media: .playPause)?.command == .playPause)
    }

    @Test func controllerButtons() throws {
        #expect(bindings.binding(controller: .a)?.command == .select)
        let home = try #require(bindings.binding(controller: .home))
        #expect(home.command == .home)
        #expect(home.isGlobal)
    }

    @Test func unknownKeyIsNil() {
        #expect(bindings.command(keyCode: UInt16(kVK_ANSI_Q), modifiers: []) == nil)
    }

    @Test func decodesPlanJSONSample() throws {
        let json = """
        { "command" : "home", "isGlobal" : true, "label" : "Home key (fn+←)",
          "trigger" : { "key" : { "keyCode" : 115, "modifiers" : [ ] } } }
        """
        let binding = try JSONDecoder().decode(InputBinding.self, from: Data(json.utf8))
        #expect(binding == InputBinding(
            trigger: .key(keyCode: 115, modifiers: []),
            command: .home,
            isGlobal: true,
            label: "Home key (fn+←)"
        ))
    }

    @Test func missingOptionalFieldsUseDefaults() throws {
        let json = #"{ "command" : "select", "trigger" : { "controller" : { "button" : "a" } } }"#
        let binding = try JSONDecoder().decode(InputBinding.self, from: Data(json.utf8))
        #expect(binding == InputBinding(trigger: .controller(button: .a), command: .select))
    }

    @Test func defaultBindingsRoundTrip() throws {
        let data = try JSONEncoder().encode(KeyBindings.defaultBindings)
        let decoded = try JSONDecoder().decode([InputBinding].self, from: data)
        #expect(decoded == KeyBindings.defaultBindings)
    }
}
