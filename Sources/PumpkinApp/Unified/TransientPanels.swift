import AppKit
import SwiftUI
import PumpkinCore

struct UnifiedTransientPanel: View {
    @Environment(Workbench.self) private var workbench
    let presentation: PanelPresentation
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch presentation.scene {
            case .list: menu
            case .prompt(let fallback):
                let batch = workbench.files.prompts.first { $0.id == fallback.id } ?? fallback
                HStack { Label(batch.kind == .screenshot ? workbench.text("Новый скриншот", "New screenshot") : workbench.text("Новый файл", "New file"), systemImage: batch.kind == .screenshot ? "photo" : "arrow.down.circle").font(.caption.bold()).foregroundStyle(GlassPalette.orange); Spacer(); Text("\(batch.items.count)").font(.caption) }
                Text(workbench.text("Сколько хранить?", "How long to keep?")).font(.system(size: 23, weight: .bold, design: .rounded))
                HStack { Image(nsImage: FileIcons.icon(path: batch.primary.url.path, isFolder: batch.primary.snapshot.isFolder)).resizable().frame(width: 44, height: 44); VStack(alignment: .leading, spacing: 4) { Text(batch.title).font(.headline).lineLimit(2); Text(batch.items.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(3) } }
                HStack(spacing: 4) {
                    ForEach(Array(batch.stops.enumerated()), id: \.offset) { index, duration in
                        Button { workbench.files.select(index, in: batch.id) } label: {
                            Text(compactDuration(duration)).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(index == batch.selection ? GlassPalette.orange.opacity(0.8) : Color.white.opacity(0.15), in: Capsule())
                        }.buttonStyle(.plain).accessibilityLabel(durationLabel(duration, workbench: workbench)).accessibilityAddTraits(index == batch.selection ? .isSelected : [])
                    }
                }
                Text(workbench.text("По сроку — в Корзину. Можно вернуть.", "At expiry — Trash. You can put it back.")).font(.caption).foregroundStyle(.secondary)
                HStack { Button(workbench.text("Оставить навсегда", "Keep forever")) { workbench.files.keep(batch.id) }.buttonStyle(PumpkinButtonStyle()); Spacer(); Button(workbench.text("Готово", "Done")) { workbench.files.confirm(batch.id) }.buttonStyle(PumpkinButtonStyle(primary: true)) }
                Text("← → · Return · K · Esc").font(.caption2).foregroundStyle(.secondary)
            case .confirmation(let confirmation):
                Label(confirmation.title, systemImage: "checkmark.circle").font(.headline).lineLimit(2)
                switch confirmation.kind {
                case .kept: Text(workbench.text("Хранить бессрочно", "Kept forever"))
                case .scheduled(let date): Text(date, style: .relative)
                }
            case .toast(let toast):
                switch toast.kind {
                case .trashed(let records):
                    Label(workbench.text("Перемещено в Корзину", "Moved to Trash"), systemImage: "trash").font(.headline)
                    Text(records.map(\.name).joined(separator: ", ")).font(.caption).lineLimit(3)
                    Button(workbench.text("Вернуть", "Put back")) { workbench.files.putBack(records) }.buttonStyle(PumpkinButtonStyle(primary: true))
                case .restored(let name, _): Label(workbench.text("Восстановлен: ", "Restored: ") + name, systemImage: "arrow.uturn.backward").font(.headline).lineLimit(3)
                case .failed(let title, let message): Label(title, systemImage: "exclamationmark.triangle").font(.headline); Text(message).font(.caption)
                }
            }
        }.padding(18).frame(width: PanelController.width, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            .background { GlassBackdrop() }.clipShape(RoundedRectangle(cornerRadius: PanelController.cornerRadius)).tint(GlassPalette.orange)
            .modifier(PumpkinContentColor())
            .preferredColorScheme(workbench.prefs.theme == "dark" ? .dark : workbench.prefs.theme == "light" ? .light : nil)
            .environment(\.locale, Locale(identifier: workbench.prefs.language == "en" ? "en" : "ru"))
    }
    private func compactDuration(_ duration: ShelfDuration) -> String {
        guard workbench.prefs.language != "en" else { return duration.shortLabel }
        switch Int(duration.seconds) { case 600: return "10м"; case 1800: return "30м"; case 3600: return "1ч"; case 86400: return "1д"; case 604800: return "1н"; case 2592000: return "30д"; default: return duration.shortLabel }
    }
    private var menu: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 32, height: 32); Text("Pumpkin").font(.system(size: 21, weight: .heavy, design: .rounded)); Spacer(); Text("2.0").font(.caption).foregroundStyle(.secondary) }
            if workbench.recorder.busy {
                GlassCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(workbench.recorder.phase == .recording ? workbench.recorder.elapsed : workbench.text("Подготовка / сохранение", "Preparing / saving"), systemImage: "record.circle.fill").font(.headline.monospacedDigit()).foregroundStyle(.red)
                        if workbench.recorder.phase == .recording { Button(workbench.text("Остановить и сохранить", "Stop and save")) { workbench.files.isListOpen = false; workbench.recorder.toggle() }.buttonStyle(PumpkinButtonStyle(primary: true)) }
                    }
                }
            }
            menuEntry(workbench.text("Записать экран", "Record screen"), "record.circle", .recording)
            Button { workbench.files.isListOpen = false; workbench.showQuickClipboard() } label: { HStack { Label(workbench.text("Буфер", "Clipboard"), systemImage: "clipboard"); Spacer(); Text(workbench.prefs.clipboardShortcut.label).font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain).padding(.vertical, 5)
            menuEntry(workbench.text("Очистка", "Cleanup"), "timer", .cleanup)
            Divider()
            Button(workbench.files.isPaused ? workbench.text("Продолжить таймеры", "Resume timers") : workbench.text("Пауза таймеров", "Pause timers")) { workbench.files.togglePause() }.buttonStyle(.plain)
            if !workbench.files.prompts.isEmpty { Text(workbench.text("\(workbench.files.prompts.reduce(0) { $0 + $1.items.count }) ждут решения", "\(workbench.files.prompts.reduce(0) { $0 + $1.items.count }) need a decision")).font(.caption).foregroundStyle(.secondary) }
            if let error = workbench.shortcutError { Text(error).font(.caption).foregroundStyle(.orange) }
            Divider()
            HStack { Button(workbench.text("Настройки", "Settings")) { workbench.files.isListOpen = false; workbench.open(.settings) }.buttonStyle(.plain); Spacer(); Button(workbench.text("Выйти", "Quit")) { NSApp.terminate(nil) }.buttonStyle(.plain) }
        }
    }
    private func menuEntry(_ label: String, _ icon: String, _ section: WorkspaceSection) -> some View {
        Button { workbench.files.isListOpen = false; workbench.open(section) } label: { Label(label, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5) }.buttonStyle(.plain)
    }
}
