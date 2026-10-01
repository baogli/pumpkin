import AppKit
import Observation

enum WorkspaceSection: String, CaseIterable { case recording, clipboard, cleanup, settings, access }

@MainActor @Observable
final class Workbench {
    let files: AppModel
    let prefs: UnifiedPreferences
    let clipboard: ClipboardHistory
    let recorder: RecorderModel
    var section: WorkspaceSection = .recording
    var intro: Bool
    var windowVisible = false { didSet { synchronizePanels() } }
    var clipboardVisible = false { didSet { synchronizePanels() } }
    var notice: String? { didSet { noticeIsError = false; noticeAction = nil } }
    var noticeIsError = false
    var noticeAction: WorkspaceSection?
    var shortcutError: String?
    var capturingShortcut: UInt32?
    @ObservationIgnored var showWindow: () -> Void = {}
    @ObservationIgnored var hideWindow: () -> Void = {}
    @ObservationIgnored var showQuickClipboard: () -> Void = {}
    @ObservationIgnored var hideQuickClipboard: () -> Void = {}
    @ObservationIgnored var updateShortcuts: () -> Void = {}
    @ObservationIgnored private var recorderWasBusy = false

    init(files: AppModel, prefs: UnifiedPreferences, clipboard: ClipboardHistory? = nil, recorder: RecorderModel? = nil) {
        self.files = files; self.prefs = prefs
        self.clipboard = clipboard ?? ClipboardHistory()
        self.recorder = recorder ?? RecorderModel(files: files, defaults: prefs.defaults)
        intro = !prefs.completedIntro
        self.recorder.onStateChange = { [weak self] in self?.recordingStateChanged() }
        self.clipboard.setEnabled(prefs.clipboardEnabled)
        files.automaticPanelsSuppressed = intro
    }
    func text(_ ru: String, _ en: String) -> String { prefs.text(ru, en) }
    func message(_ value: String) -> String {
        guard prefs.language != "en" else { return value }
        let messages: [String: String] = [
            "Select a connected display and confirm valid L/R channels.": "Выбери подключённый дисплей и подтверди пару L/R.",
            "Microphone access is required for the selected audio input.": "Для выбранного аудиовхода нужен доступ к микрофону.",
            "Allow Microphone access for Pumpkin in System Settings.": "Разреши Pumpkin доступ к микрофону в настройках macOS.",
            "Allow Screen Recording for Pumpkin in System Settings, then try again.": "Разреши Pumpkin запись экрана в настройках macOS, затем попробуй снова.",
            "Selected display is unavailable.": "Выбранный дисплей недоступен.",
            "Selected display was disconnected.": "Выбранный дисплей отключён.",
            "Selected audio input or channels are unavailable.": "Выбранное аудиоустройство или каналы недоступны.",
            "Not enough free space to begin recording (less than 100 MB).": "Недостаточно места для начала записи: свободно меньше 100 МБ.",
            "Silence on selected inputs. Check the source and L/R channels.": "На выбранных входах тишина. Проверь источник и пару L/R.",
            "Audio clipping. Lower the input level.": "Звук перегружен. Уменьши входной уровень.",
            "Screen Recording permission was revoked.": "Доступ к записи экрана отозван.",
            "Mac is going to sleep.": "Mac переходит в спящий режим.",
            "The screen or user session is inactive.": "Экран или пользовательская сессия неактивны.",
            "No video was created.": "Видео не создано.",
            "The selected MP4 has no playable video.": "В выбранном MP4 нет доступного видео.",
            "Recording was interrupted. A partial MP4 may not be playable.": "Запись прервана. Частичный MP4 может не открыться.",
            "Without audio": "Без звука", "Imported": "Импортирована", "Unknown": "Неизвестно"
        ]
        return value.components(separatedBy: "\n").map { line in
            if let translated = messages[line] { return translated }
            if line.hasPrefix("Audio input packets were dropped:") { return line.replacingOccurrences(of: "Audio input packets were dropped:", with: "Пропуски входных аудиопакетов:") }
            if line.hasPrefix("Dropped video/audio packets:") { return line.replacingOccurrences(of: "Dropped video/audio packets:", with: "Пропуски видео/аудио:") }
            if line.hasPrefix("Pumpkin can’t read your ") { return line.replacingOccurrences(of: "Pumpkin can’t read your ", with: "Нет доступа к папке ").replacingOccurrences(of: " folder.", with: ".") }
            if line.hasPrefix("Pumpkin can’t see screenshots on your ") { return line.replacingOccurrences(of: "Pumpkin can’t see screenshots on your ", with: "Нет доступа к скриншотам в папке ") }
            return line
        }.joined(separator: "\n")
    }
    func synchronizePanels() { files.automaticPanelsSuppressed = intro || recorder.busy || clipboardVisible || windowVisible }
    private func recordingStateChanged() {
        if recorder.busy && !recorderWasBusy { files.deferredTrashCount = 0 }
        if !recorder.busy && recorderWasBusy {
            let pending = files.prompts.reduce(0) { $0 + $1.items.count }, trashed = files.deferredTrashCount
            if pending > 0 || trashed > 0 {
                notice = text("Очистка: \(pending) ждут решения, \(trashed) перемещено в Корзину.", "Cleanup: \(pending) need a decision, \(trashed) moved to Trash.")
                noticeAction = .cleanup
            }
        }
        recorderWasBusy = recorder.busy; synchronizePanels()
    }
    func open(_ section: WorkspaceSection) { hideQuickClipboard(); files.isListOpen = false; self.section = section; showWindow() }
    func finishIntro(connectFolders: Bool = true) {
        intro = false; prefs.completedIntro = true; files.prefs.hasCompletedOnboarding = true
        clipboard.setEnabled(prefs.clipboardEnabled)
        if connectFolders { files.retryWatching() }
        synchronizePanels(); updateShortcuts()
    }
    func setClipboardEnabled(_ enabled: Bool) {
        if !enabled { hideQuickClipboard() }
        prefs.clipboardEnabled = enabled; clipboard.setEnabled(enabled); updateShortcuts()
    }
    func importClipboardSettings() {
        guard let previous = UserDefaults.standard.persistentDomain(forName: "dev.vee.Vee") else { notice = text("Сохранённые настройки Vee не найдены", "No Vee preferences found"); return }
        if let count = previous["visibleItemCount"] as? Int { prefs.visibleClips = max(3, min(9, count)) }
        if let key = previous["hotKeyKeyCode"] as? UInt32, let modifiers = previous["hotKeyModifiers"] as? UInt32 { prefs.clipboardShortcut = GlobalShortcut(key: key, modifiers: modifiers) }
        notice = text("Перенесены настройки Vee. История из памяти не переносится.", "Vee preferences imported. Its in-memory history is not transferred.")
        updateShortcuts()
    }
    func copy(_ entry: ClipboardEntry) { clipboard.copy(entry); noticeAction = nil; notice = text("Скопировано — вставь ⌘V", "Copied — paste with ⌘V") }
    func clearClipboard() {
        let alert = NSAlert(); alert.messageText = text("Очистить историю?", "Clear clipboard history?")
        alert.informativeText = text("Текст в системном буфере останется. История Pumpkin будет удалена из памяти.", "The system clipboard stays unchanged. Pumpkin's in-memory history will be cleared.")
        alert.addButton(withTitle: text("Очистить", "Clear")); alert.addButton(withTitle: text("Отмена", "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { hideQuickClipboard(); clipboard.clear() }
    }
    func requestRecording() {
        guard prefs.recordingEnabled else { open(.settings); return }
        if recorder.phase == .idle && !recorder.ready { open(.recording) }
        else { recorder.toggle(); if recorder.phase == .preparing { open(.recording) } }
    }
}
