import Foundation

/// A shallow, cheap description of one entry in the watched folder.
public struct FileSnapshot: Hashable, Sendable {
    public var url: URL
    /// The inode. Stable across renames within the same volume, which is how
    /// a file is recognised after a browser renames `x.crdownload` to `x`.
    public var fileID: UInt64
    public var isDirectory: Bool
    public var isPackage: Bool
    public var size: Int64
    public var modifiedAt: Date?
    public var addedAt: Date?

    public init(url: URL, fileID: UInt64, isDirectory: Bool, isPackage: Bool, size: Int64, modifiedAt: Date?, addedAt: Date?) {
        self.url = url
        self.fileID = fileID
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.size = size
        self.modifiedAt = modifiedAt
        self.addedAt = addedAt
    }

    public var name: String { url.lastPathComponent }

    /// A plain folder, as opposed to a file or a package such as an `.app` bundle.
    public var isFolder: Bool { isDirectory && !isPackage }
}

public enum FolderScanner {
    static let resourceKeys: [URLResourceKey] = [.isPackageKey, .addedToDirectoryDateKey, .creationDateKey]

    /// Lists the direct children of `folder`. Throws when the folder is missing or unreadable.
    public static func scan(_ folder: URL) throws -> [FileSnapshot] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: resourceKeys,
            options: []
        )
        return urls.compactMap(snapshot(of:))
    }

    public static func snapshot(of url: URL) -> FileSnapshot? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        let values = try? url.resourceValues(forKeys: Set(resourceKeys))
        let isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
        return FileSnapshot(
            url: url,
            fileID: UInt64(info.st_ino),
            isDirectory: isDirectory,
            isPackage: values?.isPackage ?? false,
            size: isDirectory ? 0 : Int64(info.st_size),
            modifiedAt: Date(timespec: info.st_mtimespec),
            addedAt: values?.addedToDirectoryDate ?? values?.creationDate
        )
    }

    public static func fileID(of url: URL) -> UInt64? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return UInt64(info.st_ino)
    }

    /// Total size of a directory's contents, giving up after `limit` entries so a
    /// huge unzipped folder can't stall the watcher.
    public static func deepSize(of url: URL, limit: Int = 20_000) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        var count = 0
        for case let child as URL in enumerator {
            count += 1
            if count > limit { break }
            let values = try? child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }
}

extension Date {
    init(timespec ts: timespec) {
        self.init(timeIntervalSince1970: TimeInterval(ts.tv_sec) + TimeInterval(ts.tv_nsec) / 1_000_000_000)
    }
}
