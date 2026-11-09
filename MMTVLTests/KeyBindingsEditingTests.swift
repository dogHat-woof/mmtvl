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
        #expect(select == [returnKey, .key(keyCode: UInt16(kVK_ANSI_KeypadEnter), modifiers: []), .controller(button: .a),
                           .siriRemote(button: .select)])
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
            .removing(.siriRemote(button: .select))
        #expect(!onlyReturn.canRemove(returnKey))
        // A second Select can go.
        #expect(KeyBindings.defaults.canRemove(returnKey))
        // The last Home can go too.
        let oneHome = KeyBindings(KeyBindings.defaultBindings.filter { $0.command != .home || $0.trigger == homeKey })
        #expect(oneHome.canRemove(homeKey))
        // An unbound trigger can always be "removed".
        #expect(KeyBindings.defaults.canRemove(f5))
    }

    // MARK: M7h (L2, L9)

    @Test func addingAPlainLetterToHomeStaysLocal() {
        let a = InputBinding.Trigger.key(keyCode: UInt16(kVK_ANSI_A), modifiers: [])
        let added = KeyBindings.defaults.adding(a, for: .home).binding(matching: a)
        #expect(added?.command == .home)
        #expect(added?.isGlobal == false)
        // With a modifier it's not a typing key: global like any Home.
        let shiftA = InputBinding.Trigger.key(keyCode: UInt16(kVK_ANSI_A), modifiers: [.shift])
        #expect(KeyBindings.defaults.adding(shiftA, for: .home).binding(matching: shiftA)?.isGlobal == true)
    }

    @Test func settingGlobalKeepsPlainLettersLocal() {
        let five = InputBinding.Trigger.key(keyCode: UInt16(kVK_ANSI_5), modifiers: [])
        let edited = KeyBindings.defaults.adding(five, for: .home).settingGlobal(true, for: five)
        #expect(edited.binding(matching: five)?.isGlobal == false)
        // F5 can still be made global.
        #expect(KeyBindings.defaults.adding(f5, for: .select).settingGlobal(true, for: f5).binding(matching: f5)?.isGlobal == true)
    }

    @Test func canSetGlobal() {
        let lettersAndDigits = [kVK_ANSI_A, kVK_ANSI_M, kVK_ANSI_Z, kVK_ANSI_Q, kVK_ANSI_0, kVK_ANSI_5, kVK_ANSI_9]
        for code in lettersAndDigits {
            #expect(!KeyBindings.canSetGlobal(.key(keyCode: UInt16(code), modifiers: [])))
        }
        let others = [kVK_F1, kVK_F5, kVK_F13, kVK_Home, kVK_PageUp, kVK_Escape, kVK_ANSI_Keypad5, kVK_ANSI_Minus]
        for code in others {
            #expect(KeyBindings.canSetGlobal(.key(keyCode: UInt16(code), modifiers: [])))
        }
        #expect(KeyBindings.canSetGlobal(.key(keyCode: UInt16(kVK_ANSI_A), modifiers: [.control])))
        #expect(KeyBindings.canSetGlobal(.controller(button: .a)))
        #expect(KeyBindings.canSetGlobal(.media(key: .playPause)))
        #expect(KeyBindings.canSetGlobal(.siriRemote(button: .tv)))
    }

    /// QA finding 2: L2, Siri Remote bindings are always global.
    @Test func siriRemoteBindingsStayGlobal() {
        let tv = InputBinding.Trigger.siriRemote(button: .tv)
        let edited = KeyBindings.defaults.settingGlobal(false, for: tv)
        #expect(edited.binding(matching: tv)?.isGlobal == true)
        #expect(edited == KeyBindings.defaults)
        // Other Home buttons can still be turned off.
        #expect(KeyBindings.defaults.settingGlobal(false, for: homeKey).binding(matching: homeKey)?.isGlobal == false)
    }

    @Test func addingASiriRemoteButtonIsGlobal() {
        let edited = KeyBindings.defaults.adding(.siriRemote(button: .playPause), for: .menu)
        let added = edited.binding(matching: .siriRemote(button: .playPause))
        #expect(added?.command == .menu)
        #expect(added?.isGlobal == true)
        #expect(added?.label == "Siri Remote Play/Pause")
        #expect(edited.bindings(for: .playPause).allSatisfy { $0.trigger != .siriRemote(button: .playPause) })
    }
}

struct InputRouterCaptureTests {
    @Test func captureWithoutAHandlerReturnsFalse() {
        let router = InputRouter(bindings: .defaults)
        #expect(!router.capture(.controller(button: .a)))
    }
}
