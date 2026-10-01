import AppKit
import Carbon
import Observation

struct GlobalShortcut: Codable, Equatable, Hashable {
    var key: UInt32
    var modifiers: UInt32
    var character: String? = nil
    static let clipboard = GlobalShortcut(key: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey | cmdKey))
    static let recording = GlobalShortcut(key: UInt32(kVK_ANSI_R), modifiers: UInt32(controlKey | shiftKey))
    var label: String {
        let letters: [UInt32: String] = [UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_R): "R"]
        return (modifiers & UInt32(controlKey) != 0 ? "⌃" : "") + (modifiers & UInt32(optionKey) != 0 ? "⌥" : "") + (modifiers & UInt32(shiftKey) != 0 ? "⇧" : "") + (modifiers & UInt32(cmdKey) != 0 ? "⌘" : "") + (character ?? letters[key] ?? "Key \(key)")
    }
}

@MainActor @Observable
final class UnifiedPreferences {
    @ObservationIgnored let defaults: UserDefaults
    var clipboardEnabled: Bool { didSet { defaults.set(clipboardEnabled, forKey: "v2.clipboardEnabled") } }
    var visibleClips: Int { didSet { defaults.set(max(3, min(9, visibleClips)), forKey: "v2.visibleClips") } }
    var recordingEnabled: Bool { didSet { defaults.set(recordingEnabled, forKey: "v2.recordingEnabled") } }
    var theme: String { didSet { defaults.set(theme, forKey: "v2.theme") } }
    var language: String { didSet { defaults.set(language, forKey: "v2.language") } }
    var completedIntro: Bool { didSet { defaults.set(completedIntro, forKey: "v2.completedIntro") } }
    var clipboardShortcut: GlobalShortcut { didSet { save(clipboardShortcut, "v2.clipboardShortcut") } }
    var recordingShortcut: GlobalShortcut { didSet { save(recordingShortcut, "v2.recordingShortcut") } }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["v2.clipboardEnabled": false, "v2.visibleClips": 5, "v2.recordingEnabled": true, "v2.theme": "system", "v2.language": "ru", "v2.completedIntro": false])
        clipboardEnabled = defaults.bool(forKey: "v2.clipboardEnabled")
        visibleClips = max(3, min(9, defaults.integer(forKey: "v2.visibleClips")))
        recordingEnabled = defaults.bool(forKey: "v2.recordingEnabled")
        theme = defaults.string(forKey: "v2.theme") ?? "system"
        language = defaults.string(forKey: "v2.language") ?? "ru"
        completedIntro = defaults.bool(forKey: "v2.completedIntro")
        clipboardShortcut = defaults.data(forKey: "v2.clipboardShortcut").flatMap { try? JSONDecoder().decode(GlobalShortcut.self, from: $0) } ?? .clipboard
        recordingShortcut = defaults.data(forKey: "v2.recordingShortcut").flatMap { try? JSONDecoder().decode(GlobalShortcut.self, from: $0) } ?? .recording
    }
    private func save<T: Encodable>(_ value: T, _ key: String) { if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) } }
    func text(_ ru: String, _ en: String) -> String { language == "en" ? en : ru }
    var appearance: NSAppearance? { theme == "dark" ? NSAppearance(named: .darkAqua) : theme == "light" ? NSAppearance(named: .aqua) : nil }
}
