import AppKit
import QuickLookThumbnailing
import Observation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum Brand {
    static let tint = Color(red: 0.95, green: 0.38, blue: 0.20)
    static let gradientTop = Color(red: 1.00, green: 0.65, blue: 0.29)
    static let gradientBottom = Color(red: 0.93, green: 0.30, blue: 0.22)
}

/// Runs `apply` now and again after every change to any observable value it reads.
@MainActor
func observeContinuously(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking {
        apply()
    } onChange: {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                observeContinuously(apply)
            }
        }
    }
}

@MainActor
enum FileIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(path: String, isFolder: Bool) -> NSImage {
        if let cached = cache[path] {
            return cached
        }
        if FileManager.default.fileExists(atPath: path) {
            let image = NSWorkspace.shared.icon(forFile: path)
            cache[path] = image
            return image
        }
        let ext = (path as NSString).pathExtension
        let type = isFolder ? UTType.folder : (UTType(filenameExtension: ext) ?? .data)
        return NSWorkspace.shared.icon(for: type)
    }
}

enum Sounds {
    static func playTrash() {
        let finderSound = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/finder/move to trash.aif"
        (NSSound(contentsOfFile: finderSound, byReference: true) ?? NSSound(named: "Pop"))?.play()
    }
}

enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isEnabled: Bool { status == .enabled }
    static var needsApproval: Bool { status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if status == .enabled || status == .requiresApproval {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum FolderAccess {
    /// Reads the folder, which makes macOS show its privacy prompt the first time.
    /// The call blocks while that prompt is up, so it runs off the main thread.
    static func check(_ url: URL) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
        }.value
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum UnansweredPolicy: String, CaseIterable, Identifiable {
    case keep
    case useDefault

    var id: String { rawValue }
}

@MainActor @Observable
final class Preferences {
    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let defaultDuration = "defaultDuration"
        static let unansweredPolicy = "unansweredPolicy"
        static let promptTimeout = "promptTimeout"
        static let showCountdown = "showCountdown"
        static let playSound = "playSound"
        static let askAboutFolders = "askAboutFolders"
        static let watchScreenshots = "watchScreenshots"
        static let customFolderPath = "watchedFolderPath"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    /// Seconds preselected on the slider when a download arrives.
    var defaultDuration: TimeInterval {
        didSet { defaults.set(defaultDuration, forKey: Key.defaultDuration) }
    }

    var unansweredPolicy: UnansweredPolicy {
        didSet { defaults.set(unansweredPolicy.rawValue, forKey: Key.unansweredPolicy) }
    }

    /// Seconds before an unanswered question tucks itself away; 0 means never.
    var promptTimeout: TimeInterval {
        didSet { defaults.set(promptTimeout, forKey: Key.promptTimeout) }
    }

    var showCountdown: Bool {
        didSet { defaults.set(showCountdown, forKey: Key.showCountdown) }
    }

    var playSound: Bool {
        didSet { defaults.set(playSound, forKey: Key.playSound) }
    }

    var askAboutFolders: Bool {
        didSet { defaults.set(askAboutFolders, forKey: Key.askAboutFolders) }
    }

    /// Also ask about new screenshots, wherever macOS saves them.
    var watchScreenshots: Bool {
        didSet { defaults.set(watchScreenshots, forKey: Key.watchScreenshots) }
    }

    var customFolderPath: String? {
        didSet { defaults.set(customFolderPath, forKey: Key.customFolderPath) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Import local settings from the previous name once, without overwriting
        // preferences already saved by Pumpkin or isolated QA suites.
        if defaults === UserDefaults.standard {
            Self.migrateLegacySettings(
                defaults: defaults,
                domain: "app.pumpkin.Pumpkin",
                previous: defaults.persistentDomain(forName: "app.shelflife.ShelfLife")
            )
        }
        defaults.register(defaults: [
            Key.defaultDuration: 86_400.0,
            Key.unansweredPolicy: UnansweredPolicy.keep.rawValue,
            Key.promptTimeout: 30.0,
            Key.showCountdown: true,
            Key.playSound: true,
            Key.askAboutFolders: true,
            Key.watchScreenshots: true,
            Key.hasCompletedOnboarding: false,
        ])
        defaultDuration = defaults.double(forKey: Key.defaultDuration)
        unansweredPolicy = UnansweredPolicy(rawValue: defaults.string(forKey: Key.unansweredPolicy) ?? "") ?? .keep
        promptTimeout = defaults.double(forKey: Key.promptTimeout)
        showCountdown = defaults.bool(forKey: Key.showCountdown)
        playSound = defaults.bool(forKey: Key.playSound)
        askAboutFolders = defaults.bool(forKey: Key.askAboutFolders)
        watchScreenshots = defaults.bool(forKey: Key.watchScreenshots)
        customFolderPath = defaults.string(forKey: Key.customFolderPath)
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
    }

    static var downloadsFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    var watchedFolder: URL {
        if let customFolderPath, !customFolderPath.isEmpty {
            return URL(fileURLWithPath: customFolderPath, isDirectory: true)
        }
        return Self.downloadsFolder
    }

    var isUsingDownloads: Bool { customFolderPath?.isEmpty ?? true }

    static func migrateLegacySettings(defaults: UserDefaults, domain: String, previous: [String: Any]?) {
        var current = defaults.persistentDomain(forName: domain) ?? [:]
        guard current["pumpkinSettingsMigrated"] as? Bool != true else { return }
        if let previous {
            for (key, value) in previous where current[key] == nil {
                current[key] = value
            }
        }
        current["pumpkinSettingsMigrated"] = true
        defaults.setPersistentDomain(current, forName: domain)
    }

    /// "Downloads", localised the way Finder shows it.
    var watchedFolderName: String {
        FileManager.default.displayName(atPath: watchedFolder.path)
    }
}

/// Finder-style previews for images, PDFs and videos, loaded in the background.
@MainActor @Observable
final class Thumbnails {
    static let shared = Thumbnails()

    private(set) var images: [String: NSImage] = [:]
    @ObservationIgnored private var requested: Set<String> = []

    /// The preview if it's ready; otherwise starts loading it and returns nil.
    func thumbnail(for path: String) -> NSImage? {
        if let image = images[path] {
            return image
        }
        load(path)
        return nil
    }

    private func load(_ path: String) {
        guard !requested.contains(path), FileManager.default.fileExists(atPath: path) else { return }
        if requested.count > 300 {
            requested.removeAll()
            images.removeAll()
        }
        requested.insert(path)
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: CGSize(width: 96, height: 96),
            scale: 2,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let image = representation?.nsImage else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { Thumbnails.shared.images[path] = image }
            }
        }
    }
}
