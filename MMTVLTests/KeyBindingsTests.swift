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

    // MARK: M7h (L2, L9)

    @Test func siriRemoteTriggerJSONRoundTrips() throws {
        let binding = InputBinding(trigger: .siriRemote(button: .tv), command: .home, isGlobal: true, label: "Siri Remote TV")
        let data = try JSONEncoder().encode(binding)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let trigger = try #require(object["trigger"] as? [String: Any])
        #expect((trigger["siriRemote"] as? [String: String]) == ["button": "tv"])
        #expect(try JSONDecoder().decode(InputBinding.self, from: data) == binding)

        let json = #"{ "command" : "volumeUp", "trigger" : { "siriRemote" : { "button" : "volumeUp" } } }"#
        let decoded = try JSONDecoder().decode(InputBinding.self, from: Data(json.utf8))
        #expect(decoded == InputBinding(trigger: .siriRemote(button: .volumeUp), command: .volumeUp))
    }

    @Test func newCommandsComeLastWithTitles() {
        #expect(Array(RemoteCommand.allCases.suffix(5)) == [.volumeUp, .volumeDown, .mute, .power, .powerMenu])
        #expect(RemoteCommand.allCases.suffix(5).map(\.title) == ["Volume Up", "Volume Down", "Mute", "Power", "Power Menu"])
        #expect(RemoteCommand(rawValue: "powerMenu") == .powerMenu)
    }

    @Test func siriRemoteDefaults() throws {
        let expected: [(SiriRemoteButton, RemoteCommand, String)] = [
            (.tv, .home, "Siri Remote TV"), (.back, .back, "Siri Remote Back"),
            (.up, .up, "Siri Remote Up"), (.down, .down, "Siri Remote Down"),
            (.left, .left, "Siri Remote Left"), (.right, .right, "Siri Remote Right"),
            (.select, .select, "Siri Remote Select"), (.playPause, .playPause, "Siri Remote Play/Pause"),
            (.volumeUp, .volumeUp, "Siri Remote Volume Up"), (.volumeDown, .volumeDown, "Siri Remote Volume Down"),
            (.mute, .mute, "Siri Remote Mute"), (.power, .power, "Siri Remote Power"),
        ]
        #expect(expected.count == SiriRemoteButton.allCases.count)
        for (button, command, label) in expected {
            let binding = try #require(bindings.binding(siriRemote: button))
            #expect(binding.command == command)
            #expect(binding.isGlobal)
            #expect(binding.label == label)
        }
        // L2: no default binds Power Menu (a long press of Power sends it).
        #expect(bindings.bindings(for: .powerMenu).isEmpty)
    }

    @Test func currentRevisionIsThree() {
        #expect(KeyBindings.currentRevision == 3)
    }

    /// The mini's file before M7h: revision 2 defaults plus Remote Buddy's "a" as a global Home (M7e).
    private var revision2WithGlobalA: KeyBindings {
        KeyBindings(KeyBindings.defaultBindings.filter { !$0.trigger.isSiriRemote }
            + [InputBinding(trigger: .key(keyCode: 0, modifiers: []), command: .home, isGlobal: true, label: "A")])
    }

    @Test func revision2MigratesWithoutGlobalLetterAndWithSiriRemote() throws {
        let json = #"[{ "command" : "home", "isGlobal" : true, "label" : "A", "trigger" : { "key" : { "keyCode" : 0, "modifiers" : [ ] } } }]"#
        let fromFile = try JSONDecoder().decode([InputBinding].self, from: Data(json.utf8))
        let old = KeyBindings(KeyBindings.defaultBindings.filter { !$0.trigger.isSiriRemote } + fromFile)
        #expect(old == revision2WithGlobalA)

        let migration = old.migrated(fromRevision: 2)
        let migrated = migration.bindings
        #expect(migrated.binding(keyCode: 0, modifiers: []) == nil)
        #expect(migration.removedGlobal == fromFile)
        for button in SiriRemoteButton.allCases {
            #expect(migrated.binding(siriRemote: button) == KeyBindings.defaults.binding(siriRemote: button))
        }
        #expect(migrated == KeyBindings.defaults)
        // Idempotent: a second run changes nothing.
        let again = migrated.migrated(fromRevision: 2)
        #expect(again.bindings == migrated)
        #expect(again.removedGlobal.isEmpty)
    }

    @Test func migrationAddsOnlySiriRemoteTriggers() {
        // The user removed the Home key and Escape; revision 3 doesn't bring them back.
        let old = KeyBindings(KeyBindings.defaultBindings.filter {
            !$0.trigger.isSiriRemote && $0.label != "Home key (fn+←)" && $0.label != "Escape"
        })
        let migrated = old.migrated(fromRevision: 2).bindings
        #expect(migrated.binding(keyCode: UInt16(kVK_Home), modifiers: []) == nil)
        #expect(migrated.binding(keyCode: UInt16(kVK_Escape), modifiers: []) == nil)
        #expect(migrated.bindings.count == old.bindings.count + SiriRemoteButton.allCases.count)
        #expect(migrated.bindings.suffix(SiriRemoteButton.allCases.count).allSatisfy { $0.trigger.isSiriRemote })
    }

    @Test func migrationKeepsLocalLettersAndModifiedGlobals() {
        let localA = InputBinding(trigger: .key(keyCode: UInt16(kVK_ANSI_A), modifiers: []), command: .select)
        let global7 = InputBinding(trigger: .key(keyCode: UInt16(kVK_ANSI_7), modifiers: []), command: .home, isGlobal: true)
        let globalShiftA = InputBinding(trigger: .key(keyCode: UInt16(kVK_ANSI_A), modifiers: [.shift]), command: .home, isGlobal: true)
        let globalF13 = InputBinding(trigger: .key(keyCode: UInt16(kVK_F13), modifiers: []), command: .home, isGlobal: true)
        let old = KeyBindings(KeyBindings.defaultBindings.filter { !$0.trigger.isSiriRemote } + [localA, global7, globalShiftA, globalF13])
        let migration = old.migrated(fromRevision: 2)
        #expect(migration.removedGlobal == [global7])
        #expect(migration.bindings.bindings.contains(localA))
        #expect(migration.bindings.bindings.contains(globalShiftA))
        #expect(migration.bindings.bindings.contains(globalF13))
    }

    @Test func revision1GetsBothMigrations() {
        let old = KeyBindings(KeyBindings.defaultBindings.filter {
            !$0.trigger.isSiriRemote && ![.menu, .channelUp, .channelDown].contains($0.command)
        })
        #expect(old.migrated(fromRevision: 1).bindings == KeyBindings.defaults)
    }

    // MARK: M7h QA finding 1: rollback and unreadable entries

    @Test func unreadableEntriesAreSkipped() throws {
        let json = """
        [
          { "command" : "home", "isGlobal" : true, "trigger" : { "siriRemote" : { "button" : "tv" } } },
          { "command" : "home", "isGlobal" : true, "trigger" : { "siriRemote" : { "button" : "siri" } } },
          { "command" : "select", "trigger" : { "controller" : { "button" : "a" } } },
          { "command" : "teleport", "trigger" : { "key" : { "keyCode" : 96, "modifiers" : [ ] } } },
          { "command" : "back", "trigger" : { "remoteBuddy" : { "button" : "menu" } } },
          { "command" : "back", "trigger" : { "key" : { "keyCode" : 53, "modifiers" : [ ] } } }
        ]
        """
        let stored = try JSONDecoder().decode(StoredBindings.self, from: Data(json.utf8))
        #expect(stored.skippedCount == 3)
        #expect(stored.bindings == [
            InputBinding(trigger: .siriRemote(button: .tv), command: .home, isGlobal: true),
            InputBinding(trigger: .controller(button: .a), command: .select),
            InputBinding(trigger: .key(keyCode: 53, modifiers: []), command: .back),
        ])
    }

    @Test func storedBindingsKeepTheFileFormat() throws {
        let data = try JSONEncoder().encode(StoredBindings(KeyBindings.defaultBindings))
        #expect(try JSONDecoder().decode([InputBinding].self, from: data) == KeyBindings.defaultBindings)
        let decoded = try JSONDecoder().decode(StoredBindings.self, from: data)
        #expect(decoded.bindings == KeyBindings.defaultBindings)
        #expect(decoded.skippedCount == 0)
    }

    @Test func aFileThatIsntAnArrayIsStillCorrupt() {
        #expect(throws: (any Error).self) { try JSONDecoder().decode(StoredBindings.self, from: Data(#"{"bindings":[]}"#.utf8)) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(StoredBindings.self, from: Data("[ not json".utf8)) }
    }

    private func temporaryBindingsFile() throws -> (JSONConfigFile<StoredBindings>, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "KeyBindingsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = JSONConfigFile(url: directory.appending(path: KeyBindings.fileName),
                                  defaultValue: StoredBindings(KeyBindings.defaultBindings))
        return (file, directory)
    }

    @Test func aFileWithAnUnknownSiriRemoteButtonIsntCorrupt() throws {
        let (file, directory) = try temporaryBindingsFile()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = Data("""
        [
          { "command" : "home", "isGlobal" : true, "trigger" : { "siriRemote" : { "button" : "siri" } } },
          { "command" : "menu", "trigger" : { "key" : { "keyCode" : 96, "modifiers" : [ ] } } }
        ]
        """.utf8)
        try original.write(to: file.url)
        let loaded = file.load()
        #expect(loaded.bindings == [InputBinding(trigger: .key(keyCode: 96, modifiers: []), command: .menu)])
        #expect(loaded.skippedCount == 1)
        // Not moved away and not replaced with the defaults.
        #expect(try Data(contentsOf: file.url) == original)
        #expect(!FileManager.default.fileExists(atPath: file.backupURL.path))
    }

    /// QA finding (re-verify) 2: skipped entries are kept in .bak before the first save drops them.
    @Test func skippedEntriesAreBackedUpBeforeTheFirstSave() throws {
        let (file, directory) = try temporaryBindingsFile()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = Data("""
        [
          { "command" : "power", "isGlobal" : true, "trigger" : { "siriRemote" : { "button" : "siri" } } },
          { "command" : "select", "trigger" : { "controller" : { "button" : "a" } } }
        ]
        """.utf8)
        try original.write(to: file.url)
        let loaded = StoredBindings.load(from: file)
        #expect(loaded.skippedCount == 1)
        #expect(loaded.bindings == [InputBinding(trigger: .controller(button: .a), command: .select)])
        try file.save(StoredBindings(KeyBindings(loaded.bindings).addingSiriRemoteDefaults().bindings))
        try file.save(StoredBindings(KeyBindings.defaultBindings))   // a later save leaves the backup alone
        #expect(try Data(contentsOf: file.backupURL) == original)
        #expect(file.load().skippedCount == 0)
    }

    @Test func aFileWithoutSkippedEntriesIsntBackedUp() throws {
        let (file, directory) = try temporaryBindingsFile()
        defer { try? FileManager.default.removeItem(at: directory) }
        try file.save(StoredBindings(KeyBindings.defaultBindings))
        #expect(StoredBindings.load(from: file).bindings == KeyBindings.defaultBindings)
        #expect(!FileManager.default.fileExists(atPath: file.backupURL.path))
    }

    /// QA finding (re-verify) 1: nothing readable at all is a corrupt file, as before M7h.
    @Test func anArrayWithNoReadableEntryIsCorrupt() throws {
        let (file, directory) = try temporaryBindingsFile()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = Data(#"[{"command":"teleport","trigger":{"key":{"keyCode":96,"modifiers":[]}}}]"#.utf8)
        try original.write(to: file.url)
        let loaded = StoredBindings.load(from: file)
        #expect(loaded.bindings == KeyBindings.defaultBindings)
        #expect(loaded.skippedCount == 0)
        #expect(try Data(contentsOf: file.backupURL) == original)
        #expect(try JSONDecoder().decode([InputBinding].self, from: Data(contentsOf: file.url)) == KeyBindings.defaultBindings)
        // An empty array is still just no bindings.
        #expect(try JSONDecoder().decode(StoredBindings.self, from: Data("[]".utf8)).bindings.isEmpty)
    }

    @Test func aRevision3FileWithoutSiriRemoteGetsOnlyItsDefaults() {
        // What an older build writes after a rollback: its own defaults (no Siri Remote), revision 3 kept.
        let rolledBack = KeyBindings(KeyBindings.defaultBindings.filter { !$0.trigger.isSiriRemote })
        #expect(!rolledBack.hasSiriRemoteBindings)
        #expect(rolledBack.migrated(fromRevision: 3).bindings == rolledBack)   // migration doesn't run
        let restored = rolledBack.addingSiriRemoteDefaults()
        #expect(restored.hasSiriRemoteBindings)
        #expect(restored == KeyBindings.defaults)
        #expect(Array(restored.bindings.prefix(rolledBack.bindings.count)) == rolledBack.bindings)
        #expect(restored.bindings.dropFirst(rolledBack.bindings.count).allSatisfy { $0.trigger.isSiriRemote })
        // The user's other edits stay: a removed Home key isn't brought back.
        let edited = KeyBindings(rolledBack.bindings.filter { $0.label != "Home key (fn+←)" })
        #expect(edited.addingSiriRemoteDefaults().bindings.count == edited.bindings.count + SiriRemoteButton.allCases.count)
        #expect(edited.addingSiriRemoteDefaults().binding(keyCode: UInt16(kVK_Home), modifiers: []) == nil)
        #expect(KeyBindings.defaults.hasSiriRemoteBindings)
    }

    @Test func currentRevisionMigratesToItself() {
        #expect(revision2WithGlobalA.migrated(fromRevision: 3).bindings == revision2WithGlobalA)
        #expect(revision2WithGlobalA.migrated(fromRevision: 3).removedGlobal.isEmpty)
    }
}
