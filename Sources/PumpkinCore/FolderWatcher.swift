import Foundation

/// Watches one folder and reports entries that newly appear in it once they have
/// finished downloading.
///
/// Every method must be called on `queue`, and every callback is delivered on it.
public final class FolderWatcher {
    public let folder: URL

    /// New, settled entries. Each entry is reported at most once.
    public var onNewItems: (([FileSnapshot]) -> Void)?
    /// Every successful scan, with the full listing.
    public var onScan: (([FileSnapshot]) -> Void)?
    /// The folder couldn't be read (missing, or access denied).
    public var onFailure: ((Error) -> Void)?
    /// Only settled entries passing this test are reported (for example, only
    /// screenshots on the Desktop). The rest are quietly marked as seen.
    public var accept: ((FileSnapshot) -> Bool)?

    private let queue: DispatchQueue
    private let pollInterval: TimeInterval
    private let safetyInterval: TimeInterval
    private var tracker: StabilityTracker
    private let makeTracker: () -> StabilityTracker

    private var source: DispatchSourceFileSystemObject?
    private var safetyTimer: DispatchSourceTimer?
    private var scanScheduled = false
    private var reattachScheduled = false
    private var known: Set<UInt64> = []
    public private(set) var isRunning = false

    public init(
        folder: URL,
        queue: DispatchQueue = .main,
        settleInterval: TimeInterval = 1.5,
        emptySettleInterval: TimeInterval = 6,
        pollInterval: TimeInterval = 1,
        safetyInterval: TimeInterval = 30
    ) {
        self.folder = folder
        self.queue = queue
        self.pollInterval = pollInterval
        self.safetyInterval = safetyInterval
        self.makeTracker = { StabilityTracker(settleInterval: settleInterval, emptySettleInterval: emptySettleInterval) }
        self.tracker = makeTracker()
    }

    deinit {
        source?.cancel()
        safetyTimer?.cancel()
    }

    /// Starts watching. Entries already in the folder count as seen, except ones
    /// added after `newSince` (e.g. while the app wasn't running) that aren't in
    /// `alreadyKnown`; those are reported once they settle.
    ///
    /// In-progress downloads are never counted as seen, so a transfer that is
    /// running at launch is still reported when it finishes.
    public func start(newSince: Date? = nil, alreadyKnown: Set<UInt64> = []) throws {
        stop()
        let items = try FolderScanner.scan(folder)

        known = []
        for item in items where !DownloadFilter.isIgnorable(name: item.name) {
            if alreadyKnown.contains(item.fileID) {
                known.insert(item.fileID)
            } else if let since = newSince, let added = item.addedAt, added > since {
                continue
            } else {
                known.insert(item.fileID)
            }
        }

        isRunning = true
        try attachSource()
        startSafetyTimer()
        scheduleScan(after: 0)
    }

    public func stop() {
        isRunning = false
        source?.cancel()
        source = nil
        safetyTimer?.cancel()
        safetyTimer = nil
        tracker = makeTracker()
    }

    /// Treat an entry as already seen (for example a file we just put back from the Trash).
    public func markKnown(_ fileID: UInt64) {
        known.insert(fileID)
    }

    public func scheduleScan(after delay: TimeInterval) {
        guard isRunning, !scanScheduled else { return }
        scanScheduled = true
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.scanScheduled = false
            self.scan()
        }
    }

    // MARK: - Private

    private func attachSource() throws {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
                // The folder itself moved away; watch the path again instead.
                self.detachAndReattach()
            } else {
                self.scheduleScan(after: 0.2)
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func detachAndReattach() {
        source?.cancel()
        source = nil
        scheduleReattach(after: 1)
    }

    private func scheduleReattach(after delay: TimeInterval) {
        guard isRunning, !reattachScheduled else { return }
        reattachScheduled = true
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.reattachScheduled = false
            guard self.isRunning, self.source == nil else { return }
            do {
                try self.attachSource()
                self.scheduleScan(after: 0)
            } catch {
                self.onFailure?(error)
                self.scheduleReattach(after: 5)
            }
        }
    }

    private func startSafetyTimer() {
        // Directory events cover almost everything, but a periodic look is cheap
        // insurance against missed events (sleep, network volumes, etc.).
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + safetyInterval, repeating: safetyInterval, leeway: .seconds(2))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.source == nil {
                self.scheduleReattach(after: 0)
            }
            self.scheduleScan(after: 0)
        }
        timer.resume()
        safetyTimer = timer
    }

    private func scan() {
        guard isRunning else { return }

        let items: [FileSnapshot]
        do {
            items = try FolderScanner.scan(folder)
        } catch {
            onFailure?(error)
            return
        }

        let present = Set(items.map(\.fileID))
        known.formIntersection(present)

        let names = Set(items.map(\.name))
        let candidates = items.filter {
            !known.contains($0.fileID) && !DownloadFilter.isIgnorable(name: $0.name)
        }
        let ready = tracker.evaluate(candidates, allNames: names, now: Date()) { item in
            item.isDirectory ? FolderScanner.deepSize(of: item.url) : item.size
        }
        for item in ready {
            known.insert(item.fileID)
        }

        onScan?(items)
        let reported = accept.map { test in ready.filter(test) } ?? ready
        if !reported.isEmpty {
            onNewItems?(reported)
        }

        // Writes inside an existing file don't fire directory events, so keep
        // polling while something is still settling.
        if tracker.pendingCount > 0 {
            scheduleScan(after: pollInterval)
        }
    }
}
