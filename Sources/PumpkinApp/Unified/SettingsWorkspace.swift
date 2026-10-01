import AppKit
import AVFoundation
import Carbon
import SwiftUI
import PumpkinCore

struct UnifiedSettingsView: View {
    @Environment(Workbench.self) private var workbench
    @State private var login = LoginItem.isEnabled
    @State private var loginError: String?
    var body: some View {
        @Bindable var prefs = workbench.prefs
        @Bindable var filesPrefs = workbench.files.prefs
        return VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(title: workbench.text("Настройки", "Settings"), subtitle: workbench.text("Каждая функция работает независимо", "Each module works independently"))
            ScrollView {
                VStack(spacing: 14) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(workbench.text("Общие", "General")).font(.headline)
                            Toggle(workbench.text("Открывать Pumpkin при входе", "Open Pumpkin at login"), isOn: $login).onChange(of: login) { _, value in do { try LoginItem.setEnabled(value); loginError = LoginItem.needsApproval ? workbench.text("Подтверди Pumpkin в настройках Login Items.", "Approve Pumpkin in Login Items.") : nil } catch { loginError = error.localizedDescription } }
                            if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange); Button(workbench.text("Настройки входа", "Login Items settings")) { if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) } } }
                            Picker(workbench.text("Оформление", "Appearance"), selection: $prefs.theme) { Text(workbench.text("Системное", "System")).tag("system"); Text(workbench.text("Светлое", "Light")).tag("light"); Text(workbench.text("Тёмное", "Dark")).tag("dark") }.pickerStyle(.segmented)
                            Picker(workbench.text("Язык", "Language"), selection: $prefs.language) { Text("Русский").tag("ru"); Text("English").tag("en") }.pickerStyle(.segmented)
                            Button(workbench.text("Доступы macOS", "macOS permissions")) { workbench.section = .access }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(workbench.text("Буфер", "Clipboard")).font(.headline)
                            Toggle(workbench.text("Сохранять историю текста", "Capture text history"), isOn: Binding(get: { prefs.clipboardEnabled }, set: { workbench.setClipboardEnabled($0) }))
                            Text(workbench.text("Выключение очищает историю из памяти. Системный буфер не меняется.", "Disabling clears the in-memory history. The system clipboard stays unchanged.")).font(.caption).foregroundStyle(.secondary)
                            Stepper(workbench.text("В быстром окне: \(prefs.visibleClips)", "Quick popup: \(prefs.visibleClips) items"), value: $prefs.visibleClips, in: 3...9)
                            HStack { Text(workbench.text("Горячая клавиша", "Shortcut")); Spacer(); ShortcutField(value: $prefs.clipboardShortcut, workbench: workbench, id: 1).frame(width: 220, height: 30) }
                            Button(workbench.text("Импорт настроек Vee", "Import Vee preferences")) { workbench.importClipboardSettings() }
                            Button(workbench.text("Разрешить быструю вставку", "Allow automatic paste")) { ClipboardHistory.requestAccessibility() }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(workbench.text("Запись", "Recording")).font(.headline)
                            Toggle(workbench.text("Включить запись экрана", "Enable screen recording"), isOn: Binding(get: { prefs.recordingEnabled }, set: { prefs.recordingEnabled = $0; workbench.updateShortcuts() })).disabled(workbench.recorder.locked)
                            HStack { Text(workbench.text("Горячая клавиша", "Shortcut")); Spacer(); ShortcutField(value: $prefs.recordingShortcut, workbench: workbench, id: 2).frame(width: 220, height: 30).disabled(workbench.recorder.locked) }
                            Button(workbench.text("Импорт настроек Able Recorder", "Import Able Recorder settings")) { workbench.recorder.importSettings(); workbench.notice = workbench.text("Проверь экран, устройство и пару L/R перед записью.", "Check the display, audio input and L/R pair before recording.") }.disabled(workbench.recorder.locked)
                            Text(workbench.text("При переходе закрой Vee и Able Recorder и отключи их автозапуск, чтобы не было конфликтов клавиш.", "When switching, close Vee and Able Recorder and disable their login items to avoid shortcut conflicts.")).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let error = workbench.shortcutError { Text(error).foregroundStyle(.red).font(.callout).frame(maxWidth: .infinity, alignment: .leading); Button(workbench.text("Проверить сочетания снова", "Retry shortcut registration")) { workbench.updateShortcuts() } }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(workbench.text("Очистка", "Cleanup")).font(.headline)
                            Toggle(workbench.text("Наблюдать загрузки", "Watch downloads"), isOn: Binding(get: { filesPrefs.watchDownloads }, set: { workbench.files.setDownloadsEnabled($0) }))
                            HStack { Text(filesPrefs.watchedFolderName).lineLimit(1); Spacer(); Button(workbench.text("Выбрать папку…", "Choose folder…")) { chooseFolder() }; if !filesPrefs.isUsingDownloads { Button("Downloads") { workbench.files.changeWatchedFolder(to: nil) } } }
                            Toggle(workbench.text("Наблюдать скриншоты macOS", "Watch macOS screenshots"), isOn: Binding(get: { filesPrefs.watchScreenshots }, set: { workbench.files.setWatchScreenshots($0) }))
                            Text(workbench.text("Отключение источника прекращает новые вопросы. Подтверждённые таймеры продолжают работать.", "Disabling a source stops new prompts. Existing confirmed timers continue.")).font(.caption).foregroundStyle(.secondary)
                            Picker(workbench.text("Предвыбранный срок", "Preselected expiry"), selection: $filesPrefs.defaultDuration) { ForEach(ShelfDuration.standardStops) { Text(durationLabel($0, workbench: workbench)).tag($0.seconds) } }
                            Picker(workbench.text("Без ответа", "Unanswered prompts"), selection: $filesPrefs.unansweredPolicy) { Text(workbench.text("Оставить файл", "Keep the file")).tag(UnansweredPolicy.keep); Text(workbench.text("Автоматически назначить срок", "Apply expiry automatically")).tag(UnansweredPolicy.useDefault) }
                            if filesPrefs.unansweredPolicy == .useDefault { Text(workbench.text("Даже без нажатия «Готово» файл получит срок и затем уйдёт в Корзину.", "Without pressing Done, the file receives an expiry and later moves to the Trash.")).font(.caption).foregroundStyle(.orange) }
                            Picker(workbench.text("Скрыть вопрос через", "Prompt timeout"), selection: $filesPrefs.promptTimeout) { Text("15 s").tag(15.0); Text("30 s").tag(30.0); Text("60 s").tag(60.0); Text(workbench.text("Никогда", "Never")).tag(0.0) }
                            Toggle(workbench.text("Время до очистки в строке меню", "Show next expiry in menu bar"), isOn: $filesPrefs.showCountdown)
                            Toggle(workbench.text("Звук при перемещении в Корзину", "Trash sound"), isOn: $filesPrefs.playSound)
                            Toggle(workbench.text("Спрашивать о новых папках", "Ask about new folders"), isOn: $filesPrefs.askAboutFolders)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text(workbench.text("Pumpkin 2.0 · Бесплатно · MIT · Без аккаунта, сети и телеметрии", "Pumpkin 2.0 · Free · MIT · No account, network or telemetry")).font(.caption).foregroundStyle(.secondary)
                    Link("Open source on GitHub", destination: URL(string: "https://github.com/baogli/pumpkin")!)
                }.padding(.bottom, 10)
            }
        }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false; panel.directoryURL = workbench.files.prefs.watchedFolder
        if panel.runModal() == .OK, let url = panel.url { workbench.files.changeWatchedFolder(to: url) }
    }
}

