import Foundation

public protocol FileTrashing {
    /// Moves the item to the Trash and returns where it ended up, if known.
    func trashItem(at url: URL) throws -> URL?
}

/// The real Trash, via Finder-compatible `FileManager.trashItem`.
public struct SystemTrash: FileTrashing {
    public init() {}

    public func trashItem(at url: URL) throws -> URL? {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }
}

public enum ItemLocation: Equatable {
    /// Still directly inside the folder it was tracked in.
    case inFolder(URL)
    /// Still exists, but the user moved it somewhere else, so it's theirs to keep.
    case movedOut(URL)
    /// Gone, or replaced by a different file with the same name.
    case missing
}

public enum ItemLocator {
    public static func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Finds the file a timer belongs to, following renames. A different file that
    /// merely has the same name is never mistaken for it.
    public static func locate(_ item: TrackedItem) -> ItemLocation {
        var found: URL?

        if let bookmark = item.bookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), FolderScanner.fileID(of: url) == item.fileID {
                found = url
            }
        }
        if found == nil, FolderScanner.fileID(of: item.url) == item.fileID {
            found = item.url
        }

        guard let url = found else { return .missing }
        return isDirectChild(url, of: item.folderURL) ? .inFolder(url) : .movedOut(url)
    }

    public static func isDirectChild(_ url: URL, of folder: URL) -> Bool {
        canonicalPath(url.deletingLastPathComponent()) == canonicalPath(folder)
    }

    public static func canonicalPath(_ url: URL) -> String {
        var path = url.resolvingSymlinksInPath().standardizedFileURL.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}

public enum ExpiryOutcome: Equatable {
    case trashed(TrashRecord)
    case missing
    case movedOut(URL)
    case failed(String)
}

public enum PutBackError: LocalizedError, Equatable {
    case noLongerInTrash

    public var errorDescription: String? {
        switch self {
        case .noLongerInTrash: return "It’s no longer in the Trash."
        }
    }
}

public struct ExpiryEngine {
    public var trash: FileTrashing

    public init(trash: FileTrashing = SystemTrash()) {
        self.trash = trash
    }

    /// Moves the item to the Trash if, and only if, it is still the same file and
    /// still sits directly in the folder it was tracked in.
    public func expire(_ item: TrackedItem, now: Date = Date()) -> ExpiryOutcome {
        switch ItemLocator.locate(item) {
        case .missing:
            return .missing
        case .movedOut(let url):
            return .movedOut(url)
        case .inFolder(let url):
            do {
                let trashed = try trash.trashItem(at: url)
                return .trashed(TrashRecord(
                    name: url.lastPathComponent,
                    originalPath: url.path,
                    trashedPath: trashed?.path,
                    trashedAt: now,
                    isFolder: item.isFolder,
                    size: item.size
                ))
            } catch {
                return .failed(error.localizedDescription)
            }
        }
    }

    /// Moves a trashed item back where it came from, choosing a free name if the
    /// original one has been taken in the meantime.
    @discardableResult
    public static func putBack(_ record: TrashRecord) throws -> URL {
        guard let trashedPath = record.trashedPath, FileManager.default.fileExists(atPath: trashedPath) else {
            throw PutBackError.noLongerInTrash
        }
        let original = URL(fileURLWithPath: record.originalPath)
        try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        let destination = uniqueDestination(for: original)
        try FileManager.default.moveItem(at: URL(fileURLWithPath: trashedPath), to: destination)
        return destination
    }

    /// `name.ext`, or `name 2.ext`, `name 3.ext`… whichever is free first.
    public static func uniqueDestination(for url: URL) -> URL {
        guard exists(url) else { return url }
        let folder = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !exists(candidate) {
                return candidate
            }
            index += 1
        }
    }

    private static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }
}
