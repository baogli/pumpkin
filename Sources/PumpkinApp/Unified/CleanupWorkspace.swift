import AppKit
import SwiftUI
import PumpkinCore

enum CleanupClassification {
    static func kind(of item: TrackedItem) -> ItemKind {
        if let kind = item.kind.flatMap(ItemKind.init(rawValue:)) { return kind }
        if item.source == "Pumpkin Recording" { return .recording }
        return Screenshots.isTaggedScreenCapture(item.url) ? .screenshot : .download
    }
    static func kind(of record: TrashRecord, recordings: [RecordingEntry]) -> ItemKind {
        if let kind = record.kind.flatMap(ItemKind.init(rawValue:)) { return kind }
        let url = URL(fileURLWithPath: record.trashedPath ?? record.originalPath)
        if recordings.contains(where: { $0.matches(url) }) { return .recording }
        return Screenshots.isTaggedScreenCapture(url) ? .screenshot : .download
    }
}

struct CleanupWorkspace: View {
    @Environment(Workbench.self) private var workbench
    @State private var filter = 0
    private var files: AppModel { workbench.files }
    private var shownPrompts: [PromptBatch] { files.prompts.filter { matches($0.kind) } }
    private var shownItems: [TrackedItem] { files.sortedItems.filter { matches(CleanupClassification.kind(of: $0)) } }
    private var shownHistory: [TrashRecord] { files.history.filter { matches(CleanupClassification.kind(of: $0, recordings: files.recordings)) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { ScreenHeader(title: workbench.text("Очистка", "Cleanup"), subtitle: workbench.text("Загрузки и скриншоты: срок → Корзина → вернуть", "Downloads and screenshots: expiry → Trash → restore")); Spacer(); Button(files.isPaused ? workbench.text("Продолжить", "Resume timers") : workbench.text("Пауза таймеров", "Pause timers")) { files.togglePause() }.buttonStyle(PumpkinButtonStyle()) }
            PillSegments(selection: $filter, choices: [(workbench.text("Все", "All"), 0), (workbench.text("Загрузки", "Downloads"), 1), (workbench.text("Скриншоты", "Screenshots"), 2), (workbench.text("Записи", "Recordings"), 3)])
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let problem = files.folderProblem { issue(problem) }
                    if let problem = files.screenshotProblem { issue(problem) }
                    if workbench.recorder.busy { Text(workbench.text("Во время записи вопросы и уведомления не всплывают. Таймеры продолжают работать, если не на паузе.", "During recording, prompts are deferred. Timers continue unless paused.")).font(.caption).foregroundStyle(.secondary) }
                    ForEach(shownPrompts) { batch in
                        GlassCard { pending(batch) }
                    }
                    HStack { Text(workbench.text("С таймером", "Expiring files")).font(.headline); Text("· \(shownItems.count)").foregroundStyle(.secondary) }.padding(.top, 8)
                    if shownItems.isEmpty && shownPrompts.isEmpty {
                        GlassCard { VStack(spacing: 12) { Image(systemName: "leaf").font(.largeTitle).foregroundStyle(GlassPalette.sage); Text(workbench.text("Всё спокойно", "All clear")).font(.title2.bold()); Text(workbench.text("Новые загрузки и скриншоты появятся здесь. Файлы до первого запуска не трогаем.", "New downloads and screenshots appear here. Files from before your first launch are left alone.")).multilineTextAlignment(.center).foregroundStyle(.secondary); Button(workbench.text("Настроить папки", "Set up folders")) { workbench.section = .settings } }.padding(18).frame(maxWidth: .infinity) }
                    }
                    ForEach(shownItems) { item in GlassCard(padding: 16) { tracked(item) } }
                    HStack { Text(workbench.text("Недавно в Корзине", "Recently trashed")).font(.headline); Text(workbench.text("Pumpkin не очищает Корзину", "Pumpkin never empties the Trash")).font(.caption).foregroundStyle(.secondary) }.padding(.top, 10)
                    if shownHistory.isEmpty { Text(workbench.text("В этой категории пока нет истории", "No history in this category yet")).font(.caption).foregroundStyle(.secondary) }
                    ForEach(shownHistory.prefix(30)) { record in
                        GlassCard(padding: 13) {
                            HStack { Image(systemName: "trash").foregroundStyle(GlassPalette.sage); VStack(alignment: .leading, spacing: 4) { Text(record.name).font(.headline).lineLimit(1); Text(record.restoredAt != nil ? workbench.text("Восстановлен", "Restored") : record.canPutBack ? workbench.text("В Корзине", "In the Trash") : workbench.text("Больше нет в Корзине", "No longer in the Trash")).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(workbench.text("Вернуть", "Put back")) { files.putBack([record]) }.buttonStyle(PumpkinButtonStyle()).disabled(!record.canPutBack) }
                        }
                    }
                    if let toast = files.toast { toastMessage(toast) }
                }.padding(.bottom, 8)
            }
        }
    }
    private func matches(_ kind: ItemKind) -> Bool {
        filter == 0 || (filter == 1 && kind == .download) || (filter == 2 && kind == .screenshot) || (filter == 3 && kind == .recording)
    }
    private func pending(_ batch: PromptBatch) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: batch.kind == .screenshot ? "photo" : "arrow.down.circle").foregroundStyle(GlassPalette.orange); VStack(alignment: .leading, spacing: 4) { Text(batch.items.count == 1 ? batch.primary.name : workbench.text("\(batch.items.count) файла ждут решения", "\(batch.items.count) files need a decision")).font(.headline).lineLimit(2); Text(batch.items.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(2) }; Spacer() }
            Text(workbench.text("Сколько хранить?", "How long to keep?")).font(.caption.bold())
            PillSegments(selection: Binding(get: { batch.selection }, set: { files.select($0, in: batch.id) }), choices: batch.stops.enumerated().map { (durationLabel($0.element, workbench: workbench), $0.offset) })
            HStack { Text(workbench.text("По сроку → в Корзину", "At expiry → Trash")).font(.caption).foregroundStyle(.secondary); Spacer(); Button(workbench.text("Оставить навсегда", "Keep forever")) { files.keep(batch.id) }.buttonStyle(PumpkinButtonStyle()); Button(workbench.text("Готово", "Done")) { files.confirm(batch.id) }.buttonStyle(PumpkinButtonStyle(primary: true)) }
        }
    }
    private func tracked(_ item: TrackedItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(nsImage: FileIcons.icon(path: item.path, isFolder: item.isFolder)).resizable().frame(width: 32, height: 32); VStack(alignment: .leading, spacing: 4) { Text(item.name).font(.headline).lineLimit(1).truncationMode(.middle); Text(item.expiresAt, style: .date).font(.caption).foregroundStyle(.secondary) }; Spacer(); TimelineView(.periodic(from: .now, by: 1)) { context in Text(files.isPaused ? workbench.text("Пауза", "Paused") : Formatting.compactRemaining(item.remaining(at: files.clock(context.date)))).font(.headline.monospacedDigit()).foregroundStyle(item.remaining(at: files.clock(context.date)) < 600 ? .red : GlassPalette.orange) } }
            if let error = item.lastError { Text(workbench.message(error)).font(.caption).foregroundStyle(.red) }
            HStack {
                Menu(workbench.text("Изменить срок", "Change expiry")) { ForEach(ShelfDuration.standardStops) { duration in Button(durationLabel(duration, workbench: workbench)) { files.setTimer(for: item.id, to: duration) } } }
                Button(workbench.text("Оставить навсегда", "Keep forever")) { files.keepForever(item.id) }.buttonStyle(PumpkinButtonStyle())
                Button { files.reveal(item) } label: { Image(systemName: "folder") }.help(item.path)
            }
        }
    }
    private func issue(_ text: String) -> some View { HStack { Image(systemName: "exclamationmark.triangle"); Text(workbench.message(text)); Spacer(); Button(workbench.text("Доступы", "Access")) { workbench.section = .access } }.font(.callout).padding(12).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14)) }
    @ViewBuilder private func toastMessage(_ toast: Toast) -> some View {
        switch toast.kind {
        case .failed(let title, let message): issue(title + "\n" + message)
        case .restored(let name, _): Text(workbench.text("Восстановлен: ", "Restored: ") + name).font(.callout).foregroundStyle(GlassPalette.sage)
        case .trashed(let records): Text(workbench.text("В Корзину: ", "Moved to Trash: ") + records.map(\.name).joined(separator: ", ")).font(.callout)
        }
    }
}
