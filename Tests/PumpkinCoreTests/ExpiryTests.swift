import Foundation
import Testing
@testable import PumpkinCore

@Suite struct ExpiryEngineTests {
    @Test func trashesFileStillInFolder() throws {
        let dir = TempDir(), trash = TempDir()
        let file = try dir.write("Installer.dmg")
        let engine = ExpiryEngine(trash: FakeTrash(folder: trash.url))

        let outcome = engine.expire(makeItem(for: file, folder: dir.url))
        guard case .trashed(let record) = outcome else {
            Issue.record("expected trashed, got \(outcome)")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(record.name == "Installer.dmg")
        #expect(record.trashedPath.map { FileManager.default.fileExists(atPath: $0) } == true)
        #expect(record.canPutBack)
    }

    @Test func followsRenamesInsideTheFolder() throws {
        let dir = TempDir(), trash = TempDir()
        let file = try dir.write("draft.txt")
        let item = makeItem(for: file, folder: dir.url)
        let renamed = dir.url.appendingPathComponent("final.txt")
        try FileManager.default.moveItem(at: file, to: renamed)

        let outcome = ExpiryEngine(trash: FakeTrash(folder: trash.url)).expire(item)
        guard case .trashed(let record) = outcome else {
            Issue.record("expected trashed, got \(outcome)")
            return
        }
        #expect(record.name == "final.txt")
        #expect(!FileManager.default.fileExists(atPath: renamed.path))
    }

    @Test func leavesFilesMovedIntoSubfolderAlone() throws {
        let dir = TempDir(), trash = TempDir()
        let file = try dir.write("keepme.pdf")
        let item = makeItem(for: file, folder: dir.url)
        let sub = try dir.subfolder("Sorted")
        let moved = sub.appendingPathComponent("keepme.pdf")
        try FileManager.default.moveItem(at: file, to: moved)

        let outcome = ExpiryEngine(trash: FakeTrash(folder: trash.url)).expire(item)
        guard case .movedOut = outcome else {
            Issue.record("expected movedOut, got \(outcome)")
            return
        }
        #expect(FileManager.default.fileExists(atPath: moved.path))
    }

    @Test func leavesFilesMovedToAnotherFolderAlone() throws {
        let dir = TempDir(), elsewhere = TempDir(), trash = TempDir()
        let file = try dir.write("contract.pdf")
        let item = makeItem(for: file, folder: dir.url)
        let moved = elsewhere.url.appendingPathComponent("contract.pdf")
        try FileManager.default.moveItem(at: file, to: moved)

        let outcome = ExpiryEngine(trash: FakeTrash(folder: trash.url)).expire(item)
        guard case .movedOut = outcome else {
            Issue.record("expected movedOut, got \(outcome)")
            return
        }
        #expect(FileManager.default.fileExists(atPath: moved.path))
    }

    @Test func reportsMissingWhenDeleted() throws {
        let dir = TempDir(), trash = TempDir()
        let file = try dir.write("gone.txt")
        let item = makeItem(for: file, folder: dir.url)
        try FileManager.default.removeItem(at: file)
        #expect(ExpiryEngine(trash: FakeTrash(folder: trash.url)).expire(item) == .missing)
    }

    @Test func neverTrashesADifferentFileWithTheSameName() throws {
        let dir = TempDir(), trash = TempDir()
        let file = try dir.write("photo.jpg")
        let item = makeItem(for: file, folder: dir.url)
        try FileManager.default.removeItem(at: file)
        let impostor = try dir.write("photo.jpg", bytes: 99)

        #expect(ExpiryEngine(trash: FakeTrash(folder: trash.url)).expire(item) == .missing)
        #expect(FileManager.default.fileExists(atPath: impostor.path))
    }

    @Test func surfacesTrashFailures() throws {
        let dir = TempDir()
        let file = try dir.write("locked.bin")
        let outcome = ExpiryEngine(trash: FailingTrash()).expire(makeItem(for: file, folder: dir.url))
        #expect(outcome == .failed("Permission denied"))
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func trashesWholeFolders() throws {
        let dir = TempDir(), trash = TempDir()
        let folder = try dir.subfolder("Unzipped")
        try Data(count: 10).write(to: folder.appendingPathComponent("inner.txt"))
        var item = makeItem(for: folder, folder: dir.url)
        item.isFolder = true

        let outcome = ExpiryEngine(trash: FakeTrash(folder: trash.url)).expire(item)
        guard case .trashed(let record) = outcome else {
            Issue.record("expected trashed, got \(outcome)")
            return
        }
        #expect(record.isFolder)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func putBackRestoresOriginalLocation() throws {
        let dir = TempDir(), trash = TempDir()
        let file = try dir.write("notes.md")
        guard case .trashed(let record) = ExpiryEngine(trash: FakeTrash(folder: trash.url)).expire(makeItem(for: file, folder: dir.url)) else {
            Issue.record("expected trashed")
            return
        }
        let restored = try ExpiryEngine.putBack(record)
        #expect(restored.resolvingSymlinksInPath().path == file.resolvingSymlinksInPath().path)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func putBackPicksAFreeNameOnConflict() throws {
        let dir = TempDir(), trash = TempDir()
        let file = try dir.write("notes.md")
        guard case .trashed(let record) = ExpiryEngine(trash: FakeTrash(folder: trash.url)).expire(makeItem(for: file, folder: dir.url)) else {
            Issue.record("expected trashed")
            return
        }
        try dir.write("notes.md", bytes: 3)
        let restored = try ExpiryEngine.putBack(record)
        #expect(restored.lastPathComponent == "notes 2.md")
    }

    @Test func putBackFailsWhenTrashWasEmptied() throws {
        let dir = TempDir(), trash = TempDir()
        let file = try dir.write("temp.txt")
        guard case .trashed(let record) = ExpiryEngine(trash: FakeTrash(folder: trash.url)).expire(makeItem(for: file, folder: dir.url)) else {
            Issue.record("expected trashed")
            return
        }
        try FileManager.default.removeItem(atPath: record.trashedPath!)
        #expect(!record.canPutBack)
        #expect(throws: PutBackError.noLongerInTrash) {
            try ExpiryEngine.putBack(record)
        }
    }

    @Test func uniqueDestinationHandlesExtensionlessNames() throws {
        let dir = TempDir()
        try dir.write("README")
        try dir.write("README 2")
        #expect(ExpiryEngine.uniqueDestination(for: dir.url.appendingPathComponent("README")).lastPathComponent == "README 3")
    }

    @Test func directChildCheckResolvesSymlinks() throws {
        let dir = TempDir()
        let file = try dir.write("a.txt")
        // /var is a symlink to /private/var on macOS.
        let privateFolder = URL(fileURLWithPath: dir.url.resolvingSymlinksInPath().path)
        #expect(ItemLocator.isDirectChild(file, of: privateFolder))
        #expect(ItemLocator.isDirectChild(file, of: URL(fileURLWithPath: dir.url.path + "/")))
        #expect(!ItemLocator.isDirectChild(file, of: dir.url.deletingLastPathComponent()))
    }
}

@Suite struct TrackedItemTests {
    @Test func fractionRemaining() {
        let start = Date(timeIntervalSince1970: 0)
        let item = TrackedItem(name: "a", path: "/a", folderPath: "/", fileID: 1, bookmark: nil, size: 0, isFolder: false, source: nil, startedAt: start, expiresAt: start + 100)
        #expect(item.fractionRemaining(at: start) == 1)
        #expect(item.fractionRemaining(at: start + 25) == 0.75)
        #expect(item.fractionRemaining(at: start + 500) == 0)
        #expect(item.remaining(at: start + 40) == 60)
    }
}

@Suite struct StateStoreTests {
    @Test func roundTrips() throws {
        let dir = TempDir()
        let store = StateStore(url: dir.url.appendingPathComponent("nested/state.json"))
        let now = Date()
        let state = PersistedState(
            items: [TrackedItem(name: "a.zip", path: "/x/a.zip", folderPath: "/x", fileID: 42, bookmark: Data([1, 2, 3]), size: 10, isFolder: false, source: "example.com", startedAt: now, expiresAt: now + 60)],
            history: [TrashRecord(name: "b.dmg", originalPath: "/x/b.dmg", trashedPath: "/t/b.dmg", trashedAt: now, isFolder: false, size: 5)],
            lastSeenAt: now,
            pausedAt: nil
        )
        try store.save(state)
        #expect(store.load() == state)
    }

