import Foundation
import Testing
@testable import PumpkinCore

@Suite struct DownloadFilterTests {
    @Test func ignoresHiddenAndSystemEntries() {
        for name in [".DS_Store", ".localized", "._photo.jpg", "Icon\r", "~$Report.docx", ""] {
            #expect(DownloadFilter.isIgnorable(name: name), "\(name.debugDescription) should be ignored")
        }
    }

    @Test func ignoresInProgressDownloads() {
        for name in ["movie.mp4.crdownload", "Unconfirmed 123.crdownload", "setup.dmg.part", "file.zip.download", "a.opdownload", "a.PART", "x.aria2"] {
            #expect(DownloadFilter.isIgnorable(name: name), "\(name) should be ignored")
        }
    }

    @Test func acceptsFinishedFiles() {
        for name in ["Installer.dmg", "photo.JPG", "README", "archive.tar.gz", "My Folder", "Report (1).pdf", "App.app"] {
            #expect(!DownloadFilter.isIgnorable(name: name), "\(name) should be accepted")
        }
    }

    @Test func detectsPartialSiblings() {
        let names: Set<String> = ["setup.dmg", "setup.dmg.part", "other.zip"]
        #expect(DownloadFilter.hasPartialSibling("setup.dmg", among: names))
        #expect(!DownloadFilter.hasPartialSibling("other.zip", among: names))
    }
}

@Suite struct StabilityTrackerTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    func snapshot(_ id: UInt64, _ name: String, size: Int64, modified: TimeInterval = 0, directory: Bool = false) -> FileSnapshot {
        FileSnapshot(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            fileID: id,
            isDirectory: directory,
            isPackage: false,
            size: size,
            modifiedAt: start.addingTimeInterval(modified),
            addedAt: start
        )
    }

    @Test func reportsOnlyAfterSettling() {
        var tracker = StabilityTracker(settleInterval: 1.5, emptySettleInterval: 6)
        let file = snapshot(1, "a.zip", size: 100)
        #expect(tracker.evaluate([file], allNames: ["a.zip"], now: start).isEmpty)
        #expect(tracker.evaluate([file], allNames: ["a.zip"], now: start + 1).isEmpty)
        let ready = tracker.evaluate([file], allNames: ["a.zip"], now: start + 1.6)
        #expect(ready.map(\.fileID) == [1])
        #expect(tracker.pendingCount == 0)
    }

    @Test func growingFileRestartsTheClock() {
        var tracker = StabilityTracker(settleInterval: 1.5, emptySettleInterval: 6)
        _ = tracker.evaluate([snapshot(1, "a", size: 10)], allNames: ["a"], now: start)
        #expect(tracker.evaluate([snapshot(1, "a", size: 20, modified: 1)], allNames: ["a"], now: start + 1.4).isEmpty)
        #expect(tracker.evaluate([snapshot(1, "a", size: 20, modified: 1)], allNames: ["a"], now: start + 2.5).isEmpty)
        #expect(tracker.evaluate([snapshot(1, "a", size: 20, modified: 1)], allNames: ["a"], now: start + 3.0).count == 1)
    }

    @Test func emptyFilesWaitLonger() {
        var tracker = StabilityTracker(settleInterval: 1.5, emptySettleInterval: 6)
        let empty = snapshot(1, "empty.txt", size: 0)
        _ = tracker.evaluate([empty], allNames: ["empty.txt"], now: start)
        #expect(tracker.evaluate([empty], allNames: ["empty.txt"], now: start + 2).isEmpty)
        #expect(tracker.evaluate([empty], allNames: ["empty.txt"], now: start + 6).count == 1)
    }

    @Test func partialSiblingBlocksReporting() {
        var tracker = StabilityTracker(settleInterval: 1.5, emptySettleInterval: 6)
        let placeholder = snapshot(1, "setup.dmg", size: 0)
        let names: Set<String> = ["setup.dmg", "setup.dmg.part"]
        _ = tracker.evaluate([placeholder], allNames: names, now: start)
        #expect(tracker.evaluate([placeholder], allNames: names, now: start + 60).isEmpty)
    }

    @Test func vanishedCandidatesAreDropped() {
        var tracker = StabilityTracker()
        _ = tracker.evaluate([snapshot(1, "a", size: 1)], allNames: ["a"], now: start)
        #expect(tracker.pendingCount == 1)
        _ = tracker.evaluate([], allNames: [], now: start + 1)
        #expect(tracker.pendingCount == 0)
    }

    @Test func directoriesUseDeepSize() {
        var tracker = StabilityTracker(settleInterval: 1, emptySettleInterval: 6)
        let folder = snapshot(9, "Unzipped", size: 0, directory: true)
        var deep: Int64 = 100
        _ = tracker.evaluate([folder], allNames: ["Unzipped"], now: start) { _ in deep }
        deep = 200
        #expect(tracker.evaluate([folder], allNames: ["Unzipped"], now: start + 1.2) { _ in deep }.isEmpty)
        let ready = tracker.evaluate([folder], allNames: ["Unzipped"], now: start + 2.4) { _ in deep }
        #expect(ready.first?.size == 200)
    }
}

