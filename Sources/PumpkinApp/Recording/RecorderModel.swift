import AppKit
import AVFoundation
import Observation
import ScreenCaptureKit
import PumpkinCore

struct DisplayChoice: Identifiable {
    var id: CGDirectDisplayID
    var name: String
    var width: Int
    var height: Int
    var isMain: Bool
}

struct RecordingOptions: Codable, Equatable {
    var displayID: UInt32?
    var deviceUID: String?
    var withAudio = false
    var left = 1
    var right = 2
    var channelsConfirmed = false
    var resolution = 1080
    var fps = 30
    var quality = 1
    var hevc = false
    var cursor = true
    var countdown = true
    var folderPath = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!.appendingPathComponent("Pumpkin").path
    var folder: URL { URL(fileURLWithPath: folderPath, isDirectory: true) }
    func dimensions(width: Int, height: Int) -> (Int, Int) {
        let scale = resolution == 0 ? 1 : min(1, Double(resolution) / Double(max(1, height)))
        return (max(2, Int(Double(width) * scale) / 2 * 2), max(2, Int(Double(height) * scale) / 2 * 2))
    }
}

@MainActor @Observable
final class RecorderModel {
    enum Phase: String { case idle, preparing, countdown, recording, finalizing, monitoring }
    private(set) var phase: Phase = .idle
    private(set) var displays: [DisplayChoice] = []
    private(set) var devices: [InputDevice] = []
    private(set) var seconds = 0
    private(set) var countdownValue = 3
    private(set) var bytes: Int64 = 0
    private(set) var levelL: Float = 0
    private(set) var levelR: Float = 0
    private(set) var drops = 0
    private(set) var warning: String?
    private(set) var error: String?
    private(set) var resultID: UUID?
    private(set) var screenAllowed = CGPreflightScreenCaptureAccess()
    private(set) var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    var options: RecordingOptions { didSet { if let data = try? JSONEncoder().encode(options) { defaults.set(data, forKey: "v2.recordingOptions") } } }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let files: AppModel
    @ObservationIgnored private let deviceProvider: () -> [InputDevice]
    @ObservationIgnored private let displayProvider: () -> [DisplayChoice]
    @ObservationIgnored private var session: RecordingSession?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var startDate: Date?
    @ObservationIgnored private var lastSignal = Date()
    @ObservationIgnored private var entryID: UUID?
    @ObservationIgnored private var pendingError: String?
    @ObservationIgnored private var observerTokens: [NSObjectProtocol] = []
    @ObservationIgnored var onStateChange: () -> Void = {}
    @ObservationIgnored private var revision = 0
    var busy: Bool { phase != .idle && phase != .monitoring }
    var locked: Bool { phase != .idle }
    var selectedDisplay: DisplayChoice? { displays.first { $0.id == options.displayID } }
    var selectedDevice: InputDevice? { devices.first { $0.uid == options.deviceUID } }
    var inputValid: Bool {
        guard options.withAudio else { return true }
        guard let device = selectedDevice else { return false }
        return options.channelsConfirmed && options.left >= 1 && options.right >= 1 && options.left <= device.channels && options.right <= device.channels
    }
    var ready: Bool { selectedDisplay != nil && inputValid }
    var dimensions: (Int, Int) { options.dimensions(width: selectedDisplay?.width ?? 1920, height: selectedDisplay?.height ?? 1080) }
    var bitrate: Int { VideoPreset.all[max(0, min(2, options.quality))].bitrate(width: dimensions.0, height: dimensions.1, fps: options.fps) }
    var estimatedMB: Int { (bitrate + (options.withAudio ? 256_000 : 0)) * 60 / 8 / 1_000_000 }
    var elapsed: String { String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
    var audioDescription: String { options.withAudio ? "\(selectedDevice?.name ?? "?") · Input \(options.left) → L · Input \(options.right) → R" : "Without audio" }
    var formatDescription: String { "\(dimensions.0) × \(dimensions.1) · \(options.fps) fps · \(options.hevc ? "HEVC" : "H.264")" }

    init(files: AppModel, defaults: UserDefaults = .standard, deviceProvider: @escaping () -> [InputDevice] = Devices.inputs, displayProvider: @escaping () -> [DisplayChoice] = RecorderModel.systemDisplays) {
        self.files = files; self.defaults = defaults; self.deviceProvider = deviceProvider; self.displayProvider = displayProvider
        options = defaults.data(forKey: "v2.recordingOptions").flatMap { try? JSONDecoder().decode(RecordingOptions.self, from: $0) } ?? RecordingOptions()
        options.fps = options.fps == 60 ? 60 : 30
        options.quality = max(0, min(2, options.quality))
        if ![0, 1080, 1440, 2160].contains(options.resolution) { options.resolution = 1080 }
        if options.left < 1 || options.right < 1 { options.channelsConfirmed = false }
        refreshDevices()
        if options.displayID == nil { options.displayID = displays.first?.id }
        let notifications = NSWorkspace.shared.notificationCenter
        observerTokens.append(notifications.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.interrupt("Mac is going to sleep.") }
        })
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification] {
            observerTokens.append(notifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.interrupt("The screen or user session is inactive.") }
            })
        }
        observerTokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshDevices()
                if self.phase == .recording && self.selectedDisplay == nil { self.interrupt("Selected display was disconnected.") }
            }
        })
    }
    func refreshPermissions() { screenAllowed = CGPreflightScreenCaptureAccess(); microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio) }
    static func systemDisplays() -> [DisplayChoice] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = number.uint32Value, mode = CGDisplayCopyDisplayMode(id)
            return DisplayChoice(id: id, name: screen.localizedName, width: mode?.pixelWidth ?? Int(screen.frame.width * screen.backingScaleFactor), height: mode?.pixelHeight ?? Int(screen.frame.height * screen.backingScaleFactor), isMain: id == CGMainDisplayID())
        }
    }
    func refreshDevices() { displays = displayProvider(); devices = deviceProvider(); refreshPermissions() }
    func chooseDevice(_ uid: String?) { options.deviceUID = uid; options.channelsConfirmed = false; options.left = 1; options.right = 1 }
    func chooseFolder() {
        guard phase == .idle else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = options.folder
        if panel.runModal() == .OK, let url = panel.url { options.folderPath = url.path }
    }
    func importSettings() {
        guard phase == .idle, let old = UserDefaults.standard.persistentDomain(forName: "local.michael.LoopbackRecorder") else { return }
        // Explicit user action only; never assume another bundle's permissions.
        if let uid = old["device"] as? String {
            options.deviceUID = uid; options.withAudio = true
            if let left = old["left-" + uid] as? Int { options.left = left }
            if let right = old["right-" + uid] as? Int { options.right = right }
        }
        if let display = old["display"] as? UInt32 { options.displayID = display }
        if let folder = old["folder"] as? String { options.folderPath = folder }
        if let index = old["resolution"] as? Int, (0...3).contains(index) { options.resolution = [1080, 1440, 2160, 0][index] }
        if let index = old["fps"] as? Int, (0...1).contains(index) { options.fps = [30, 60][index] }
        if let quality = old["quality"] as? Int { options.quality = max(0, min(2, quality)) }
        if let codec = old["codec"] as? Int { options.hevc = codec == 1 }
        options.channelsConfirmed = false
        refreshDevices()
    }
    func clearResult() { resultID = nil; error = nil; warning = nil }
    func toggle() {
        switch phase {
        case .idle: start()
        case .monitoring: Task { await stopMonitor(); start() }
        case .preparing, .countdown: cancel()
        case .recording: Task { await stop() }
        case .finalizing: break
        }
    }
    func cancel() {
        guard phase == .preparing || phase == .countdown else { return }
        operation?.cancel()
        // The operation unwinds before idle, so a second start cannot share its resources.
    }
    private func setPhase(_ value: Phase) { phase = value; onStateChange() }
    private func microphonePermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard allowed else { throw RecorderError(message: "Microphone access is required for the selected audio input.") }
        default: throw RecorderError(message: "Allow Microphone access for Pumpkin in System Settings.")
        }
        refreshPermissions()
    }
    private func configure(_ value: RecordingSession) {
        revision += 1; let expected = revision
        value.onMeter = { [weak self] l, r, dropped in
            DispatchQueue.main.async {
                guard let self, self.revision == expected else { return }
                self.levelL = l; self.levelR = r
                if max(l, r) > 0.0005 {
                    self.lastSignal = Date()
                    if self.warning?.hasPrefix("Silence") == true { self.warning = nil }
                }
                if dropped > 0 { self.warning = "Audio input packets were dropped: \(dropped)." }
                else if max(l, r) >= 0.99 { self.warning = "Audio clipping. Lower the input level." }
                else if self.warning?.hasPrefix("Audio clipping") == true { self.warning = nil }
            }
        }
        value.onStats = { [weak self] _, video, audio in DispatchQueue.main.async {
            guard let self, self.revision == expected else { return }; self.drops = video + audio
        } }
        value.onFailure = { [weak self] error in DispatchQueue.main.async {
            guard let self, self.revision == expected else { return }; self.interrupt(error.localizedDescription)
        } }
    }
    private func startTicker() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    private func tick() {
        if let startDate { seconds = Int(Date().timeIntervalSince(startDate)) }
        if let id = entryID, let entry = files.recordings.first(where: { $0.id == id }) {
            bytes = Int64((try? entry.partialURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        if options.withAudio && (phase == .recording || phase == .monitoring), Date().timeIntervalSince(lastSignal) > 3 {
            warning = "Silence on selected inputs. Check the source and L/R channels."
        }
        if drops > 0 { warning = "Dropped video/audio packets: \(drops)." }
        if phase == .recording {
            if !CGPreflightScreenCaptureAccess() { interrupt("Screen Recording permission was revoked."); return }
            if options.displayID.map({ CGDisplayIsActive($0) == 0 }) ?? true { interrupt("Selected display was disconnected.") }
        }
    }
    func toggleMonitor() {
        if phase == .monitoring { Task { await stopMonitor() }; return }
        guard phase == .idle, options.withAudio, inputValid, let device = selectedDevice else { return }
        setPhase(.preparing); error = nil; warning = nil
        operation = Task {
            do {
                try await microphonePermission(); try Task.checkCancellation()
                let value = RecordingSession(); configure(value); session = value
                try value.monitor(device: device, left: options.left, right: options.right)
                lastSignal = Date(); setPhase(.monitoring); startTicker()
            } catch {
                if let current = session { _ = await current.stop(); session = nil }
                if !(error is CancellationError) { self.error = error.localizedDescription }
                refreshPermissions(); setPhase(.idle)
            }
        }
    }
    func stopMonitor() async {
        guard phase == .monitoring else { return }
        setPhase(.finalizing); timer?.invalidate(); timer = nil
        if let current = session { _ = await current.stop() }; session = nil; levelL = 0; levelR = 0
        setPhase(.idle)
    }
    func start() {
        guard phase == .idle else { return }
        refreshDevices()
        guard ready else { error = "Select a connected display and confirm valid L/R channels."; return }
        error = nil; warning = nil; resultID = nil; seconds = 0; bytes = 0; drops = 0; pendingError = nil
        let config = options
        setPhase(.preparing)
        operation = Task {
            do {
                if config.withAudio { try await microphonePermission() }
                try Task.checkCancellation()
                guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                    throw RecorderError(message: "Allow Screen Recording for Pumpkin in System Settings, then try again.")
                }
                refreshPermissions(); try Task.checkCancellation()
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                try Task.checkCancellation()
                guard let display = content.displays.first(where: { $0.displayID == config.displayID }) else { throw RecorderError(message: "Selected display is unavailable.") }
                let device = config.withAudio ? Devices.inputs().first { $0.uid == config.deviceUID } : nil
                if config.withAudio {
                    guard let device, Devices.alive(device.id), config.channelsConfirmed, config.left <= device.channels, config.right <= device.channels else { throw RecorderError(message: "Selected audio input or channels are unavailable.") }
                }
                try FileManager.default.createDirectory(at: config.folder, withIntermediateDirectories: true)
                let disk = try config.folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                if let free = disk.volumeAvailableCapacityForImportantUsage, free < 100_000_000 { throw RecorderError(message: "Not enough free space to begin recording (less than 100 MB).") }
                if config.countdown {
                    setPhase(.countdown)
                    for second in (1...3).reversed() { countdownValue = second; try await Task.sleep(nanoseconds: 1_000_000_000) }
                }
                try Task.checkCancellation()
                let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let url = config.folder.appendingPathComponent("Recording_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(8)).mp4")
                let id = try files.beginRecording(url: url, screen: selectedDisplay?.name ?? "Display", audio: audioDescription, format: formatDescription)
                entryID = id
                let value = RecordingSession(); session = value; configure(value)
                let size = config.dimensions(width: selectedDisplay?.width ?? display.width, height: selectedDisplay?.height ?? display.height)
                let bitrate = VideoPreset.all[max(0, min(2, config.quality))].bitrate(width: size.0, height: size.1, fps: config.fps)
                try await value.start(display: display, device: device, left: config.left, right: config.right, width: size.0, height: size.1, fps: config.fps, bitrate: bitrate, hevc: config.hevc, cursor: config.cursor, url: url, content: content)
                try Task.checkCancellation()
                startDate = Date(); lastSignal = Date(); setPhase(.recording); startTicker()
            } catch {
                if let current = session { _ = await current.stop(); session = nil }
                if let id = entryID { files.finishRecording(id, duration: 0, error: error.localizedDescription); entryID = nil }
                if !(error is CancellationError) { self.error = error.localizedDescription }
                refreshPermissions(); setPhase(.idle)
            }
        }
    }
    private func interrupt(_ message: String) {
        switch phase {
        case .recording: pendingError = message; Task { await stop() }
        case .monitoring: error = message; Task { await stopMonitor() }
        case .preparing, .countdown: pendingError = message; operation?.cancel(); error = message
        case .idle, .finalizing: break
        }
    }
    func stop() async {
        guard phase == .recording, let current = session else { return }
        setPhase(.finalizing); timer?.invalidate(); timer = nil
        let elapsed = startDate.map { Date().timeIntervalSince($0) } ?? 0
        let (result, _) = await current.stop(); session = nil; startDate = nil; levelL = 0; levelR = 0
        if let id = entryID {
            if let result, case .success(let url) = result {
                let duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? elapsed
                files.finishRecording(id, duration: duration); resultID = id; warning = pendingError ?? warning
            } else {
                let message: String
                if let result, case .failure(let error) = result { message = error.localizedDescription } else { message = "No video was created." }
                let explanation = [pendingError, message].compactMap { $0 }.joined(separator: "\n")
                files.finishRecording(id, duration: elapsed, error: explanation); error = explanation
            }
        }
        entryID = nil; setPhase(.idle)
    }
    static func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") { NSWorkspace.shared.open(url) }
    }

    func importVideo(_ url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let videos = try await asset.loadTracks(withMediaType: .video)
        let duration = try await asset.load(.duration).seconds
        guard !videos.isEmpty, duration.isFinite, duration > 0 else { throw RecorderError(message: "The selected MP4 has no playable video.") }
        try files.importRecording(url, duration: duration)
    }
}
