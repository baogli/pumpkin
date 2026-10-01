import AppKit
import Observation
import PumpkinCore

enum ItemKind: String, Hashable {
    case download
    case screenshot
    case recording
}

struct PromptItem: Identifiable, Hashable {
    var snapshot: FileSnapshot
    var source: String?

    var id: UInt64 { snapshot.fileID }
    var name: String { snapshot.name }
    var url: URL { snapshot.url }
}

/// One question on screen: "how long should these keep?"
struct PromptBatch: Identifiable, Hashable {
    let id: UUID
    var items: [PromptItem]
    var stops: [ShelfDuration]
    var selection: Int
    var kind: ItemKind = .download
    var isDemo: Bool
    var arrivedAt: Date
    /// The user has started interacting, so no more files get folded into it.
    var touched = false

    var primary: PromptItem { items[0] }
    var selectedDuration: ShelfDuration { stops[min(max(selection, 0), stops.count - 1)] }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.snapshot.size } }
    var title: String { items.count == 1 ? primary.name : "\(items.count) items" }
}

struct Toast: Identifiable, Hashable {
    enum Kind: Hashable {
        case trashed([TrashRecord])
        case restored(name: String, count: Int)
        case failed(title: String, message: String)
    }

    let id = UUID()
    var kind: Kind
}

struct Confirmation: Identifiable, Hashable {
    enum Kind: Hashable {
        case scheduled(expiresAt: Date)
        case kept
    }

    let id = UUID()
    var kind: Kind
    var title: String
    var iconPath: String
    var isFolder: Bool
    var isScreenshot = false
}

/// What the drop-down panel is showing.
enum PanelScene: Hashable {
    case list
    case prompt(PromptBatch)
    case confirmation(Confirmation)
    case toast(Toast)

    /// Changes whenever the panel should cross-fade to new content.
    var transitionKey: String {
        switch self {
        case .list: return "list"
        case .prompt(let batch): return "prompt-\(batch.id)"
        case .confirmation(let confirmation): return "confirmation-\(confirmation.id)"
        case .toast(let toast): return "toast-\(toast.id)"
        }
    }
}

/// Progress of the onboarding "Try It" step.
enum DemoStatus: Equatable {
    case idle
    case waitingForAnswer
    case scheduled(Date)
    case kept
    case trashed
    case failed(String)
}

struct AppActions {
    var showSettings: () -> Void = {}
    var showOnboarding: () -> Void = {}
    var showAbout: () -> Void = {}
}

@MainActor @Observable
final class AppModel {
    let prefs: Preferences

    private(set) var recordings: [RecordingEntry] = []
    var deferredTrashCount = 0
    var automaticPanelsSuppressed = false {
        didSet { restartPromptTimer(); restartToastTimer() }
    }
    @ObservationIgnored var protectedURL: (URL) -> Bool = { _ in false }
    private(set) var items: [TrackedItem] = []
    private(set) var history: [TrashRecord] = []
    private(set) var prompts: [PromptBatch] = []
    private(set) var toast: Toast?
    private(set) var confirmation: Confirmation?
    private(set) var pausedAt: Date?
    private(set) var folderProblem: String?
    private(set) var isWatching = false
    /// Where screenshots are being watched, when that's a separate folder.
    private(set) var screenshotFolder: URL?
    private(set) var screenshotProblem: String?
    /// When the question on screen will tuck itself away, if it will.
    private(set) var promptDeadline: Date?
    private(set) var demoStatus: DemoStatus = .idle

    var isListOpen = false {
        didSet {
            guard isListOpen != oldValue else { return }
            if isListOpen {
                toast = nil
                confirmation = nil
            }
            restartPromptTimer()
        }
    }

    var isPointerInside = false {
        didSet {
            guard isPointerInside != oldValue else { return }
            restartPromptTimer()
            restartToastTimer()
        }
    }

    @ObservationIgnored var actions = AppActions()