@Suite(.serialized) struct FolderWatcherTests {
    let queue = DispatchQueue(label: "watcher-tests")

    func makeWatcher(_ dir: TempDir, collector: Collector) -> FolderWatcher {
        let watcher = FolderWatcher(
            folder: dir.url,
            queue: queue,
            settleInterval: 0.3,
            emptySettleInterval: 0.8,
            pollInterval: 0.1,
            safetyInterval: 5
        )
        watcher.onNewItems = { collector.append($0) }
        return watcher
    }

    @Test func reportsNewFilesButNotExistingOnes() async throws {
        let dir = TempDir()
        try dir.write("old.pdf")
        let collector = Collector()
        let watcher = makeWatcher(dir, collector: collector)
        try queue.sync { try watcher.start() }
        defer { queue.sync { watcher.stop() } }

        try await Task.sleep(for: .milliseconds(600))
        #expect(collector.all.isEmpty)

        try dir.write("new.zip", bytes: 2_048)
        #expect(await waitUntil { collector.names == ["new.zip"] })
        #expect(collector.all.first?.size == 2_048)

        // Reported exactly once.
        try await Task.sleep(for: .milliseconds(700))
        #expect(collector.names == ["new.zip"])
    }

    @Test func ignoresHiddenFiles() async throws {
        let dir = TempDir()
        let collector = Collector()
        let watcher = makeWatcher(dir, collector: collector)
        try queue.sync { try watcher.start() }
        defer { queue.sync { watcher.stop() } }

        try dir.write(".DS_Store")
        try dir.write("visible.txt")
        #expect(await waitUntil { collector.names == ["visible.txt"] })
        try await Task.sleep(for: .milliseconds(500))
        #expect(collector.names == ["visible.txt"])
    }

    @Test func chromeStyleRenameIsReportedUnderFinalName() async throws {
        let dir = TempDir()
        let collector = Collector()
        let watcher = makeWatcher(dir, collector: collector)
        try queue.sync { try watcher.start() }
        defer { queue.sync { watcher.stop() } }

        let partial = try dir.write("Unconfirmed 4821.crdownload", bytes: 500)
        try await Task.sleep(for: .milliseconds(800))
        #expect(collector.all.isEmpty)

        try FileManager.default.moveItem(at: partial, to: dir.url.appendingPathComponent("Report.pdf"))
        #expect(await waitUntil { collector.names == ["Report.pdf"] })
    }

    @Test func firefoxStylePlaceholderWaitsForPartFile() async throws {
        let dir = TempDir()
        let collector = Collector()
        let watcher = makeWatcher(dir, collector: collector)
        try queue.sync { try watcher.start() }
        defer { queue.sync { watcher.stop() } }

        try dir.write("setup.dmg", bytes: 0)
        let part = try dir.write("setup.dmg.part", bytes: 4_000)
        try await Task.sleep(for: .milliseconds(1_500))
        #expect(collector.all.isEmpty)

        _ = try FileManager.default.replaceItemAt(dir.url.appendingPathComponent("setup.dmg"), withItemAt: part)
        #expect(await waitUntil { collector.names == ["setup.dmg"] })
        #expect(collector.all.first?.size == 4_000)
        #expect(collector.all.count == 1)
    }

