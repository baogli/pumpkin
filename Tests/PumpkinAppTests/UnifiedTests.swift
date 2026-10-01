import AppKit
import Carbon
import Foundation
import Testing
import PumpkinCore
@testable import PumpkinApp

@MainActor @Suite(.serialized) struct UnifiedTests {
    @MainActor struct Fixture {
        let folder: URL
        let defaults: UserDefaults
        let suite: String
        let store: StateStore
        init() throws {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("PumpkinV2Test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            suite = "PumpkinV2Test-\(UUID().uuidString)"; defaults = UserDefaults(suiteName: suite)!
            defaults.set(false, forKey: "watchScreenshots"); defaults.set(false, forKey: "playSound")
            store = StateStore(url: folder.appendingPathComponent("state.json"))
        }
        func write(_ name: String) throws -> URL { let url = folder.appendingPathComponent(name); try Data("demo".utf8).write(to: url); return url }
        func model() -> AppModel { let prefs = Preferences(defaults: defaults); prefs.customFolderPath = folder.path; return AppModel(prefs: prefs, store: store) }
        func remove() { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
    }

    @Test func clipboardRejectsProtectedAndEmptyText() {
        var tail = ClipboardTail()
        tail.capture("  \n\t", types: [])
        for type in ClipboardTail.excludedTypes { tail.capture("secret", types: [type]) }
        #expect(tail.entries.isEmpty)
        tail.capture("normal", types: []); #expect(tail.entries.count == 1)
    }
    @Test func clipboardDeduplicatesAndKeepsOnlySixty() {
        var tail = ClipboardTail()
        for i in 0..<70 { tail.capture("text \(i)", types: []) }
        #expect(tail.entries.count == 60); #expect(tail.entries.last?.text == "text 10")
        tail.capture("text 30", types: []); #expect(tail.entries.first?.text == "text 30"); #expect(tail.entries.count == 60)
        tail.clear(); #expect(tail.entries.isEmpty)
    }
    @Test func historyPauseAndOwnCopyDoNotCapture() {
        let board = NSPasteboard(name: .init("PumpkinTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let history = ClipboardHistory(pasteboard: board); history.setEnabled(true)
        board.clearContents(); board.setString("first", forType: .string); history.poll()
        history.paused = true; board.clearContents(); board.setString("paused", forType: .string); history.poll()
        history.paused = false; history.poll(); #expect(history.entries.map(\.text) == ["first"])
        history.copy(history.entries[0]); history.poll(); #expect(history.entries.count == 1)
        history.setEnabled(false); #expect(history.entries.isEmpty); #expect(board.string(forType: .string) == "first")
    }
    @Test func captureChecksEveryPasteboardItemForProtectedTypes() {
        let board = NSPasteboard(name: .init("PumpkinTests-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        let history = ClipboardHistory(pasteboard: board); history.setEnabled(true)
        let plain = NSPasteboardItem(); plain.setString("should not save", forType: .string)
        let concealed = NSPasteboardItem(); concealed.setString("1", forType: .init("org.nspasteboard.ConcealedType"))
        board.clearContents(); board.writeObjects([plain, concealed]); history.poll()
        #expect(history.entries.isEmpty); history.setEnabled(false)
    }
    @Test func temporaryPasteboardIsNotCaptured() {
        let board = NSPasteboard(name: .init("PumpkinTests-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        let history = ClipboardHistory(pasteboard: board); history.setEnabled(true)
        let item = NSPasteboardItem(); item.setString("own insert", forType: .string); item.setString("token", forType: .pumpkinTemporary)
        board.clearContents(); board.writeObjects([item]); history.poll(); #expect(history.entries.isEmpty); history.setEnabled(false)
    }
    @Test func pasteboardSnapshotRestoresAllRepresentations() {
        let board = NSPasteboard(name: .init("PumpkinTests-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        let item = NSPasteboardItem(); item.setString("original", forType: .string); item.setData(Data([1, 2, 3]), forType: .init("test.binary"))
        board.clearContents(); board.writeObjects([item]); let snapshot = PasteboardSnapshot(board)
        board.clearContents(); board.setString("chosen", forType: .string); board.setString("token", forType: .pumpkinTemporary)
        #expect(snapshot.restore(to: board, ifOwnedBy: "token", changeCount: board.changeCount))
        #expect(board.string(forType: .string) == "original"); #expect(board.data(forType: .init("test.binary")) == Data([1, 2, 3]))
    }
    @Test func newerUserCopyWinsOverDelayedRestore() {
        let board = NSPasteboard(name: .init("PumpkinTests-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        board.clearContents(); board.setString("original", forType: .string); let snapshot = PasteboardSnapshot(board)
        board.clearContents(); board.setString("chosen", forType: .string); board.setString("token", forType: .pumpkinTemporary); let owned = board.changeCount
        board.clearContents(); board.setString("new user copy", forType: .string)
        #expect(!snapshot.restore(to: board, ifOwnedBy: "token", changeCount: owned)); #expect(board.string(forType: .string) == "new user copy")
    }
    @Test func pendingRecordingIsProtectedBeforeFileExists() throws {
        let f = try Fixture(); defer { f.remove() }; let model = f.model(); let url = f.folder.appendingPathComponent("video.mp4")
        let id = try model.beginRecording(url: url, screen: "Display", audio: "No audio", format: "H.264")
        #expect(f.store.load().recordings.first?.id == id)
        try Data("video".utf8).write(to: url)
        model.handleNewItems([FolderScanner.snapshot(of: url)!], kind: .download)
        #expect(model.prompts.isEmpty); #expect(model.items.isEmpty)
    }
    @Test func finishedRecordingIsProtectedAfterRestartAndRename() throws {
        let f = try Fixture(); defer { f.remove() }; let model = f.model(); let url = try f.write("video.mp4")
        let id = try model.beginRecording(url: url, screen: "Display", audio: "No audio", format: "MP4"); model.finishRecording(id, duration: 3)
        let renamed = f.folder.appendingPathComponent("renamed.mp4"); try FileManager.default.moveItem(at: url, to: renamed)
        let restored = f.model(); restored.handleNewItems([FolderScanner.snapshot(of: renamed)!], kind: .download)
        #expect(restored.prompts.isEmpty); #expect(restored.recordings[0].locatedURL?.lastPathComponent == "renamed.mp4")
    }
    @Test func similarDownloadNameIsNotProtected() throws {
        let f = try Fixture(); defer { f.remove() }; let model = f.model(); let url = try f.write("Recording_download.mp4")
        model.handleNewItems([FolderScanner.snapshot(of: url)!], kind: .download)
        #expect(model.prompts.count == 1)
    }
    @Test func partialMp4NeverGetsAutomaticExpiry() throws {
        let f = try Fixture(); defer { f.remove() }; let model = f.model(); let url = try f.write("unfinished.partial.mp4")
        #expect(DownloadFilter.isIgnorable(name: url.lastPathComponent))
        model.handleNewItems([FolderScanner.snapshot(of: url)!], kind: .download); #expect(model.prompts.isEmpty)
    }
    @Test func explicitRecordingExpiryUsesSingleObjectAndPauseClock() throws {
        let f = try Fixture(); defer { f.remove() }; let model = f.model(); let url = try f.write("video.mp4")
        let id = try model.beginRecording(url: url, screen: "Display", audio: "No audio", format: "MP4"); model.finishRecording(id, duration: 3)
        model.togglePause(); model.scheduleRecording(id, duration: .minutes(10)); model.scheduleRecording(id, duration: .hours(1))
        #expect(model.items.count == 1); #expect(model.items[0].remaining(at: model.clock(Date())) == 3600)
        #expect(model.items[0].folderPath == f.folder.path); model.keepForever(model.items[0].id)
        #expect(model.items.isEmpty); #expect(FileManager.default.fileExists(atPath: url.path))
    }
    @Test func hiddenQuestionSurvivesRestartWithoutTimer() async throws {
        let f = try Fixture(); defer { f.remove() }; let model = f.model(); model.prefs.promptTimeout = 0.05; model.prefs.unansweredPolicy = .useDefault
        model.automaticPanelsSuppressed = true
        let url = try f.write("notes.pdf"); model.handleNewItems([FolderScanner.snapshot(of: url)!], kind: .download)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(model.items.isEmpty); #expect(model.promptDeadline == nil); #expect(model.prompts.count == 1)
        let restored = f.model(); #expect(restored.prompts.count == 1); #expect(restored.items.isEmpty)
        restored.keep(restored.prompts[0].id); #expect(f.store.load().pendingGroups.isEmpty)
    }
    @Test func pausedTimersStillCollectUnansweredQuestions() throws {
        let f = try Fixture(); defer { f.remove() }; let model = f.model(); model.togglePause()
        let url = try f.write("paused.pdf"); model.handleNewItems([FolderScanner.snapshot(of: url)!], kind: .download)
        #expect(model.prompts.count == 1); #expect(model.scene == nil); #expect(model.promptDeadline == nil)
    }
    @Test func interruptedRecordingIsNotPresentedAsSaved() throws {
        let f = try Fixture(); defer { f.remove() }; let model = f.model()
        _ = try model.beginRecording(url: f.folder.appendingPathComponent("video.mp4"), screen: "Display", audio: "No audio", format: "MP4")
        let restored = f.model(); #expect(restored.recordings.first?.status == .failed); #expect(restored.recordings.first?.error != nil)
    }
    @Test func corruptReplacementDoesNotMatchSavedIdentity() throws {
        let f = try Fixture(); defer { f.remove() }; let model = f.model(); let url = try f.write("video.mp4")
        let id = try model.beginRecording(url: url, screen: "Display", audio: "No audio", format: "MP4"); model.finishRecording(id, duration: 3)
        try FileManager.default.moveItem(at: url, to: f.folder.appendingPathComponent("moved.mp4")); try Data("different".utf8).write(to: url)
        #expect(!model.recordings[0].matches(url))
    }
    @Test func strictScreenshotDetectionRejectsNameOnly() throws {
        let f = try Fixture(); defer { f.remove() }; let url = try f.write("Screenshot 2026-10-01.png")
        #expect(!Screenshots.isTaggedScreenCapture(url))
        let data = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        _ = data.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, data.count, 0, 0) }
        #expect(Screenshots.isTaggedScreenCapture(url))
    }
    @Test func dimensionsPreserveAspectAndNeverUpscale() {
        var options = RecordingOptions(); options.resolution = 2160
        #expect(options.dimensions(width: 1280, height: 720).0 == 1280)
        #expect(options.dimensions(width: 1280, height: 720).1 == 720)
        options.resolution = 1080
        let size = options.dimensions(width: 3840, height: 2160)
        #expect(size.0 == 1920); #expect(size.1 == 1080)
    }
    @Test func popupStaysOnNegativeAndSmallDisplays() {
        for screen in [NSRect(x: -1920, y: -200, width: 1920, height: 1080), NSRect(x: 0, y: 0, width: 320, height: 240)] {
            for point in [screen.origin, NSPoint(x: screen.maxX, y: screen.maxY)] {
                let frame = QuickClipboardController.clampFrame(anchor: point, size: NSSize(width: 420, height: 450), screen: screen)
                #expect(screen.contains(frame))
            }
        }
    }
    @Test func shortcutCaptureRequiresModifierAndProtectsEditingKeys() {
        let control = ShortcutControl()
        var result: GlobalShortcut?
        control.onFinish = { result = $0 }
        control.begin()
        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags, _ character: String) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: code)!
        }
        control.keyDown(with: key(UInt16(kVK_ANSI_V), [], "v"))
        #expect(control.capturing); #expect(result == nil)
        control.keyDown(with: key(UInt16(kVK_ANSI_V), [.command], "v"))
        #expect(control.capturing); #expect(result == nil)
        control.keyDown(with: key(UInt16(kVK_ANSI_K), [.command, .option], "k"))
        #expect(!control.capturing); #expect(result?.key == UInt32(kVK_ANSI_K))
        #expect(result?.modifiers == UInt32(cmdKey | optionKey)); #expect(result?.label == "⌥⌘K")
    }
    @Test func shortcutEscapeCancelsWithoutChangingValue() {
        let control = ShortcutControl(); var finished = false; var result: GlobalShortcut?
        control.onFinish = { finished = true; result = $0 }
        control.begin()
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        control.keyDown(with: event)
        #expect(finished); #expect(result == nil); #expect(!control.capturing)
    }
    @Test func v1MigrationBacksUpWithoutLosingTimers() throws {
        let f = try Fixture(); defer { f.remove() }
        let original = Data("{\"items\":[],\"history\":[],\"pausedAt\":1}".utf8); try original.write(to: f.store.url)
        let state = f.store.load(); #expect(state.pausedAt != nil); #expect(state.recordings.isEmpty)
        #expect(try Data(contentsOf: f.folder.appendingPathComponent("state.v1.backup.json")) == original)
        try f.store.save(state); #expect(f.store.load() == state)
        #expect(try Data(contentsOf: f.folder.appendingPathComponent("state.v1.backup.json")) == original)
    }
}