    @Test func missingFileLoadsEmptyState() {
        let dir = TempDir()
        #expect(StateStore(url: dir.url.appendingPathComponent("none.json")).load() == PersistedState())
    }

    @Test func unreadableFileIsSetAside() throws {
        let dir = TempDir()
        let url = dir.url.appendingPathComponent("state.json")
        try Data("{ not json".utf8).write(to: url)
        #expect(StateStore(url: url).load() == PersistedState())
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
        #expect(leftovers.contains { $0.hasPrefix("state.unreadable-") })
    }

    @Test func toleratesMissingKeys() throws {
        let dir = TempDir()
        let url = dir.url.appendingPathComponent("state.json")
        try Data("{}".utf8).write(to: url)
        #expect(StateStore(url: url).load() == PersistedState())
    }
}

@Suite struct DownloadSourceTests {
    func setAttribute(_ name: String, _ data: Data, on url: URL) {
        _ = data.withUnsafeBytes { buffer in
            setxattr(url.path, name, buffer.baseAddress, data.count, 0, 0)
        }
    }

    @Test func prefersReferringPage() throws {
        let dir = TempDir()
        let file = try dir.write("release.zip")
        let froms = ["https://objects.githubusercontent.com/abc/release.zip", "https://www.github.com/owner/repo/releases"]
        setAttribute(DownloadSource.whereFromsAttribute, try PropertyListSerialization.data(fromPropertyList: froms, format: .binary, options: 0), on: file)
        #expect(DownloadSource.describe(file) == "github.com")
    }

    @Test func fallsBackToDownloadHost() throws {
        let dir = TempDir()
        let file = try dir.write("image.png")
        let froms = ["https://cdn.example.org/image.png"]
        setAttribute(DownloadSource.whereFromsAttribute, try PropertyListSerialization.data(fromPropertyList: froms, format: .binary, options: 0), on: file)
        #expect(DownloadSource.describe(file) == "cdn.example.org")
    }

    @Test func fallsBackToQuarantineAgent() throws {
        let dir = TempDir()
        let file = try dir.write("doc.pdf")
        setAttribute(DownloadSource.quarantineAttribute, Data("0083;65f0c1a2;Google Chrome;4A1B".utf8), on: file)
        #expect(DownloadSource.describe(file) == "Google Chrome")
    }

    @Test func nilWithoutMetadata() throws {
        let dir = TempDir()
        #expect(DownloadSource.describe(try dir.write("plain.txt")) == nil)
    }
}
