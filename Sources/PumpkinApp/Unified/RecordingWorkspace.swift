import AppKit
import SwiftUI
import PumpkinCore

struct RecordingWorkspace: View {
    @Environment(Workbench.self) private var workbench
    @State private var assigning: RecordingEntry?
    @State private var selectedDuration: Double?
    @State private var setupWidth: CGFloat = 0
    private var recorder: RecorderModel { workbench.recorder }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                ScreenHeader(title: workbench.text("Запись", "Record"), subtitle: workbench.text("Один дисплей, MP4 и звук из выбранного устройства", "One display, MP4 and your audio input"))
                Spacer()
                if recorder.ready { StatusPill(title: workbench.text("Готово", "Ready")) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let error = recorder.error { message(error, symbol: "exclamationmark.triangle", color: .red) }
                    if let warning = recorder.warning { message(warning, symbol: "exclamationmark.triangle", color: .orange) }
                    if recorder.phase == .recording || recorder.phase == .countdown || recorder.phase == .finalizing || recorder.phase == .preparing {
                        activeRecording
                    } else if let id = recorder.resultID, let entry = workbench.files.recordings.first(where: { $0.id == id }) {
                        GlassCard { VStack(alignment: .leading, spacing: 12) { StatusPill(title: workbench.text("Запись сохранена", "Recording saved")); recordingRow(entry); Button(workbench.text("Новая запись", "New recording")) { recorder.clearResult() }.buttonStyle(PumpkinButtonStyle(primary: true)) } }
                    } else { setup }
                    if !workbench.files.recordings.isEmpty {
                        HStack { Text(workbench.text("Свои записи", "Your recordings")).font(.headline); Spacer(); Button(workbench.text("Импортировать MP4…", "Import MP4…")) { importVideos() } }.padding(.top, 4)
                        ForEach(workbench.files.recordings) { entry in GlassCard(padding: 14) { recordingRow(entry) } }
                    } else if recorder.phase == .idle {
                        Button(workbench.text("Импортировать записи Able Recorder…", "Import Able Recorder videos…")) { importVideos() }.buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }.padding(.bottom, 8)
            }
            if recorder.phase == .idle && recorder.resultID == nil { recordingFooter }
        }.sheet(item: $assigning) { entry in
            VStack(alignment: .leading, spacing: 18) {
                Text(workbench.text("Сколько хранить запись?", "How long to keep this recording?")).font(.title2.bold())
                Text(entry.url.lastPathComponent).lineLimit(2)
                Text(workbench.text("Сейчас хранится бессрочно. Таймер появится только после подтверждения.", "Currently kept forever. A timer starts only after confirmation.")).foregroundStyle(.secondary)
                Picker(workbench.text("Срок", "Expiry"), selection: $selectedDuration) {
                    Text(workbench.text("Выбери срок", "Choose a duration")).tag(nil as Double?)
                    ForEach(ShelfDuration.standardStops) { duration in Text(durationLabel(duration, workbench: workbench)).tag(Optional(duration.seconds)) }
                }
                HStack { Button(workbench.text("Отмена", "Cancel")) { assigning = nil }; Spacer(); Button(workbench.text("Назначить срок", "Set expiry")) { if let seconds = selectedDuration { workbench.files.scheduleRecording(entry.id, duration: .seconds(seconds)) }; assigning = nil }.disabled(selectedDuration == nil).buttonStyle(PumpkinButtonStyle(primary: true)) }
            }.padding(28).frame(width: 420)
        }
    }
    private var setup: some View {
        @Bindable var recorder = workbench.recorder
        return VStack(spacing: 14) {
            HStack { Text(workbench.text("Что записываем", "Choose a display")).font(.headline); Spacer(); Button { recorder.refreshDevices() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).accessibilityLabel(workbench.text("Обновить устройства", "Refresh devices")) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190))], spacing: 12) {
                ForEach(recorder.displays) { display in
                    Button { recorder.options.displayID = display.id } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "display").font(.system(size: 28)).foregroundStyle(GlassPalette.orange)
                            VStack(alignment: .leading, spacing: 5) { Text(display.name).font(.system(size: 13, weight: .semibold)).lineLimit(2); Text("\(display.width) × \(display.height)").font(.caption).foregroundStyle(.secondary); if display.isMain { Text(workbench.text("Основной", "Main")).font(.caption2) } }
                            Spacer(minLength: 0)
                            if recorder.options.displayID == display.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(GlassPalette.orange) }
                        }.frame(height: 54).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 22))
                            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(recorder.options.displayID == display.id ? GlassPalette.orange : Color.white.opacity(0.45), lineWidth: recorder.options.displayID == display.id ? 2 : 1))
                    }.buttonStyle(.plain).disabled(recorder.locked)
                }
            }
            if recorder.selectedDisplay == nil { message(workbench.text("Выбранный дисплей недоступен. Выбери подключённый экран.", "The saved display is unavailable. Choose a connected screen."), symbol: "display.trianglebadge.exclamationmark", color: .orange) }
            if setupWidth >= 600 {
                HStack(alignment: .top, spacing: 12) {
                    GlassCard { audioSettings }.frame(width: (setupWidth - 12) / 2)
                    GlassCard { videoSettings }.frame(width: (setupWidth - 12) / 2)
                }
            } else {
                VStack(spacing: 12) {
                    GlassCard { audioSettings }.frame(maxWidth: .infinity)
                    GlassCard { videoSettings }.frame(maxWidth: .infinity)
                }
            }
            GlassCard(padding: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Toggle(workbench.text("Курсор в кадре", "Show cursor"), isOn: $recorder.options.cursor); Toggle(workbench.text("Отсчёт 3 с", "3-second countdown"), isOn: $recorder.options.countdown) }
                    HStack { Label(recorder.options.folderPath.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path + "/", with: ""), systemImage: "folder").font(.caption).lineLimit(1).truncationMode(.middle); Spacer(); Button(workbench.text("Выбрать…", "Choose…")) { recorder.chooseFolder() } }
                }.toggleStyle(.switch).controlSize(.mini).disabled(recorder.locked)
            }
            Text(workbench.text("Видео хранится бессрочно. Окна Pumpkin скрыты из записи; другие приложения и их уведомления могут попасть в кадр.", "Videos are kept forever. Pumpkin windows are excluded; other apps and notifications can appear in the recording.")).font(.caption).foregroundStyle(.secondary)
        }.background(GeometryReader { geometry in
            Color.clear.onAppear { setupWidth = geometry.size.width }.onChange(of: geometry.size.width) { _, width in setupWidth = width }
        })
    }
    private var recordingFooter: some View {
        GlassCard(padding: 14) {
                HStack { VStack(alignment: .leading, spacing: 4) { Text(recorder.selectedDisplay?.name ?? workbench.text("Выбери экран", "Choose a display")).font(.headline); Text(recorder.formatDescription).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button { workbench.requestRecording() } label: { Label(workbench.text("Начать запись", "Start recording"), systemImage: "record.circle") }.buttonStyle(PumpkinButtonStyle(primary: true)).disabled(!recorder.ready || !workbench.prefs.recordingEnabled || recorder.phase != .idle) }
            }
    }
    private var audioSettings: some View {
        @Bindable var recorder = workbench.recorder
        return VStack(alignment: .leading, spacing: 12) {
            Label(workbench.text("Звук", "Audio"), systemImage: "mic").font(.headline)
            PillSegments(selection: $recorder.options.withAudio, choices: [(workbench.text("Без звука", "No audio"), false), (workbench.text("Аудиоустройство", "Audio input"), true)]).disabled(recorder.locked)
            if recorder.options.withAudio {
                Text(workbench.text("Устройство", "Input")).font(.caption)
                Picker(workbench.text("Устройство", "Input"), selection: Binding(get: { recorder.options.deviceUID ?? "" }, set: { recorder.chooseDevice($0.isEmpty ? nil : $0) })) {
                    Text(workbench.text("Выбери устройство", "Choose input")).tag("")
                    ForEach(recorder.devices, id: \.uid) { device in Text("\(device.name) · \(device.channels) ch").tag(device.uid) }
                    if let uid = recorder.options.deviceUID, recorder.selectedDevice == nil { Text(workbench.text("Устройство отключено", "Input disconnected")).tag(uid) }
                }.labelsHidden().disabled(recorder.locked).help(recorder.selectedDevice?.name ?? workbench.text("Выбери устройство", "Choose input"))
                channelPicker(left: true); channelPicker(left: false)
                Toggle(workbench.text("Пара L/R выбрана верно", "Confirm this L/R pair"), isOn: $recorder.options.channelsConfirmed).font(.caption).disabled(recorder.locked)
                Button(recorder.phase == .monitoring ? workbench.text("Остановить проверку", "Stop sound check") : workbench.text("Проверить звук", "Check audio")) { recorder.toggleMonitor() }.buttonStyle(PumpkinButtonStyle()).disabled(!recorder.inputValid || (recorder.phase != .idle && recorder.phase != .monitoring))
                Text(workbench.text("Для Ableton выбери loopback-входы своей карты. Их номера зависят от устройства.", "For Ableton, choose your interface's loopback inputs. Channel numbers depend on the device.")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func channelPicker(left: Bool) -> some View {
        @Bindable var recorder = workbench.recorder
        return VStack(alignment: .leading, spacing: 5) {
            Text(left ? workbench.text("Левый (L)", "Left (L)") : workbench.text("Правый (R)", "Right (R)")).font(.caption)
            HStack {
            Picker(left ? "L" : "R", selection: left ? $recorder.options.left : $recorder.options.right) {
                ForEach(1...max(1, recorder.selectedDevice?.channels ?? 1), id: \.self) { Text("Input \($0)").tag($0) }
            }.labelsHidden().frame(minWidth: 108).disabled(recorder.locked)
            LevelMeter(level: left ? recorder.levelL : recorder.levelR, channel: left ? "L" : "R")
            }
        }
    }
    private var videoSettings: some View {
        @Bindable var recorder = workbench.recorder
        return VStack(alignment: .leading, spacing: 12) {
            Label(workbench.text("Видео", "Video"), systemImage: "video").font(.headline)
            Picker(workbench.text("Размер", "Size"), selection: $recorder.options.resolution) { ForEach([1080, 1440, 2160], id: \.self) { Text("\($0)p").tag($0) }; Text(workbench.text("Исходный", "Native")).tag(0) }
            HStack { Text(workbench.text("Частота", "Rate")).font(.caption); PillSegments(selection: $recorder.options.fps, choices: [("30 fps", 30), ("60 fps", 60)]) }
            Text(workbench.text("Качество", "Quality")).font(.caption)
            Picker(workbench.text("Качество", "Quality"), selection: $recorder.options.quality) { Text(workbench.text("Компактное", "Compact")).tag(0); Text(workbench.text("Сбалансированное", "Balanced")).tag(1); Text(workbench.text("Высокое", "High")).tag(2) }.labelsHidden()
            Text(workbench.text("примерно \(recorder.estimatedMB) МБ в минуту", "about \(recorder.estimatedMB) MB per minute")).font(.caption.bold()).foregroundStyle(GlassPalette.orange)
            HStack { Text(workbench.text("Кодек", "Codec")).font(.caption); PillSegments(selection: $recorder.options.hevc, choices: [("H.264", false), ("HEVC", true)]) }
            Text(workbench.text("H.264 — для совместимости. HEVC поддерживается не на всех устройствах.", "H.264 for compatibility. HEVC support varies by device.")).font(.caption).foregroundStyle(.secondary)
        }.disabled(recorder.locked)
    }
    private var activeRecording: some View {
        GlassCard {
            VStack(spacing: 22) {
                if recorder.phase == .countdown { Text("\(recorder.countdownValue)").font(.system(size: 100, weight: .heavy, design: .rounded)).foregroundStyle(GlassPalette.orange) }
                else if recorder.phase == .recording { Label(recorder.elapsed, systemImage: "record.circle.fill").font(.system(size: 44, weight: .bold, design: .monospaced)).foregroundStyle(.red); Text(ByteCountFormatter.string(fromByteCount: recorder.bytes, countStyle: .file)).foregroundStyle(.secondary) }
                else { ProgressView(); Text(recorder.phase == .finalizing ? workbench.text("Сохраняем MP4…", "Saving MP4…") : workbench.text("Подготовка записи…", "Preparing recording…")).font(.title2.bold()) }
                Text(recorder.selectedDisplay?.name ?? "Display").font(.headline)
                Text(recorder.options.withAudio ? recorder.audioDescription : workbench.text("Без звука", "No audio")).font(.caption).multilineTextAlignment(.center)
                if recorder.options.withAudio { HStack { Text("L"); LevelMeter(level: recorder.levelL, channel: "L"); Text("R"); LevelMeter(level: recorder.levelR, channel: "R") } }
                Text(workbench.text("Хранить бессрочно", "Keep forever")).foregroundStyle(.secondary)
                if recorder.phase != .finalizing {
                    Button(recorder.phase == .recording ? workbench.text("Остановить и сохранить", "Stop and save") : workbench.text("Отмена", "Cancel")) { recorder.toggle() }.buttonStyle(PumpkinButtonStyle(primary: true))
                }
            }.frame(maxWidth: .infinity).padding(.vertical, 24)
        }
    }
    private func recordingRow(_ entry: RecordingEntry) -> some View {
        let url = entry.locatedURL
        let trashed = workbench.files.history.first { $0.originalPath == entry.path && $0.canPutBack }
        let timer = workbench.files.items.first { item in url.map { item.fileID == FolderScanner.fileID(of: $0) && item.folderPath == $0.deletingLastPathComponent().path } ?? false }
        return VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: "film").foregroundStyle(GlassPalette.orange); Text(url?.lastPathComponent ?? entry.url.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle); Spacer(); if entry.status != .finished { StatusPill(title: workbench.text("Незавершённая", "Unfinished"), symbol: "exclamationmark.triangle", color: .orange) } }
            Text("\(Int(entry.duration)) s · \(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)) · \(entry.format)").font(.caption).foregroundStyle(.secondary)
            Text(workbench.message(entry.screen) + " · " + workbench.message(entry.audio)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if let error = entry.error { Text(workbench.message(error)).font(.caption).foregroundStyle(.red) }
            if let trashed {
                HStack { Text(workbench.text("В Корзине", "In the Trash")).font(.caption).foregroundStyle(.secondary); Spacer(); Button(workbench.text("Вернуть", "Put back")) { workbench.files.putBack([trashed]) }.buttonStyle(PumpkinButtonStyle()) }
            } else if entry.status == .finished, let url {
                HStack {
                    Button(workbench.text("Открыть", "Open")) { NSWorkspace.shared.open(url) }
                    Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    Button(workbench.text("Путь", "Copy path")) { workbench.clipboard.copy(ClipboardEntry(text: url.path, copiedAt: Date())); workbench.notice = workbench.text("Путь скопирован", "Path copied") }
                    Spacer()
                    if let timer { Text(Formatting.compactRemaining(timer.remaining(at: workbench.files.clock(Date())))).font(.caption); Button(workbench.text("Навсегда", "Keep forever")) { workbench.files.keepForever(timer.id) } }
                    Button(workbench.text("Назначить срок", "Set expiry")) { selectedDuration = nil; assigning = entry }
                }.font(.caption)
            } else {
                HStack { Text(entry.status == .finished ? workbench.text("Файл недоступен", "File unavailable") : workbench.text("Частичный MP4 может не открыться", "Partial MP4 may not be playable")).font(.caption).foregroundStyle(.secondary); Spacer(); if FileManager.default.fileExists(atPath: entry.partialURL.path) { Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.partialURL]) } }; Button(workbench.text("Убрать из списка", "Remove from list")) { workbench.files.removeRecording(entry.id) } }
            }
        }
    }
    private func message(_ text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top) { Image(systemName: symbol).foregroundStyle(color); Text(workbench.message(text)).font(.callout); Spacer(); Button(workbench.text("Доступы", "Permissions")) { workbench.section = .access } }.padding(12).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }
    private func importVideos() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = true; panel.allowedContentTypes = [.mpeg4Movie]
        if panel.runModal() == .OK { Task { for url in panel.urls { do { try await recorder.importVideo(url) } catch { workbench.notice = workbench.message(error.localizedDescription) } } } }
    }
}

@MainActor func durationLabel(_ duration: ShelfDuration, workbench: Workbench) -> String {
    if workbench.prefs.language == "en" { return duration.longLabel }
    switch Int(duration.seconds) { case 600: return "10 мин"; case 1800: return "30 мин"; case 3600: return "1 час"; case 86400: return "1 день"; case 604800: return "1 неделя"; case 2592000: return "30 дней"; default: return duration.shortLabel }
}