    @Test func waitsForGrowingFileToFinish() async throws {
        let dir = TempDir()
        let collector = Collector()
        let watcher = makeWatcher(dir, collector: collector)
        try queue.sync { try watcher.start() }
        defer { queue.sync { watcher.stop() } }

        let url = dir.url.appendingPathComponent("stream.bin")
        FileManager.default.createFile(atPath: url.path, contents: Data(count: 100))
        let handle = try FileHandle(forWritingTo: url)
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(120))
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(count: 100))
            #expect(collector.all.isEmpty)
        }
        try handle.close()

        #expect(await waitUntil { collector.names == ["stream.bin"] })
        #expect(collector.all.first?.size == 900)
    }

    @Test func reportsNewFoldersWithTheirContentsSize() async throws {
        let dir = TempDir()
        let collector = Collector()
        let watcher = makeWatcher(dir, collector: collector)
        try queue.sync { try watcher.start() }
        defer { queue.sync { watcher.stop() } }

        let folder = try dir.subfolder("Photos")
        try Data(count: 300).write(to: folder.appendingPathComponent("a.jpg"))
        try Data(count: 700).write(to: folder.appendingPathComponent("b.jpg"))

        #expect(await waitUntil { collector.names == ["Photos"] })
        #expect(collector.all.first?.size == 1_000)
        #expect(collector.all.first?.isFolder == true)
    }

    @Test func reportsFilesAddedWhileNotRunning() async throws {
        let dir = TempDir()
        try dir.write("before.txt")
        let since = Date()
        try await Task.sleep(for: .milliseconds(1_100))
        let arrived = try dir.write("while-away.txt")
        let alreadyTracked = try dir.write("tracked.txt")

        let collector = Collector()
        let watcher = makeWatcher(dir, collector: collector)
        let trackedID = FolderScanner.fileID(of: alreadyTracked)!
        try queue.sync { try watcher.start(newSince: since, alreadyKnown: [trackedID]) }
        defer { queue.sync { watcher.stop() } }

        #expect(await waitUntil { collector.names == [arrived.lastPathComponent] })
        try await Task.sleep(for: .milliseconds(500))
        #expect(collector.names == ["while-away.txt"])
    }

    @Test func markKnownSuppressesReport() async throws {
        let dir = TempDir()
        let collector = Collector()
        let watcher = makeWatcher(dir, collector: collector)
        try queue.sync { try watcher.start() }
        defer { queue.sync { watcher.stop() } }

        let restored = try dir.write("restored.txt")
        let id = FolderScanner.fileID(of: restored)!
        queue.sync { watcher.markKnown(id) }
        try dir.write("fresh.txt")
        #expect(await waitUntil { collector.names == ["fresh.txt"] })
        try await Task.sleep(for: .milliseconds(500))
        #expect(collector.names == ["fresh.txt"])
    }

    @Test func throwsWhenFolderMissing() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)")
        let watcher = FolderWatcher(folder: missing, queue: queue)
        #expect(throws: (any Error).self) {
            try queue.sync { try watcher.start() }
        }
    }
}

@Suite struct ScreenshotTests {
    func tag(_ url: URL, _ value: Bool) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        _ = data.withUnsafeBytes { setxattr(url.path, Screenshots.captureAttribute, $0.baseAddress, data.count, 0, 0) }
    }

    @Test func recognisesTaggedFilesWhateverTheirName() throws {
        let dir = TempDir()
        let file = try dir.write("my capture.png")
        #expect(!Screenshots.isScreenCapture(file))
        try tag(file, true)
        #expect(Screenshots.isScreenCapture(file))
    }

    @Test func explicitFalseTagWins() throws {
        let dir = TempDir()
        let file = try dir.write("Screenshot 2026-09-29 at 19.40.15.png")
        try tag(file, false)
        #expect(!Screenshots.isScreenCapture(file))
    }

    @Test func fallsBackToDefaultNames() throws {
        let dir = TempDir()
        #expect(Screenshots.isScreenCapture(try dir.write("Screenshot 2026-09-29 at 19.40.15.png")))
        #expect(Screenshots.isScreenCapture(try dir.write("Screen Recording 2026-09-29 at 19.40.15.mov")))
        #expect(Screenshots.isScreenCapture(try dir.write("Снимок экрана 2026-09-29 в 19.40.15.png")))
        #expect(!Screenshots.isScreenCapture(try dir.write("holiday.png")))
    }

    @Test func folderFollowsScreenshotSettings() throws {
        let dir = TempDir()
        #expect(Screenshots.folder(location: nil).lastPathComponent == "Desktop")
        #expect(Screenshots.folder(location: "").lastPathComponent == "Desktop")
        #expect(Screenshots.folder(location: dir.url.path).path == dir.url.path)
        #expect(Screenshots.folder(location: "/nonexistent/\(UUID().uuidString)").lastPathComponent == "Desktop")
        #expect(Screenshots.folder(location: "~").path == FileManager.default.homeDirectoryForCurrentUser.path.replacingOccurrences(of: "/$", with: "", options: .regularExpression))
    }
}

@Suite(.serialized) struct FilteredWatcherTests {
    @Test func reportsOnlyAcceptedEntries() async throws {
        let dir = TempDir()
        let queue = DispatchQueue(label: "filtered-watcher")
        let collector = Collector()
        let watcher = FolderWatcher(folder: dir.url, queue: queue, settleInterval: 0.3, emptySettleInterval: 0.8, pollInterval: 0.1)
        watcher.accept = { Screenshots.isScreenCapture($0.url) }
        watcher.onNewItems = { collector.append($0) }
        try queue.sync { try watcher.start() }
        defer { queue.sync { watcher.stop() } }

        try dir.write("notes.txt")
        try dir.write("Screenshot 2026-09-29 at 21.00.00.png")
        #expect(await waitUntil { collector.names == ["Screenshot 2026-09-29 at 21.00.00.png"] })
        try await Task.sleep(for: .milliseconds(600))
        #expect(collector.names == ["Screenshot 2026-09-29 at 21.00.00.png"])
    }
}