struct AccessWorkspace: View {
    @Environment(Workbench.self) private var workbench
    @State private var refreshed = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(title: workbench.text("Доступы", "Permissions"), subtitle: workbench.text("Разрешения только для нужных функций", "Only permissions needed by your chosen features"))
            ScrollView {
                VStack(spacing: 14) {
                    accessCard("Screen Recording", description: workbench.text("Для записи выбранного дисплея. Другие функции работают без него.", "To record the selected display. Other features work without it."), allowed: workbench.recorder.screenAllowed, symbol: "display", pane: "ScreenCapture")
                    accessCard("Microphone", description: workbench.text("Для входов аудиокарты, включая loopback. В режиме «Без звука» не нужен.", "For audio inputs including hardware loopback. Not needed in No audio mode."), allowed: workbench.recorder.microphoneStatus == .authorized, symbol: "mic", pane: "Microphone")
                    accessCard("Accessibility", description: workbench.text("Для popup у текстового курсора и быстрой вставки. История и копирование работают без него.", "For caret placement and automatic paste. History and copy work without it."), allowed: AXIsProcessTrusted(), symbol: "cursorarrow.rays", pane: "Accessibility")
                    GlassCard { VStack(alignment: .leading, spacing: 12) { Label(workbench.text("Папки", "Folders"), systemImage: "folder").font(.headline); Text(workbench.files.prefs.watchedFolder.path).font(.caption).textSelection(.enabled); if let issue = workbench.files.folderProblem { Text(issue).foregroundStyle(.orange) }; Button(workbench.text("Проверить выбранные папки", "Check selected folders")) { workbench.files.retryWatching() }; Text(workbench.text("Доступ к папке записи проверяется при сохранении. Доступ ко всему диску не требуется.", "The recording folder is checked when saving. Full Disk Access is not required.")).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }
                    Button(workbench.text("Проверить разрешения снова", "Recheck permissions")) { workbench.recorder.refreshPermissions(); refreshed += 1 }.buttonStyle(PumpkinButtonStyle(primary: true))
                    Text(workbench.text("Если macOS требует перезапуск Pumpkin, сначала останови запись и дождись сохранения.", "If macOS requests a Pumpkin restart, stop recording and wait for the save first.")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.id(refreshed).onAppear { workbench.recorder.refreshPermissions() }
    }
    private func accessCard(_ title: String, description: String, allowed: Bool, symbol: String, pane: String) -> some View {
        GlassCard { VStack(alignment: .leading, spacing: 12) { HStack { Label(title, systemImage: symbol).font(.headline); Spacer(); StatusPill(title: allowed ? workbench.text("Разрешено", "Allowed") : workbench.text("Нужен доступ", "Access needed"), symbol: allowed ? "checkmark.circle" : "lock", color: allowed ? GlassPalette.sage : .orange) }; Text(description).font(.callout).foregroundStyle(.secondary); HStack { Button(workbench.text("Открыть настройки macOS", "Open System Settings")) { RecorderModel.openPrivacy(pane) }; if !allowed { Button(workbench.text("Запросить", "Request")) { if pane == "Accessibility" { ClipboardHistory.requestAccessibility() } else if pane == "ScreenCapture" { _ = CGRequestScreenCaptureAccess(); workbench.recorder.refreshPermissions() } else { Task { _ = await AVCaptureDevice.requestAccess(for: .audio); workbench.recorder.refreshPermissions() } } } } } }.frame(maxWidth: .infinity, alignment: .leading) }
    }
}

struct WelcomeView: View {
    @Environment(Workbench.self) private var workbench
    @State private var access = false
    var body: some View {
        @Bindable var prefs = workbench.prefs
        return VStack(alignment: .leading, spacing: 22) {
            if access {
                AccessWorkspace()
                HStack { Button(workbench.text("Назад", "Back")) { access = false }; Spacer(); Button(workbench.text("Открыть Pumpkin", "Open Pumpkin")) { workbench.finishIntro() }.buttonStyle(PumpkinButtonStyle(primary: true)) }
            } else {
                HStack { Text("🎃").font(.system(size: 70)); VStack(alignment: .leading, spacing: 5) { Text("Pumpkin").font(.system(size: 46, weight: .heavy, design: .rounded)); Text(workbench.text("Запиши. Вставь. Оставь только нужное.", "Record. Paste. Keep what matters.")).font(.title3) } }
                Text(workbench.files.prefs.hasCompletedOnboarding ? workbench.text("Новые функции рядом с привычными таймерами. Твои сроки и настройки сохранены.", "New features alongside your timers. Existing expiry rules and settings are preserved.") : workbench.text("Выбери нужные функции. Всё работает локально, без аккаунта.", "Choose your features. Everything runs locally, with no account.")).foregroundStyle(.secondary)
                GlassCard { Toggle(isOn: $prefs.recordingEnabled) { Label(workbench.text("Запись экрана · MP4 и аппаратный звук", "Screen recording · MP4 and hardware audio"), systemImage: "record.circle") }.font(.headline) }
                GlassCard { Toggle(isOn: Binding(get: { prefs.clipboardEnabled }, set: { workbench.setClipboardEnabled($0) })) { Label(workbench.text("Буфер · недавний текст в памяти", "Clipboard · recent text in memory"), systemImage: "clipboard") }.font(.headline) }
                GlassCard { VStack(alignment: .leading, spacing: 12) { Toggle(workbench.text("Очистка Downloads", "Downloads expiry"), isOn: Binding(get: { workbench.files.prefs.watchDownloads }, set: { workbench.files.prefs.watchDownloads = $0 })); Toggle(workbench.text("Очистка скриншотов", "Screenshot expiry"), isOn: Binding(get: { workbench.files.prefs.watchScreenshots }, set: { workbench.files.prefs.watchScreenshots = $0 })); Text(workbench.text("По выбранному сроку → в Корзину. Можно вернуть.", "At your chosen expiry → Trash. You can put files back.")).font(.caption).foregroundStyle(.secondary) } }
                Spacer(minLength: 0)
                HStack { Button(workbench.text("Настроить позже", "Set up later")) {
                    if !workbench.files.prefs.hasCompletedOnboarding { workbench.files.prefs.watchDownloads = false; workbench.files.prefs.watchScreenshots = false }
                    workbench.finishIntro(connectFolders: false)
                }; Spacer(); Button(workbench.text("Продолжить", "Continue")) { access = true }.buttonStyle(PumpkinButtonStyle(primary: true)) }
            }
        }
    }
}
