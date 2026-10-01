import Foundation

/// Metadata only. Video bytes remain in their original file.
public struct RecordingEntry: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable { case pending, finished, failed }
    public var id: UUID
    public var path: String
    public var createdAt: Date
    public var duration: Double
    public var size: Int64
    public var screen: String
    public var audio: String
    public var format: String
    public var status: Status
    public var fileID: UInt64?
    public var volumeID: UInt64?
    public var bookmark: Data?
    public var error: String?

    public init(id: UUID = UUID(), path: String, createdAt: Date = Date(), screen: String, audio: String, format: String) {
        self.id = id; self.path = path; self.createdAt = createdAt
        self.screen = screen; self.audio = audio; self.format = format
        duration = 0; size = 0; status = .pending
    }
    public var url: URL { URL(fileURLWithPath: path) }
    public var partialURL: URL { url.deletingPathExtension().appendingPathExtension("partial.mp4") }
    public func matches(_ candidate: URL) -> Bool {
        guard let fileID else { return false }
        var info = stat()
        return lstat(candidate.path, &info) == 0 && UInt64(info.st_ino) == fileID && (volumeID == nil || UInt64(info.st_dev) == volumeID)
    }
    public var locatedURL: URL? {
        if matches(url) { return url }
        var stale = false
        if let bookmark, let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale), matches(resolved) { return resolved }
        return nil
    }
    public func protects(_ candidate: URL) -> Bool {
        let path = candidate.standardizedFileURL.path
        if status == .pending && (path == url.standardizedFileURL.path || path == partialURL.standardizedFileURL.path) { return true }
        return matches(candidate)
    }
}

/// Unanswered questions survive an ordinary restart without becoming timers.
public struct PendingFileGroup: Codable, Equatable {
    public var id: UUID
    public var snapshots: [FileSnapshot]
    public var sources: [String?]
    public var kind: String
    public var selection: Int
    public var arrivedAt: Date
    public var touched: Bool
    public init(id: UUID, snapshots: [FileSnapshot], sources: [String?], kind: String, selection: Int, arrivedAt: Date, touched: Bool) {
        self.id = id; self.snapshots = snapshots; self.sources = sources; self.kind = kind
        self.selection = selection; self.arrivedAt = arrivedAt; self.touched = touched
    }
}
