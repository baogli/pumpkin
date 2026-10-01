import AppKit
import Carbon
import Foundation
import Testing
import PumpkinCore
@testable import PumpkinApp

@MainActor @Suite(.serialized) struct ReviewRegressionTests {
    typealias Fixture = UnifiedTests.Fixture
    struct PrivateTrash: FileTrashing {
        let folder: URL
        func trashItem(at url: URL) throws -> URL? {
            let destination = folder.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }
    func board() -> NSPasteboard { NSPasteboard(name: .init("PumpkinReview-\(UUID().uuidString)")) }
    func set(_ text: String, on board: NSPasteboard) { board.clearContents(); board.setString(text, forType: .string) }

    @Test func importingOneVideoPreservesOtherPendingFiles() throws {
        let f = try Fixture(); defer { f.remove() }; let model = f.model()
        let video = try f.write("video.mp4"), document = try f.write("notes.pdf")
        model.handleNewItems([FolderScanner.snapshot(of: video)!, FolderScanner.snapshot(of: document)!], kind: .download)
        #expect(model.prompts.count == 1); #expect(model.prompts[0].items.count == 2)
        try model.importRecording(video, duration: 4)
        #expect(model.prompts[0].items.map(\.url) == [document]); #expect(model.items.isEmpty)
        #expect(f.model().prompts[0].items.map(\.url) == [document])
    }
    @Test func pendingRenameIsSavedImmediately() throws {
        let f = try Fixture(); defer { f.remove() }; let model = f.model()
        let old = try f.write("before.pdf"), renamed = f.folder.appendingPathComponent("after.pdf")
        model.handleNewItems([FolderScanner.snapshot(of: old)!], kind: .download)
        try FileManager.default.moveItem(at: old, to: renamed)
        model.handleScan([FolderScanner.snapshot(of: renamed)!], in: f.folder)
        #expect(f.model().prompts.first?.primary.url == renamed)
    }
    @Test func differentFoldersDoNotMergeOrEraseQuestions() throws {
        let f = try Fixture(); defer { f.remove() }; let model = f.model()
        let other = f.folder.appendingPathComponent("other"); try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let first = try f.write("first.pdf"), second = other.appendingPathComponent("second.pdf"); try Data("second".utf8).write(to: second)
        model.handleNewItems([FolderScanner.snapshot(of: first)!], kind: .download)
        model.handleNewItems([FolderScanner.snapshot(of: second)!], kind: .download)
        #expect(model.prompts.count == 2)
        model.handleScan([], in: f.folder)
        #expect(model.prompts.count == 1); #expect(model.prompts[0].primary.url == second)
    }
    @Test func changingDownloadFolderPreservesUnansweredScreenshots() throws {
        let f = try Fixture(); defer { f.remove() }; f.defaults.set(false, forKey: "watchDownloads")
        let model = f.model(), url = try f.write("image.png")
        model.handleNewItems([FolderScanner.snapshot(of: url)!], kind: .screenshot)
        model.changeWatchedFolder(to: f.folder.appendingPathComponent("other"))
        #expect(model.prompts.first?.primary.url == url)
        #expect(f.store.load().pendingGroups.count == 1)
    }
    @Test func confirmingWhilePausedUsesFrozenClock() async throws {
        let f = try Fixture(); defer { f.remove() }; let model = f.model()
        model.togglePause(); try await Task.sleep(nanoseconds: 100_000_000)
        let url = try f.write("paused.pdf"); model.handleNewItems([FolderScanner.snapshot(of: url)!], kind: .download)
        let duration = model.prompts[0].selectedDuration.seconds; model.confirm(model.prompts[0].id)
        #expect(model.items[0].remaining(at: model.clock(Date())) == duration)
        model.togglePause(); #expect(abs(model.items[0].remaining(at: Date()) - duration) < 0.05)
    }
    @Test func renamedRecordingInTrashCannotReceiveAnotherTimer() throws {
        let f = try Fixture(); defer { f.remove() }
        let trash = f.folder.appendingPathComponent(".Trash"); try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let prefs = Preferences(defaults: f.defaults); prefs.customFolderPath = f.folder.path
        let model = AppModel(prefs: prefs, store: f.store, engine: ExpiryEngine(trash: PrivateTrash(folder: trash)))
        let url = try f.write("video.mp4"), id = try model.beginRecording(url: url, screen: "Display", audio: "None", format: "MP4")
        model.finishRecording(id, duration: 2)
        let renamed = f.folder.appendingPathComponent("renamed.mp4"); try FileManager.default.moveItem(at: url, to: renamed)
        model.scheduleRecording(id, duration: .hours(1)); #expect(model.items.count == 1)
        model.trashNow(model.items[0].id)
        #expect(model.recordingTrash(model.recordings[0])?.name == "renamed.mp4")
        #expect(model.history[0].kind == "recording"); model.scheduleRecording(id, duration: .hours(1)); #expect(model.items.isEmpty)
        model.putBack(model.history); model.scheduleRecording(id, duration: .hours(1)); #expect(model.items.count == 1)
    }
    @Test func putBackRejectsReplacementInTrash() throws {
        let f = try Fixture(); defer { f.remove() }; let url = try f.write("trashed.txt")
        let record = TrashRecord(name: "original.txt", originalPath: f.folder.appendingPathComponent("original.txt").path, trashedPath: url.path, trashedAt: Date(), isFolder: false, size: 4, fileID: FolderScanner.fileID(of: url), volumeID: ItemLocator.volumeID(of: url))
        try FileManager.default.moveItem(at: url, to: f.folder.appendingPathComponent("moved-original.txt")); try Data("replacement".utf8).write(to: url)
        #expect(!record.canPutBack); #expect(throws: PutBackError.noLongerInTrash) { try ExpiryEngine.putBack(record) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "replacement")
    }
    @Test func fileIdentityIncludesVolume() throws {
        let f = try Fixture(); defer { f.remove() }; let model = f.model(), url = try f.write("file.pdf")
        model.handleNewItems([FolderScanner.snapshot(of: url)!], kind: .download); model.confirm(model.prompts[0].id)
        var item = model.items[0]; item.volumeID = (ItemLocator.volumeID(of: url) ?? 0) + 1
        #expect(ItemLocator.locate(item) == .missing)
    }
    @Test func pendingQuestionRejectsMatchingInodeOnDifferentVolume() throws {
        let f = try Fixture(); defer { f.remove() }; let url = try f.write("file.pdf")
        var snapshot = FolderScanner.snapshot(of: url)!
        snapshot.volumeID = (snapshot.volumeID ?? 0) + 1
        let group = PendingFileGroup(id: UUID(), snapshots: [snapshot], sources: [nil], kind: "download", selection: 0, arrivedAt: Date(), touched: false)
        try f.store.save(PersistedState(pendingGroups: [group]))
        #expect(f.model().prompts.isEmpty)
    }
    @Test func selectingCurrentDurationStillPersistsInteraction() throws {
        let f = try Fixture(); defer { f.remove() }; let model = f.model(), url = try f.write("file.pdf")
        model.handleNewItems([FolderScanner.snapshot(of: url)!], kind: .download)
        model.select(model.prompts[0].selection, in: model.prompts[0].id)
        #expect(f.model().prompts[0].touched)
    }
    @Test func failedRecordingDoesNotProtectAnUnrelatedReplacement() throws {
        let f = try Fixture(); defer { f.remove() }; let model = f.model(), url = try f.write("failed.mp4")
        let id = try model.beginRecording(url: url, screen: "Display", audio: "None", format: "MP4"); model.finishRecording(id, duration: 0, error: "Interrupted")
        try FileManager.default.moveItem(at: url, to: f.folder.appendingPathComponent("failed-original.mp4")); try Data("download".utf8).write(to: url)
        model.handleNewItems([FolderScanner.snapshot(of: url)!], kind: .download)
        #expect(model.prompts.count == 1)
    }
    @Test func screenshotCategorySurvivesRenameTrashAndRestart() throws {
        let f = try Fixture(); defer { f.remove() }; let model = f.model(), url = try f.write("capture.png")
        model.handleNewItems([FolderScanner.snapshot(of: url)!], kind: .screenshot); model.confirm(model.prompts[0].id)
        #expect(CleanupClassification.kind(of: f.model().items[0]) == .screenshot)
        let fakeNamed = try f.write("Screenshot 2026-10-01.png")
        var item = model.items[0]; item.path = fakeNamed.path; item.kind = nil
        #expect(CleanupClassification.kind(of: item) == .download)
        let record = TrashRecord(name: "renamed.png", originalPath: url.path, trashedPath: nil, trashedAt: Date(), isFolder: false, size: 4, kind: "screenshot")
        #expect(CleanupClassification.kind(of: record, recordings: []) == .screenshot)
    }
    @Test func screenshotWatcherWorksWhenDownloadsIsOffInSameFolder() async throws {
        let f = try Fixture(); defer { f.remove() }; f.defaults.set(false, forKey: "watchDownloads"); f.defaults.set(true, forKey: "watchScreenshots")
        let model = f.model(); model.resolveScreenshotFolder = { f.folder }; model.startWatching()
        defer { model.setWatchScreenshots(false) }
        let url = try f.write("capture.png")
        let tag = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        _ = tag.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, tag.count, 0, 0) }
        let deadline = Date().addingTimeInterval(4)
        while model.prompts.isEmpty && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        #expect(model.prompts.first?.kind == .screenshot); #expect(!model.isWatching)
    }
    @Test func changedFocusCancelsQueuedPasteAndRestoresOriginal() async throws {
        let board = board(); defer { board.releaseGlobally() }; let history = ClipboardHistory(pasteboard: board); history.setEnabled(true)
        defer { history.setEnabled(false) }; set("original", on: board)
        var valid = true, sends = 0; var completed: Bool?
        history.paste(ClipboardEntry(text: "chosen", copiedAt: Date()), validate: { valid }, send: { sends += 1; return true }, completion: { completed = $0 })
        valid = false; try await Task.sleep(nanoseconds: 200_000_000)
        #expect(sends == 0); #expect(completed == false); #expect(!history.delivering); #expect(board.string(forType: .string) == "original")
    }
    @Test func userCopyBeforePastePreventsDeliveryAndRemainsOnPasteboard() async throws {
        let board = board(); defer { board.releaseGlobally() }; let history = ClipboardHistory(pasteboard: board); history.setEnabled(true)
        defer { history.setEnabled(false) }; set("original", on: board)
        var sends = 0; var completed: Bool?
        history.paste(ClipboardEntry(text: "chosen", copiedAt: Date()), validate: { true }, send: { sends += 1; return true }, completion: { completed = $0 })
        set("new user copy", on: board); try await Task.sleep(nanoseconds: 200_000_000)
        #expect(sends == 0); #expect(completed == false); #expect(board.string(forType: .string) == "new user copy")
    }
    @Test func newCopyAfterPasteWinsOverRestore() async throws {
        let board = board(); defer { board.releaseGlobally() }; let history = ClipboardHistory(pasteboard: board); history.setEnabled(true)
        defer { history.setEnabled(false) }; set("original", on: board)
        var sends = 0; var completed: Bool?
        history.paste(ClipboardEntry(text: "chosen", copiedAt: Date()), validate: { true }, send: { sends += 1; set("new user copy", on: board); return true }, completion: { completed = $0 })
        try await Task.sleep(nanoseconds: 850_000_000)
        #expect(sends == 1); #expect(completed == true); #expect(board.string(forType: .string) == "new user copy"); #expect(!history.delivering)
    }
    @Test func disableCancelsQueuedPasteWithoutLosingSystemBuffer() async throws {
        let board = board(); defer { board.releaseGlobally() }; let history = ClipboardHistory(pasteboard: board); history.setEnabled(true); set("original", on: board)
        var sends = 0, completions = 0
        history.paste(ClipboardEntry(text: "chosen", copiedAt: Date()), validate: { true }, send: { sends += 1; return true }, completion: { _ in completions += 1 })
        history.setEnabled(false); try await Task.sleep(nanoseconds: 200_000_000)
        #expect(sends == 0); #expect(completions == 1); #expect(board.string(forType: .string) == "original")
    }
    @Test func duplicateModuleShortcutsRegisterNeitherAction() throws {
        let f = try Fixture(); defer { f.remove() }; let prefs = UnifiedPreferences(defaults: f.defaults)
        prefs.clipboardEnabled = true; prefs.clipboardShortcut = prefs.recordingShortcut
        let board = board(); defer { board.releaseGlobally() }
        let workbench = Workbench(files: f.model(), prefs: prefs, clipboard: ClipboardHistory(pasteboard: board))
        let hotkeys = GlobalHotkeys(workbench: workbench); hotkeys.register()
        #expect(hotkeys.registeredIDs.isEmpty); #expect(workbench.shortcutError != nil)
        workbench.setClipboardEnabled(false)
    }
    @Test func visibleClipSettingIsClampedInMemoryAndStorage() throws {
        let f = try Fixture(); defer { f.remove() }; let prefs = UnifiedPreferences(defaults: f.defaults)
        prefs.visibleClips = 50; #expect(prefs.visibleClips == 9); #expect(f.defaults.integer(forKey: "v2.visibleClips") == 9)
        prefs.visibleClips = -10; #expect(prefs.visibleClips == 3)
    }
    @Test func lateWindowKeyNotificationCannotReshowHiddenWorkspace() throws {
        let f = try Fixture(); defer { f.remove() }
        let board = board(); defer { board.releaseGlobally() }
        let workbench = Workbench(files: f.model(), prefs: UnifiedPreferences(defaults: f.defaults), clipboard: ClipboardHistory(pasteboard: board))
        let controller = WorkbenchWindow(workbench: workbench)
        controller.present(); controller.hide()
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: controller.window))
        #expect(!workbench.windowVisible); #expect(controller.window?.isVisible == false)
        controller.window?.close(); controller.window?.contentView = nil
    }
}
