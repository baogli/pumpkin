import Foundation

/// Reads and writes the app's state as a small JSON file in Application Support.
public final class StateStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return migratedURL(in: base)
    }

    /// Copy the previous app's timers once, preserving the original as a backup.
    /// A failed copy keeps using the original, so an upgrade cannot lose timers.
    public static func migratedURL(in base: URL) -> URL {
        let current = base.appendingPathComponent("Pumpkin", isDirectory: true).appendingPathComponent("state.json")
        let legacy = base.appendingPathComponent("ShelfLife", isDirectory: true).appendingPathComponent("state.json")
        let fm = FileManager.default
        guard !fm.fileExists(atPath: current.path), fm.fileExists(atPath: legacy.path) else { return current }
        do {
            try fm.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: legacy, to: current)
            return current
        } catch {
            return legacy
        }
    }

    public func load() -> PersistedState {
        guard let data = try? Data(contentsOf: url) else { return PersistedState() }
        do {
            return try JSONDecoder().decode(PersistedState.self, from: data)
        } catch {
            // Set the unreadable file aside rather than overwriting it.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = url.deletingLastPathComponent().appendingPathComponent("state.unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            return PersistedState()
        }
    }

    public func save(_ state: PersistedState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
