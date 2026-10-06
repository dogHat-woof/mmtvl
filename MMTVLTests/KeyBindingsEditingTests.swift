import Carbon.HIToolbox
import Testing
@testable import MMTVL

struct KeyBindingsEditingTests {
    private let f5 = InputBinding.Trigger.key(keyCode: UInt16(kVK_F5), modifiers: [])
    private let escape = InputBinding.Trigger.key(keyCode: UInt16(kVK_Escape), modifiers: [])
    private let returnKey = InputBinding.Trigger.key(keyCode: UInt16(kVK_Return), modifiers: [])
    private let homeKey = InputBinding.Trigger.key(keyCode: UInt16(kVK_Home), modifiers: [])

    @Test func bindingsForACommandKeepFileOrder() {
        let select = KeyBindings.defaults.bindings(for: .select).map(\.trigger)
        #expect(select == [returnKey, .key(keyCode: UInt16(kVK_ANSI_KeypadEnter), modifiers: []), .controller(button: .a)])
    }

    @Test func addingMovesATriggerFromAnotherCommand() {
        let edited = KeyBindings.defaults.adding(escape, for: .menu)
        #expect(edited.binding(matching: escape)?.command == .menu)
        #expect(edited.bindings.filter { $0.trigger.matches(escape) }.count == 1)
        #expect(edited.bindings.last?.label == "Escape")
        #expect(edited.bindings.last?.isGlobal == false)
        #expect(edited.bindings.count == KeyBindings.defaults.bindings.count)
    }

    @Test func addingNormalizesModifiersAndMakesHomeGlobal() {
        let trigger = InputBinding.Trigger.key(keyCode: UInt16(kVK_F5), modifiers: [.shift, .option])
        let edited = KeyBindings.defaults.adding(trigger, for: .home)
        let added = edited.bindings.last
        #expect(added?.trigger == .key(keyCode: UInt16(kVK_F5), modifiers: [.option, .shift]))
        #expect(added?.isGlobal == true)
        #expect(added?.label == "⌥⇧ F5")
    }

    @Test func removingRemovesEveryDuplicate() {
        let doubled = KeyBindings(KeyBindings.defaultBindings + [InputBinding(trigger: .key(keyCode: UInt16(kVK_F5), modifiers: []), command: .select),
                                                                InputBinding(trigger: f5, command: .back)])
        let edited = doubled.removing(f5)
        #expect(edited.binding(matching: f5) == nil)
        #expect(edited == KeyBindings.defaults)
    }

    @Test func settingGlobal() {
        let edited = KeyBindings.defaults.settingGlobal(false, for: homeKey)
        #expect(edited.binding(matching: homeKey)?.isGlobal == false)
        #expect(edited.settingGlobal(true, for: homeKey) == KeyBindings.defaults)
    }

    @Test func theLastEssentialButtonCantBeRemoved() {
        let onlyReturn = KeyBindings.defaults
            .removing(.key(keyCode: UInt16(kVK_ANSI_KeypadEnter), modifiers: []))
            .removing(.controller(button: .a))
        #expect(!onlyReturn.canRemove(returnKey))
        // A second Select can go.
        #expect(KeyBindings.defaults.canRemove(returnKey))
        // The last Home can go too.
        let oneHome = KeyBindings(KeyBindings.defaultBindings.filter { $0.command != .home || $0.trigger == homeKey })
        #expect(oneHome.canRemove(homeKey))
        // An unbound trigger can always be "removed".
        #expect(KeyBindings.defaults.canRemove(f5))
    }
}

struct InputRouterCaptureTests {
    @Test func captureWithoutAHandlerReturnsFalse() {
        let router = InputRouter(bindings: .defaults)
        #expect(!router.capture(.controller(button: .a)))
    }
}