    @ObservationIgnored private let store: StateStore
    @ObservationIgnored private let engine: ExpiryEngine
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var screenshotWatcher: FolderWatcher?
    @ObservationIgnored private var screenshotLocationTimer: Timer?
    /// Where macOS saves screenshots. Replaceable for tests.
    @ObservationIgnored var resolveScreenshotFolder: () -> URL = { Screenshots.folder() }
    @ObservationIgnored private var lastSeenAt: Date?
    @ObservationIgnored private var lastPersistedAt = Date.distantPast
    @ObservationIgnored private var expiryTimer: Timer?
    @ObservationIgnored private var promptTimer: Timer?
    @ObservationIgnored private var toastTimer: Timer?
    @ObservationIgnored private var confirmationTimer: Timer?
    @ObservationIgnored private var retryTimer: Timer?
    @ObservationIgnored private var demoFileIDs: Set<UInt64> = []
    @ObservationIgnored private var demoItemIDs: Set<UUID> = []
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []

    static let historyLimit = 30
    static let visibleHistory = 5

    init(prefs: Preferences, store: StateStore = StateStore(url: StateStore.defaultURL), engine: ExpiryEngine = ExpiryEngine()) {
        self.prefs = prefs
        self.store = store
        self.engine = engine

        let state = store.load()
        recordings = state.recordings.map { entry in
            var copy = entry
            if copy.status == .pending { copy.status = .failed; copy.error = "Recording was interrupted. A partial MP4 may not be playable." }
            return copy
        }
        prompts = state.pendingGroups.compactMap { group in
            let entries = group.snapshots.enumerated().compactMap { index, snapshot -> PromptItem? in
                guard snapshot.matches(snapshot.url) else { return nil }
                return PromptItem(snapshot: snapshot, source: group.sources.indices.contains(index) ? group.sources[index] : nil)
            }
            guard !entries.isEmpty else { return nil }
            return PromptBatch(id: group.id, items: entries, stops: ShelfDuration.standardStops, selection: group.selection, kind: ItemKind(rawValue: group.kind) ?? .download, isDemo: false, arrivedAt: group.arrivedAt, touched: group.touched)
        }
        items = state.items
        history = state.history
        pausedAt = state.pausedAt
        lastSeenAt = state.lastSeenAt
        trimHistory()

        let workspace = NSWorkspace.shared.notificationCenter
        notificationTokens.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.expireDue()
                self?.watcher?.scheduleScan(after: 1)
                self?.screenshotWatcher?.scheduleScan(after: 1)
            }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.expireDue()
            }
        })
    }

    // MARK: - Derived state

    var scene: PanelScene? {
        if isListOpen { return .list }
        if automaticPanelsSuppressed { return nil }
        if let confirmation { return .confirmation(confirmation) }
        if !isPaused, let batch = prompts.first { return .prompt(batch) }
        if let toast { return .toast(toast) }
        return nil
    }

    var isPaused: Bool { pausedAt != nil }

    /// The moment timers are measured against: frozen while paused.
    func clock(_ now: Date) -> Date { pausedAt ?? now }

    var sortedItems: [TrackedItem] { items.sorted { $0.expiresAt < $1.expiresAt } }
    var soonest: TrackedItem? { items.min { $0.expiresAt < $1.expiresAt } }
    var recentHistory: [TrashRecord] { Array(history.prefix(Self.visibleHistory)) }
    var queuedPromptCount: Int { max(0, prompts.count - 1) }

    // MARK: - Watching

    func startWatching() {
        watcher?.stop()
        watcher = nil
        retryTimer?.invalidate()
        retryTimer = nil

        guard prefs.watchDownloads else { isWatching = false; folderProblem = nil; startScreenshotWatching(); expireDue(); return }
        let folder = prefs.watchedFolder
        let watcher = FolderWatcher(folder: folder)
        watcher.onNewItems = { [weak self] snapshots in
            MainActor.assumeIsolated {
                let screenshots = snapshots.filter { Screenshots.isTaggedScreenCapture($0.url) }
                self?.handleNewItems(snapshots.filter { !Screenshots.isTaggedScreenCapture($0.url) }, kind: .download)
                self?.handleNewItems(screenshots, kind: .screenshot)
            }
        }
        watcher.onScan = { [weak self] listing in
            MainActor.assumeIsolated { self?.handleScan(listing, in: folder) }
        }
        watcher.onFailure = { [weak self] error in
            MainActor.assumeIsolated { self?.handleWatchFailure(error) }
        }

        // Anything that arrived while Pumpkin wasn't running gets asked about,
        // within reason: a months-old backlog would just be noise.
        let since = lastSeenAt.map { max($0, Date().addingTimeInterval(-3 * 86_400)) }
        do {
            try watcher.start(newSince: since, alreadyKnown: Set(items.filter { ItemLocator.canonicalPath($0.folderURL) == ItemLocator.canonicalPath(folder) }.map(\.fileID)))
            self.watcher = watcher
            isWatching = true
            folderProblem = nil
        } catch {
            isWatching = false
            handleWatchFailure(error)
            scheduleWatchRetry()
        }
        startScreenshotWatching()
        expireDue()
    }

    func retryWatching() {
        let folder = prefs.watchedFolder
        let screenshots = prefs.watchScreenshots ? resolveScreenshotFolder() : nil
        Task {
            // Asks macOS for access off the main thread, so its prompt can't stall the UI.
            if prefs.watchDownloads { _ = await FolderAccess.check(folder) }
            if let screenshots {
                _ = await FolderAccess.check(screenshots)
            }
            startWatching()
        }
    }

    func setWatchScreenshots(_ enabled: Bool) {
        prefs.watchScreenshots = enabled
        if enabled {
            let folder = resolveScreenshotFolder()
            Task {
                _ = await FolderAccess.check(folder)
                startScreenshotWatching()
            }
        } else {
            startScreenshotWatching()
        }
    }

    /// Watches the screenshot folder for new screenshots only. Skipped when
    /// screenshots already land in the watched folder, which asks about everything.
    private func startScreenshotWatching() {
        screenshotWatcher?.stop()
        screenshotWatcher = nil
        screenshotProblem = nil
        screenshotLocationTimer?.invalidate()
        screenshotLocationTimer = nil

        guard prefs.watchScreenshots else {
            screenshotFolder = nil
            return
        }
        let folder = resolveScreenshotFolder()
        screenshotFolder = folder

        // The user can move screenshots elsewhere at any time (⇧⌘5 › Options).
        screenshotLocationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let current = self.screenshotFolder else { return }
                if ItemLocator.canonicalPath(self.resolveScreenshotFolder()) != ItemLocator.canonicalPath(current) {
                    self.startScreenshotWatching()
                }
            }
        }

        guard !prefs.watchDownloads || ItemLocator.canonicalPath(folder) != ItemLocator.canonicalPath(prefs.watchedFolder) else { return }

        let watcher = FolderWatcher(folder: folder)
        watcher.accept = { Screenshots.isTaggedScreenCapture($0.url) }
        watcher.onNewItems = { [weak self] snapshots in
            MainActor.assumeIsolated { self?.handleNewItems(snapshots, kind: .screenshot) }
        }
        watcher.onScan = { [weak self] listing in
            MainActor.assumeIsolated {
                self?.screenshotProblem = nil
                self?.handleScan(listing, in: folder)
            }
        }
        watcher.onFailure = { [weak self] _ in
            MainActor.assumeIsolated { self?.reportScreenshotProblem(folder) }
        }
        let since = lastSeenAt.map { max($0, Date().addingTimeInterval(-3 * 86_400)) }
        do {
            try watcher.start(newSince: since, alreadyKnown: Set(items.filter { ItemLocator.canonicalPath($0.folderURL) == ItemLocator.canonicalPath(folder) }.map(\.fileID)))
            screenshotWatcher = watcher
        } catch {
            reportScreenshotProblem(folder)
        }
    }

    private func reportScreenshotProblem(_ folder: URL) {
        screenshotProblem = "Pumpkin can’t see screenshots on your \(folderName(for: folder))."
    }

    func folderName(for url: URL) -> String {
        FileManager.default.displayName(atPath: url.path)
    }

    func changeWatchedFolder(to url: URL?) {
        prefs.customFolderPath = url?.path
        // Existing files in the new folder are not "new downloads".
        lastSeenAt = nil
        persist()
        retryWatching()
    }

    private func scheduleWatchRetry() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.prefs.watchDownloads, !self.isWatching else { return }
                self.retryWatching()
            }
        }
    }

    private func handleWatchFailure(_ error: Error) {
        let name = prefs.watchedFolderName
        if FileManager.default.fileExists(atPath: prefs.watchedFolder.path) {
            folderProblem = "Pumpkin can’t read your \(name) folder."
        } else {
            folderProblem = "The \(name) folder is missing."
        }
    }

    func handleScan(_ listing: [FileSnapshot], in folder: URL) {
        let watchedPath = ItemLocator.canonicalPath(folder)
        if watchedPath == ItemLocator.canonicalPath(prefs.watchedFolder), folderProblem != nil {
            folderProblem = nil
        }

        let byID = Dictionary(listing.map { ($0.fileID, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        var dropped: Set<UUID> = []

        for index in items.indices where ItemLocator.canonicalPath(items[index].folderURL) == watchedPath {
            if let entry = byID[items[index].fileID], items[index].volumeID == nil || entry.volumeID == items[index].volumeID {
                // Follow renames so the list shows the current name.
                if entry.url.path != items[index].path {
                    items[index].path = entry.url.path
                    items[index].name = entry.name
                    changed = true
                }
            } else if case .inFolder = ItemLocator.locate(items[index]) {
                continue
            } else {
                // Deleted, or moved elsewhere by the user: no longer ours to trash.
                dropped.insert(items[index].id)
            }
        }
        if !dropped.isEmpty {
            items.removeAll { dropped.contains($0.id) }
            changed = true
            scheduleExpiryTimer()
        }

        // Forget questions about files that vanished before they were answered.
        var promptsChanged = false
        var updatedPrompts = prompts
        for index in updatedPrompts.indices {
            let before = updatedPrompts[index].items
            updatedPrompts[index].items = before.compactMap { item in
                guard ItemLocator.canonicalPath(item.url.deletingLastPathComponent()) == watchedPath else { return item }
                guard let entry = byID[item.id], item.snapshot.volumeID == nil || entry.volumeID == item.snapshot.volumeID else { return nil }
                var copy = item
                copy.snapshot.url = entry.url
                return copy
            }
            if updatedPrompts[index].items != before {
                promptsChanged = true
            }
        }
        if promptsChanged {
            let hadFront = prompts.first?.id
            prompts = updatedPrompts.filter { !$0.items.isEmpty }
            if prompts.first?.id != hadFront {
                restartPromptTimer()
            }
        }

        lastSeenAt = Date()
        if changed || promptsChanged || Date().timeIntervalSince(lastPersistedAt) > 60 {
            persist()
        }
    }

    func handleNewItems(_ snapshots: [FileSnapshot], kind: ItemKind) {
        var fresh = snapshots.filter { snapshot in
            !items.contains(where: { $0.fileID == snapshot.fileID && ($0.volumeID == nil || $0.volumeID == snapshot.volumeID) && ItemLocator.isDirectChild(snapshot.url, of: $0.folderURL) })
                && !prompts.contains(where: { $0.items.contains { $0.snapshot.fileID == snapshot.fileID && ($0.snapshot.volumeID == nil || $0.snapshot.volumeID == snapshot.volumeID) && ItemLocator.canonicalPath($0.url.deletingLastPathComponent()) == ItemLocator.canonicalPath(snapshot.url.deletingLastPathComponent()) } })
                && !DownloadFilter.isIgnorable(name: snapshot.name)
                && !recordings.contains(where: { $0.protects(snapshot.url) })
                && !protectedURL(snapshot.url) && !ItemLocator.isInTrash(snapshot.url)
        }
        if !prefs.askAboutFolders {
            fresh.removeAll(where: \.isFolder)
        }

        for sample in fresh where demoFileIDs.contains(sample.fileID) {
            enqueue([sample], kind: .download, isDemo: true)
        }
        let regular = fresh.filter { !demoFileIDs.contains($0.fileID) }
        guard !regular.isEmpty else { return }
        enqueue(regular, kind: kind, isDemo: false)
    }

    private func enqueue(_ snapshots: [FileSnapshot], kind: ItemKind, isDemo: Bool) {
        let newItems = snapshots
            .sorted { ($0.addedAt ?? .distantPast) < ($1.addedAt ?? .distantPast) }
            .map { snapshot in
                PromptItem(
                    snapshot: snapshot,
                    source: kind == .screenshot ? folderName(for: snapshot.url.deletingLastPathComponent()) : DownloadSource.describe(snapshot.url)
                )
            }

        // Several files landing together become one question, as long as the
        // user hasn't started answering it yet.
        if !isDemo, let last = prompts.indices.last, !prompts[last].isDemo, !prompts[last].touched,
           prompts[last].kind == kind, Date().timeIntervalSince(prompts[last].arrivedAt) < 10,
           prompts[last].items.first.map({ first in newItems.allSatisfy { ItemLocator.canonicalPath($0.url.deletingLastPathComponent()) == ItemLocator.canonicalPath(first.url.deletingLastPathComponent()) } }) == true {
            prompts[last].items.append(contentsOf: newItems)
            persist()
            if last == 0 {
                restartPromptTimer()
            }
            return
        }

        let stops = isDemo ? ShelfDuration.demoStops : ShelfDuration.standardStops
        let selection = isDemo ? 0 : ShelfDuration.nearestIndex(to: prefs.defaultDuration, in: stops)
        prompts.append(PromptBatch(id: UUID(), items: newItems, stops: stops, selection: selection, kind: kind, isDemo: isDemo, arrivedAt: Date()))
        persist()
        if isDemo {
            demoStatus = .waitingForAnswer
        }
        if prompts.count == 1 {
            restartPromptTimer()
        }
    }

    // MARK: - Answering

    func select(_ index: Int, in batchID: UUID) {
        guard let position = prompts.firstIndex(where: { $0.id == batchID }) else { return }
        let clamped = min(max(index, 0), prompts[position].stops.count - 1)
        let newlyTouched = !prompts[position].touched
        prompts[position].touched = true
        guard prompts[position].selection != clamped else { if newlyTouched { persist() }; return }
        prompts[position].selection = clamped
        persist()
        if position == 0 {
            restartPromptTimer()
        }
    }

    func nudgeSelection(by delta: Int) {
        guard let batch = prompts.first else { return }
        select(batch.selection + delta, in: batch.id)
    }

    /// "Done": start the timers.
    func confirm(_ batchID: UUID) {
        guard let position = prompts.firstIndex(where: { $0.id == batchID }) else { return }
        let batch = prompts.remove(at: position)
        let now = clock(Date())
        let duration = batch.selectedDuration.seconds

        let added: [TrackedItem] = batch.items.compactMap { entry in
            guard let url = currentURL(of: entry) else { return nil }
            return TrackedItem(
                name: url.lastPathComponent,
                path: url.path,
                folderPath: url.deletingLastPathComponent().path,
                fileID: entry.snapshot.fileID,
                bookmark: ItemLocator.makeBookmark(for: url),
                size: entry.snapshot.size,
                isFolder: entry.snapshot.isFolder,
                source: entry.source,
                startedAt: now,
                expiresAt: now.addingTimeInterval(duration),
                volumeID: ItemLocator.volumeID(of: url),
                kind: batch.kind.rawValue
            )
        }
        items.append(contentsOf: added)
        persist()
        scheduleExpiryTimer()

        if batch.isDemo {
            demoItemIDs.formUnion(added.map(\.id))
            demoStatus = added.isEmpty ? .failed("The sample file disappeared.") : .scheduled(now.addingTimeInterval(duration))
        }

        if !added.isEmpty && !isListOpen {
            showConfirmation(Confirmation(
                kind: .scheduled(expiresAt: now.addingTimeInterval(duration)),
                title: added.count == 1 ? added[0].name : "\(added.count) items",
                iconPath: added[0].path,
                isFolder: added[0].isFolder,
                isScreenshot: batch.kind == .screenshot
            ))
        } else {
            restartPromptTimer()
        }
    }

    /// "Keep Forever": leave the files alone.
    func keep(_ batchID: UUID) {
        guard let position = prompts.firstIndex(where: { $0.id == batchID }) else { return }
        let batch = prompts.remove(at: position)
        persist()
        if batch.isDemo {
            demoStatus = .kept
        }
        if isListOpen {
            restartPromptTimer()
        } else {
            showConfirmation(Confirmation(kind: .kept, title: batch.title, iconPath: batch.primary.url.path, isFolder: batch.primary.snapshot.isFolder, isScreenshot: batch.kind == .screenshot))
        }
    }

    /// The question went unanswered (timed out, or Esc).
    func dismissCurrentPrompt() {
        guard let batch = prompts.first else { return }
        switch prefs.unansweredPolicy {
        case .keep:
            prompts.removeFirst()
            persist()
            if batch.isDemo {
                demoStatus = .kept
            }
            restartPromptTimer()
        case .useDefault:
            if !batch.touched {
                prompts[0].selection = ShelfDuration.nearestIndex(to: prefs.defaultDuration, in: batch.stops)
            }
            confirm(batch.id)
        }
    }

    func dismissToast() {
        toastTimer?.invalidate()
        toast = nil
    }

    private func currentURL(of entry: PromptItem) -> URL? {
        if entry.snapshot.matches(entry.url) {
            return entry.url
        }
        // Renamed since it arrived: find it again by inode.
        let folder = entry.url.deletingLastPathComponent()
        return (try? FolderScanner.scan(folder))?.first { entry.snapshot.matches($0.url) }?.url
    }

    private func restartPromptTimer() {
        promptTimer?.invalidate()
        promptTimer = nil
        let timeout = prefs.promptTimeout
        guard !automaticPanelsSuppressed, !isPaused, let batch = prompts.first, !batch.isDemo, timeout > 0, confirmation == nil, !isListOpen, !isPointerInside else {
            promptDeadline = nil
            return
        }
        promptDeadline = Date().addingTimeInterval(timeout)
        promptTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissCurrentPrompt() }
        }
    }

    private func showConfirmation(_ value: Confirmation) {
        promptTimer?.invalidate()
        promptDeadline = nil
        confirmation = value
        confirmationTimer?.invalidate()
        confirmationTimer = Timer.scheduledTimer(withTimeInterval: 1.7, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.confirmation = nil
                self?.restartPromptTimer()
            }
        }
    }

    private func showToast(_ kind: Toast.Kind) {
        if automaticPanelsSuppressed, case .trashed(let records) = kind { deferredTrashCount += records.count }
        guard !isListOpen else { return }
        toast = Toast(kind: kind)
        restartToastTimer()
    }

    private func restartToastTimer() {
        toastTimer?.invalidate()
        toastTimer = nil
        guard !automaticPanelsSuppressed, let toast, !isPointerInside else { return }
        let duration: TimeInterval
        switch toast.kind {
        case .trashed: duration = 6
        case .restored: duration = 2.5
        case .failed: duration = 8
        }
        toastTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.toast = nil }
        }
    }

    // MARK: - Expiry

    private func scheduleExpiryTimer() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        guard !isPaused, let next = soonest else { return }
        let interval = max(0.05, next.expiresAt.timeIntervalSinceNow)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.expireDue() }
        }
        timer.tolerance = min(1, interval * 0.02)
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    func expireDue(now: Date = Date()) {
        guard !isPaused else { return }
        let due = items.filter { $0.expiresAt <= now }
        guard !due.isEmpty else {
            scheduleExpiryTimer()
            return
        }

        var trashed: [TrashRecord] = []
        var firstFailure: (name: String, message: String)?
        for item in due {
            switch engine.expire(item, now: now) {
            case .trashed(let record):
                items.removeAll { $0.id == item.id }
                trashed.append(record)
                if demoItemIDs.contains(item.id) {
                    demoStatus = .trashed
                }
            case .missing, .movedOut:
                items.removeAll { $0.id == item.id }
            case .failed(let message):
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].startedAt = now
                    items[index].expiresAt = now.addingTimeInterval(300)
                    items[index].lastError = message
                }
                if firstFailure == nil {
                    firstFailure = (item.name, message)
                }
            }
        }

        if !trashed.isEmpty {
            history.insert(contentsOf: trashed, at: 0)
            trimHistory()
            if prefs.playSound && !automaticPanelsSuppressed {
                Sounds.playTrash()
            }
            showToast(.trashed(trashed))
        } else if let firstFailure {
            showToast(.failed(title: "Couldn’t move “\(firstFailure.name)” to the Trash", message: "\(firstFailure.message) Trying again in 5 minutes."))
        }
        persist()
        scheduleExpiryTimer()
    }

    // MARK: - List actions

    func setTimer(for itemID: UUID, to duration: ShelfDuration) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let start = clock(Date())
        items[index].startedAt = start
        items[index].expiresAt = start.addingTimeInterval(duration.seconds)
        items[index].lastError = nil
        persist()
        scheduleExpiryTimer()
    }

    func keepForever(_ itemID: UUID) {
        items.removeAll { $0.id == itemID }
        persist()
        scheduleExpiryTimer()
    }

    func trashNow(_ itemID: UUID) {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        switch engine.expire(item) {
        case .trashed(let record):
            items.removeAll { $0.id == itemID }
            history.insert(record, at: 0)
            trimHistory()
            if prefs.playSound && !automaticPanelsSuppressed {
                Sounds.playTrash()
            }
        case .missing, .movedOut:
            items.removeAll { $0.id == itemID }
        case .failed(let message):
            if let index = items.firstIndex(where: { $0.id == itemID }) {
                items[index].lastError = message
            }
        }
        persist()
        scheduleExpiryTimer()
    }

    func putBack(_ records: [TrashRecord]) {
        var restored: [URL] = []
        for record in records {
            guard let url = try? ExpiryEngine.putBack(record) else { continue }
            // Mark it as seen before the watcher's next scan so it isn't asked about again.
            if let fileID = FolderScanner.fileID(of: url) {
                watcher?.markKnown(fileID)
                screenshotWatcher?.markKnown(fileID)
            }
            if let index = history.firstIndex(where: { $0.id == record.id }) {
                history[index].restoredAt = Date()
            }
            restored.append(url)
        }
        persist()

        if let first = restored.first {
            showToast(.restored(name: first.lastPathComponent, count: restored.count))
        } else if !records.isEmpty {
            showToast(.failed(title: "Couldn’t put it back", message: PutBackError.noLongerInTrash.localizedDescription))
        }
    }

    func reveal(_ item: TrackedItem) {
        if case .inFolder(let url) = ItemLocator.locate(item) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func open(_ item: TrackedItem) {
        if case .inFolder(let url) = ItemLocator.locate(item) {
            NSWorkspace.shared.open(url)
        }
    }

    func revealInTrash(_ record: TrashRecord) {
        guard let path = record.trashedPath, FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openWatchedFolder() {
        NSWorkspace.shared.open(prefs.watchedFolder)
    }

    func clearHistory() {
        history.removeAll()
        persist()
    }

    /// Freezes every timer (and stops asking about downloads) until resumed.
    func togglePause() {
        if let pausedAt {
            let shift = Date().timeIntervalSince(pausedAt)
            for index in items.indices {
                items[index].startedAt.addTimeInterval(shift)
                items[index].expiresAt.addTimeInterval(shift)
            }
            self.pausedAt = nil
        } else {
            pausedAt = Date()
        }
        persist()
        restartPromptTimer()
        scheduleExpiryTimer()
        expireDue()
    }

    // MARK: - Onboarding sample

    func dropSampleFile() {
        let folder = prefs.watchedFolder
        let url = ExpiryEngine.uniqueDestination(for: folder.appendingPathComponent("Pumpkin Sample.txt"))
        let text = """
        Hi! I’m a sample file from Pumpkin.

        Pick a time in the menu bar and I’ll move myself to the Trash when it’s up.
        Changed your mind? “Put Back” brings me right back.

        """
        do {
            try Data(text.utf8).write(to: url)
            if let fileID = FolderScanner.fileID(of: url) {
                demoFileIDs.insert(fileID)
            }
            demoStatus = .waitingForAnswer
            watcher?.scheduleScan(after: 0.05)
        } catch {
            demoStatus = .failed(error.localizedDescription)
        }
    }

    // MARK: - Persistence

    func saveNow() {
        if isWatching {
            lastSeenAt = Date()
        }
        persist()
    }

    private var persistedState: PersistedState {
        PersistedState(items: items, history: history, lastSeenAt: lastSeenAt, pausedAt: pausedAt,
            recordings: recordings, pendingGroups: prompts.filter { !$0.isDemo }.map {
                PendingFileGroup(id: $0.id, snapshots: $0.items.map(\.snapshot), sources: $0.items.map(\.source), kind: $0.kind.rawValue, selection: $0.selection, arrivedAt: $0.arrivedAt, touched: $0.touched)
            })
    }

    @discardableResult
    func beginRecording(url: URL, screen: String, audio: String, format: String) throws -> UUID {
        let entry = RecordingEntry(path: url.path, screen: screen, audio: audio, format: format)
        recordings.insert(entry, at: 0)
        do { try store.save(persistedState) }
        catch { recordings.removeAll { $0.id == entry.id }; throw error }
        return entry.id
    }

    func finishRecording(_ id: UUID, duration: Double, error: String? = nil) {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[index].duration = duration.isFinite ? max(0, duration) : 0
        recordings[index].status = error == nil ? .finished : .failed
        recordings[index].error = error
        let url = recordings[index].url
        if let snapshot = FolderScanner.snapshot(of: url) {
            recordings[index].size = snapshot.size
            recordings[index].fileID = snapshot.fileID
            var info = stat(); if lstat(url.path, &info) == 0 { recordings[index].volumeID = UInt64(info.st_dev) }
            recordings[index].bookmark = ItemLocator.makeBookmark(for: url)
        }
        persist()
    }

    func importRecording(_ url: URL, duration: Double = 0) throws {
        guard url.pathExtension.lowercased() == "mp4", !url.lastPathComponent.lowercased().hasSuffix(".partial.mp4"), FolderScanner.snapshot(of: url) != nil else { return }
        guard !recordings.contains(where: { $0.protects(url) }) else { return }
        let id = try beginRecording(url: url, screen: "Imported", audio: "Unknown", format: "MP4")
        finishRecording(id, duration: duration)
        let front = prompts.first?.id
        if let imported = recordings.first(where: { $0.id == id }) {
            for index in prompts.indices { prompts[index].items.removeAll { imported.matches($0.url) } }
        }
        prompts.removeAll { $0.items.isEmpty }
        if prompts.first?.id != front { restartPromptTimer() }
        persist()
    }

    func removeRecording(_ id: UUID) {
        recordings.removeAll { $0.id == id }
        persist()
    }

    func scheduleRecording(_ id: UUID, duration: ShelfDuration) {
        guard let entry = recordings.first(where: { $0.id == id }), entry.status == .finished,
              recordingTrash(entry) == nil,
              let url = entry.locatedURL, !ItemLocator.isInTrash(url), let snapshot = FolderScanner.snapshot(of: url) else { return }
        if let tracked = items.first(where: { $0.fileID == snapshot.fileID && $0.folderPath == url.deletingLastPathComponent().path }) {
            setTimer(for: tracked.id, to: duration); return
        }
        let now = clock(Date())
        items.append(TrackedItem(name: url.lastPathComponent, path: url.path, folderPath: url.deletingLastPathComponent().path,
            fileID: snapshot.fileID, bookmark: ItemLocator.makeBookmark(for: url), size: snapshot.size, isFolder: false,
            source: "Pumpkin Recording", startedAt: now, expiresAt: now.addingTimeInterval(duration.seconds), volumeID: ItemLocator.volumeID(of: url), kind: ItemKind.recording.rawValue))
        persist(); scheduleExpiryTimer()
    }

    func recordingTrash(_ entry: RecordingEntry) -> TrashRecord? {
        history.first { record in
            guard record.canPutBack, let path = record.trashedPath else { return false }
            return entry.matches(URL(fileURLWithPath: path))
        }
    }

    func setDownloadsEnabled(_ enabled: Bool) {
        prefs.watchDownloads = enabled
        if enabled { retryWatching() }
        else { watcher?.stop(); watcher = nil; isWatching = false; folderProblem = nil; retryTimer?.invalidate(); startScreenshotWatching() }
    }

    private func persist() {
        lastPersistedAt = Date()
        do {
            try store.save(persistedState)
        } catch {
            NSLog("Pumpkin: couldn’t save state: \(error.localizedDescription)")
        }
    }

    private func trimHistory() {
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        history.removeAll { $0.trashedAt < cutoff }
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
    }
    deinit {
        for timer in [screenshotLocationTimer, expiryTimer, promptTimer, toastTimer, confirmationTimer, retryTimer] { timer?.invalidate() }
        for token in notificationTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
        watcher?.stop(); screenshotWatcher?.stop()
    }
}
