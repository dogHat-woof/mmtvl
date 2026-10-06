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

    // MARK: M7 (D27, L7, L9)

    @Test func defaultsHaveTheNewCommands() {
        let expected: [(InputBinding.Trigger, RemoteCommand)] = [
            (.key(keyCode: UInt16(kVK_PageUp), modifiers: []), .channelUp),
            (.key(keyCode: UInt16(kVK_PageDown), modifiers: []), .channelDown),
            (.key(keyCode: UInt16(kVK_Tab), modifiers: []), .menu),
            (.key(keyCode: UInt16(kVK_ContextualMenu), modifiers: []), .menu),
            (.controller(button: .rightTrigger), .channelUp),
            (.controller(button: .leftTrigger), .channelDown),
            (.controller(button: .y), .menu),
        ]
        for (trigger, command) in expected {
            let binding = bindings.bindings.first { $0.trigger == trigger }
            #expect(binding?.command == command)
            #expect(binding?.isGlobal == false)
        }
    }

    @Test func defaultsHaveNoDuplicateTriggers() {
        let triggers = KeyBindings.defaultBindings.map(\.trigger)
        for (index, trigger) in triggers.enumerated() {
            #expect(!triggers[(index + 1)...].contains { $0.matches(trigger) })
        }
    }

    @Test func addingDefaultsAddsOnlyUnboundTriggers() {
        let new: Set<RemoteCommand> = [.menu, .channelUp, .channelDown]
        let old = KeyBindings(KeyBindings.defaultBindings.filter { !new.contains($0.command) }
            + [InputBinding(trigger: .key(keyCode: UInt16(kVK_Tab), modifiers: []), command: .select)])
        let migrated = old.addingDefaults(for: new)
        #expect(migrated.bindings.count == old.bindings.count + 6)
        // Tab stays Select.
        #expect(migrated.binding(keyCode: UInt16(kVK_Tab), modifiers: [])?.command == .select)
        #expect(migrated.binding(keyCode: UInt16(kVK_PageUp), modifiers: [])?.command == .channelUp)
        #expect(migrated.binding(controller: .y)?.command == .menu)
        // Idempotent.
        #expect(migrated.addingDefaults(for: new) == migrated)
    }

    @Test func matchesIgnoresModifierOrder() {
        let a = InputBinding.Trigger.key(keyCode: 96, modifiers: [.shift, .option])
        let b = InputBinding.Trigger.key(keyCode: 96, modifiers: [.option, .shift, .option])
        #expect(a.matches(b))
        #expect(!a.matches(.key(keyCode: 96, modifiers: [.option])))
        #expect(!a.matches(.key(keyCode: 97, modifiers: [.shift, .option])))
        #expect(InputBinding.Trigger.controller(button: .a).matches(.controller(button: .a)))
        #expect(!InputBinding.Trigger.controller(button: .a).matches(.media(key: .playPause)))
        #expect(b.normalized == .key(keyCode: 96, modifiers: [.option, .shift]))
    }
}
