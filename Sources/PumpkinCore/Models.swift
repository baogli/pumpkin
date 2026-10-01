import Foundation

/// A file with a timer on it.
public struct TrackedItem: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Last known location. Kept fresh when the file is renamed in place.
    public var path: String
    /// The folder the file was in when its timer was set. The file is only ever
    /// trashed while it is still directly inside this folder.
    public var folderPath: String
    public var fileID: UInt64
    public var volumeID: UInt64?
    public var bookmark: Data?
    public var size: Int64
    public var isFolder: Bool
    public var source: String?
    public var kind: String?
    public var startedAt: Date
    public var expiresAt: Date
    public var lastError: String?

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        folderPath: String,
        fileID: UInt64,
        bookmark: Data?,
        size: Int64,
        isFolder: Bool,
        source: String?,
        startedAt: Date,
        expiresAt: Date,
        lastError: String? = nil,
        volumeID: UInt64? = nil,
        kind: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.folderPath = folderPath
        self.fileID = fileID
        self.volumeID = volumeID
        self.bookmark = bookmark
        self.size = size
        self.isFolder = isFolder
        self.source = source
        self.kind = kind
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.lastError = lastError
    }

    public var url: URL { URL(fileURLWithPath: path) }
    public var folderURL: URL { URL(fileURLWithPath: folderPath, isDirectory: true) }

    public func remaining(at date: Date) -> TimeInterval {
        expiresAt.timeIntervalSince(date)
    }

    /// 1 when the timer was just set, 0 when it's due.
    public func fractionRemaining(at date: Date) -> Double {
        let total = expiresAt.timeIntervalSince(startedAt)
        guard total > 0 else { return 0 }
        return min(1, max(0, remaining(at: date) / total))
    }
}

/// Something Pumpkin moved to the Trash, kept so it can be put back.
public struct TrashRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var originalPath: String
    public var trashedPath: String?
    public var trashedAt: Date
    public var isFolder: Bool
    public var size: Int64
    public var restoredAt: Date?
    public var kind: String?
    public var fileID: UInt64?
    public var volumeID: UInt64?

    public init(
        id: UUID = UUID(),
        name: String,
        originalPath: String,
        trashedPath: String?,
        trashedAt: Date,
        isFolder: Bool,
        size: Int64,
        restoredAt: Date? = nil,
        kind: String? = nil,
        fileID: UInt64? = nil,
        volumeID: UInt64? = nil
    ) {
        self.id = id
        self.name = name
        self.originalPath = originalPath
        self.trashedPath = trashedPath
        self.trashedAt = trashedAt
        self.isFolder = isFolder
        self.size = size
        self.restoredAt = restoredAt
        self.kind = kind; self.fileID = fileID; self.volumeID = volumeID
    }

    /// Whether the item is still sitting in the Trash where we left it.
    public var canPutBack: Bool {
        guard restoredAt == nil, let trashedPath else { return false }
        var info = stat()
        guard lstat(trashedPath, &info) == 0 else { return false }
        return (fileID.map { $0 == UInt64(info.st_ino) } ?? true) && (volumeID.map { $0 == UInt64(info.st_dev) } ?? true)
    }
}

public struct PersistedState: Codable, Equatable {
    public var schemaVersion: Int = 2
    public var recordings: [RecordingEntry]
    public var pendingGroups: [PendingFileGroup]
    public var items: [TrackedItem]
    public var history: [TrashRecord]
    /// Last time the folder was looked at; entries added after this are new.
    public var lastSeenAt: Date?
    /// Set while timers are frozen.
    public var pausedAt: Date?

    public init(items: [TrackedItem] = [], history: [TrashRecord] = [], lastSeenAt: Date? = nil, pausedAt: Date? = nil, recordings: [RecordingEntry] = [], pendingGroups: [PendingFileGroup] = []) {
        self.items = items
        self.history = history
        self.lastSeenAt = lastSeenAt
        self.pausedAt = pausedAt
        self.recordings = recordings
        self.pendingGroups = pendingGroups
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, items, history, lastSeenAt, pausedAt, recordings, pendingGroups
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([TrackedItem].self, forKey: .items) ?? []
        history = try container.decodeIfPresent([TrashRecord].self, forKey: .history) ?? []
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        pausedAt = try container.decodeIfPresent(Date.self, forKey: .pausedAt)
        recordings = try container.decodeIfPresent([RecordingEntry].self, forKey: .recordings) ?? []
        pendingGroups = try container.decodeIfPresent([PendingFileGroup].self, forKey: .pendingGroups) ?? []
    }
}
