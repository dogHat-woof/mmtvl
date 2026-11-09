import Carbon.HIToolbox
import Foundation
import Testing
@testable import MMTVL

/// Settings → Remote Buttons (M7 D27, L8–L11).
struct SettingsRemoteButtonsTests {
    private let f5 = InputBinding.Trigger.key(keyCode: UInt16(kVK_F5), modifiers: [])
    private let escape = InputBinding.Trigger.key(keyCode: UInt16(kVK_Escape), modifiers: [])
    private let homeKey = InputBinding.Trigger.key(keyCode: UInt16(kVK_Home), modifiers: [])

    /// A model on the Select command page, with a controllable clock.
    private func onCommandPage(_ command: RemoteCommand = .select, trusted: Bool = true,
                               bindings: KeyBindings = .defaults) -> (SettingsModel, SettingsRecorder, Clock) {
        let (model, recorder) = makeSettingsModel(trusted: trusted, bindings: bindings)
        let clock = Clock()
        model.now = { clock.now }
        model.perform(.push(.remoteButtons))
        model.perform(.push(.remoteCommand(command)))
        return (model, recorder, clock)
    }

    final class Clock {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    @Test func rootHasTheRemoteButtonsRow() {
        let (model, _) = makeSettingsModel()
        model.open(.remoteInput)
        #expect(model.row(id: "remoteButtons")?.action == .push(.remoteButtons))
        let ids = model.focusableRowIDs
        #expect(ids.firstIndex(of: "remoteButtons") == ids.firstIndex(of: "controllers")! + 1)
        #expect(ids.firstIndex(of: "channelUp") == ids.firstIndex(of: "remoteButtons")! + 1)
    }

    @Test func commandRowsListTheirButtons() {
        let (model, _) = makeSettingsModel()
        model.perform(.push(.remoteButtons))
        #expect(model.pageTitle == "Remote Buttons")
        let commandRowIDs = RemoteCommand.allCases.map { "command.\($0.rawValue)" }
        #expect(Array(model.focusableRowIDs.prefix(commandRowIDs.count)) == commandRowIDs)
        #expect(model.row(id: "command.select")?.value == "Return · Keypad Enter +1")
        #expect(model.row(id: "command.channelUp")?.value == "Page Up · Controller Right Trigger")
        #expect(model.row(id: "command.menu")?.title == "Menu")
        #expect(model.row(id: "restoreButtons")?.action == .push(.confirmRestoreButtons))

        let (empty, _) = makeSettingsModel(bindings: KeyBindings.defaults.removing(.controller(button: .x))
            .removing(.key(keyCode: UInt16(kVK_Space), modifiers: [])).removing(.media(key: .playPause)))
        empty.perform(.push(.remoteButtons))
        #expect(empty.row(id: "command.playPause")?.value == "None")
    }

    @Test func commandPageRows() {
        let (model, _, _) = onCommandPage(.home)
        #expect(model.pageTitle == "Home")
        #expect(model.row(id: "binding.0")?.title == "Home")
        #expect(model.row(id: "binding.0")?.detail == "Keyboard · Works in other apps")
        #expect(model.row(id: "binding.1")?.title == "Controller Home")
        #expect(model.row(id: "learn")?.action == .startLearning(.home))
        #expect(model.sections.first?.footer == "Home buttons can work in other apps too (needs Accessibility).")
    }

    @Test func learnPageSetsTheHandlerAndBackClearsIt() {
        let (model, recorder, _) = onCommandPage()
        model.perform(.startLearning(.select))
        #expect(model.page == .learnButton(.select))
        #expect(model.pageTitle == "Press a Button")
        #expect(recorder.learningHandler != nil)
        #expect(model.focusedRowID == "learn.cancel")
        model.press(.back)
        #expect(model.page == .remoteCommand(.select))
        #expect(recorder.learningHandler == nil)
        #expect(recorder.learningCalls == [true, false])
    }

    @Test func aCaptureShowsTheConfirmPage() throws {
        let (model, recorder, _) = onCommandPage()
        model.perform(.startLearning(.select))
        let handler = try #require(recorder.learningHandler)
        handler(f5)
        #expect(model.page == .confirmLearn(.select, f5))
        #expect(model.pageTitle == "Use F5 for Select?")
        #expect(recorder.learningHandler == nil)
        #expect(model.row(id: "confirm.use")?.detail == nil)
        // A second capture (e.g. the event tap and the monitor both) is ignored.
        handler(escape)
        #expect(model.page == .confirmLearn(.select, f5))
        #expect(model.stack.count == 4)
    }

    @Test func selectIsIgnoredRightAfterTheConfirmPageAppears() throws {
        let (model, recorder, clock) = onCommandPage()
        model.perform(.startLearning(.select))
        let handler = try #require(recorder.learningHandler)
        handler(f5)
        #expect(model.focusedRowID == "confirm.use")
        clock.now += 0.3
        model.press(.select)
        #expect(model.page == .confirmLearn(.select, f5))
        #expect(recorder.appliedBindings.isEmpty)

        clock.now += 0.4
        model.press(.select)
        #expect(model.page == .remoteCommand(.select))
        let applied = try #require(recorder.appliedBindings.last)
        #expect(applied.binding(matching: f5)?.command == .select)
        #expect(model.bindings == applied)
        #expect(model.focusedRowID == "binding.3")
        #expect(model.row(id: "binding.3")?.title == "F5")
    }

