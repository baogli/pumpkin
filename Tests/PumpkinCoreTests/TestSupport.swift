import Foundation
@testable import PumpkinCore

/// A throwaway directory, removed when the value is deinitialised.
final class TempDir {
    let url: URL

    init(_ label: String = #function) {
        let safe = label.replacingOccurrences(of: "[^A-Za-z0-9]", with: "", options: .regularExpression)
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PumpkinTests-\(safe)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func write(_ name: String, bytes: Int = 16) throws -> URL {
        let file = url.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: file)
        return file
    }

    func subfolder(_ name: String) throws -> URL {
        let folder = url.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

/// Moves files into a private folder instead of the user's real Trash.
struct FakeTrash: FileTrashing {
    let folder: URL

    func trashItem(at url: URL) throws -> URL? {
        let destination = ExpiryEngine.uniqueDestination(for: folder.appendingPathComponent(url.lastPathComponent))
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}

struct FailingTrash: FileTrashing {
    struct Boom: LocalizedError {
        var errorDescription: String? { "Permission denied" }
    }

    func trashItem(at url: URL) throws -> URL? {
        throw Boom()
    }
}

/// Thread-safe sink for watcher callbacks.
final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var batches: [[FileSnapshot]] = []

    func append(_ batch: [FileSnapshot]) {
        lock.withLock { batches.append(batch) }
    }

    var all: [FileSnapshot] { lock.withLock { batches.flatMap { $0 } } }
    var names: [String] { all.map(\.name) }
    var batchCount: Int { lock.withLock { batches.count } }
}

func waitUntil(timeout: TimeInterval = 8, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(40))
    }
    return condition()
}

func makeItem(for url: URL, folder: URL, expiresIn: TimeInterval = 60, now: Date = Date()) -> TrackedItem {
    TrackedItem(
        name: url.lastPathComponent,
        path: url.path,
        folderPath: folder.path,
        fileID: FolderScanner.fileID(of: url)!,
        bookmark: ItemLocator.makeBookmark(for: url),
        size: 16,
        isFolder: false,
        source: nil,
        startedAt: now,
        expiresAt: now.addingTimeInterval(expiresIn)
    )
}
