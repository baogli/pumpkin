import Foundation

/// Waits until a new entry stops changing before it is reported, so we never ask
/// about a download that is still being written.
public struct StabilityTracker {
    struct Signature: Equatable {
        var size: Int64
        var modifiedAt: Date?
    }

    struct Entry {
        var signature: Signature
        var stableSince: Date
    }

    /// How long a non-empty entry must stay unchanged.
    public var settleInterval: TimeInterval
    /// Empty files get longer, since some browsers create a zero-byte placeholder first.
    public var emptySettleInterval: TimeInterval

    private var entries: [UInt64: Entry] = [:]

    public init(settleInterval: TimeInterval = 1.5, emptySettleInterval: TimeInterval = 6) {
        self.settleInterval = settleInterval
        self.emptySettleInterval = emptySettleInterval
    }

    /// Number of candidates still being watched.
    public var pendingCount: Int { entries.count }

    /// Feed every current candidate (unknown, non-ignorable entries). Returns the ones
    /// that have settled; those are forgotten by the tracker. Candidates that
    /// disappeared since the last call are dropped.
    public mutating func evaluate(
        _ candidates: [FileSnapshot],
        allNames: Set<String>,
        now: Date,
        sizeOf: (FileSnapshot) -> Int64 = { $0.size }
    ) -> [FileSnapshot] {
        var ready: [FileSnapshot] = []
        var next: [UInt64: Entry] = [:]

        for candidate in candidates {
            // A directory's own mtime doesn't reflect writes deeper inside, so
            // folders are judged on their total size alone.
            let signature = Signature(
                size: sizeOf(candidate),
                modifiedAt: candidate.isDirectory ? nil : candidate.modifiedAt
            )
            var entry = entries[candidate.fileID] ?? Entry(signature: signature, stableSince: now)
            if entry.signature != signature {
                entry = Entry(signature: signature, stableSince: now)
            }

            let required = signature.size == 0 ? emptySettleInterval : settleInterval
            let settled = now.timeIntervalSince(entry.stableSince) >= required
            if settled && !DownloadFilter.hasPartialSibling(candidate.name, among: allNames) {
                var finished = candidate
                finished.size = signature.size
                ready.append(finished)
            } else {
                next[candidate.fileID] = entry
            }
        }

        entries = next
        return ready
    }
}