    @Test func aButtonUsedElsewhereMoves() throws {
        let (model, recorder, clock) = onCommandPage(.menu)
        model.perform(.startLearning(.menu))
        let handler = try #require(recorder.learningHandler)
        handler(escape)
        #expect(model.row(id: "confirm.use")?.detail == "Now used for Back; it moves to Menu")
        clock.now += 1
        model.press(.select)
        #expect(model.bindings.binding(matching: escape)?.command == .menu)
        #expect(model.bindings.bindings(for: .back).count == 2)   // Delete and Controller B stay
    }

    @Test func aButtonAlreadyUsedForTheSameCommand() throws {
        let (model, recorder, _) = onCommandPage()
        model.perform(.startLearning(.select))
        let handler = try #require(recorder.learningHandler)
        handler(.controller(button: .a))
        #expect(model.row(id: "confirm.use")?.detail == "Already used for Select")
    }

    @Test func tryAgainReturnsToTheLearnPage() throws {
        let (model, recorder, _) = onCommandPage()
        model.perform(.startLearning(.select))
        let handler = try #require(recorder.learningHandler)
        handler(f5)
        model.activate(rowID: "confirm.retry")
        #expect(model.page == .learnButton(.select))
        #expect(model.stack.count == 4)
        #expect(recorder.learningHandler != nil)
    }

    @Test func learningTimesOut() async throws {
        let (model, recorder, _) = onCommandPage()
        model.learnTimeout = .milliseconds(10)
        model.perform(.startLearning(.select))
        await model.learnTimeoutTask?.value
        #expect(model.page == .remoteCommand(.select))
        #expect(recorder.learningHandler == nil)
        #expect(model.row(id: "learn")?.detail == "No button pressed")
        model.perform(.push(.remoteBinding(.select, .controller(button: .a))))
        model.press(.back)
        #expect(model.row(id: "learn")?.detail == nil)
    }

    @Test func leavingTheLearnPageCancelsTheTimeout() async throws {
        let (model, _, _) = onCommandPage()
        model.learnTimeout = .milliseconds(10)
        model.perform(.startLearning(.select))
        let task = model.learnTimeoutTask
        model.press(.back)
        await task?.value
        #expect(model.page == .remoteCommand(.select))
        #expect(model.row(id: "learn")?.detail == nil)
    }

    @Test func removeAButton() {
        let (model, recorder, _) = onCommandPage()
        model.perform(.push(.remoteBinding(.select, .controller(button: .a))))
        #expect(model.pageTitle == "Controller A")
        #expect(model.row(id: "binding.global") == nil)
        model.activate(rowID: "binding.remove")
        #expect(model.page == .remoteCommand(.select))
        #expect(recorder.appliedBindings.last?.binding(matching: .controller(button: .a)) == nil)
    }

    @Test func theLastSelectCantBeRemoved() {
        let only = KeyBindings.defaults.removing(.controller(button: .a))
            .removing(.key(keyCode: UInt16(kVK_ANSI_KeypadEnter), modifiers: []))
        let (model, recorder, _) = onCommandPage(bindings: only)
        let returnKey = InputBinding.Trigger.key(keyCode: UInt16(kVK_Return), modifiers: [])
        model.perform(.push(.remoteBinding(.select, returnKey)))
        #expect(model.row(id: "binding.remove") == nil)
        #expect(model.row(id: "binding.cantRemove")?.title == "The last button for Select can't be removed")
        #expect(model.focusableRowIDs.isEmpty)
        model.perform(.removeBinding(returnKey))
        #expect(recorder.appliedBindings.isEmpty)
    }

    @Test func homeButtonsToggleWorksInOtherApps() {
        let (model, recorder, _) = onCommandPage(.home, trusted: false)
        model.perform(.push(.remoteBinding(.home, homeKey)))
        #expect(model.row(id: "binding.global")?.value == "On")
        #expect(model.row(id: "binding.global")?.detail == "Needs Accessibility access")
        model.activate(rowID: "binding.global")
        #expect(recorder.appliedBindings.last?.binding(matching: homeKey)?.isGlobal == false)
        #expect(model.row(id: "binding.global")?.value == "Off")
        #expect(model.page == .remoteBinding(.home, homeKey))
    }

    @Test func restoreDefaultButtons() {
        let (model, recorder) = makeSettingsModel(bindings: KeyBindings.defaults.removing(homeKey))
        model.perform(.push(.remoteButtons))
        model.activate(rowID: "restoreButtons")
        #expect(model.page == .confirmRestoreButtons)
        #expect(model.focusedRowID == "confirm.cancel")
        model.activate(rowID: "confirm.restoreButtons")
        #expect(recorder.appliedBindings == [.defaults])
        #expect(model.page == .remoteButtons)
    }

    @Test func closingSettingsStopsLearning() {
        let (model, recorder, _) = onCommandPage()
        model.perform(.startLearning(.select))
        model.screenDidClose()
        #expect(recorder.learningHandler == nil)
        model.reset()
        #expect(recorder.learningCalls == [true, false])
    }
}
