import SwiftUI

struct ClipboardWorkspace: View {
    @Environment(Workbench.self) private var workbench
    @State private var selectedID: UUID?
    private var selected: ClipboardEntry? { workbench.clipboard.entries.first { $0.id == selectedID } ?? workbench.clipboard.entries.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(title: workbench.text("Буфер", "Clipboard"), subtitle: workbench.text("Недавний текст · до 60 элементов", "Recent text · up to 60 items"))
            Label(workbench.text("История хранится до выхода из Pumpkin", "History stays in memory until you quit Pumpkin"), systemImage: "lock").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(workbench.clipboard.paused ? workbench.text("Продолжить историю", "Resume history") : workbench.text("Пауза истории", "Pause history")) { workbench.clipboard.paused.toggle() }.buttonStyle(PumpkinButtonStyle()).disabled(!workbench.prefs.clipboardEnabled)
                Button { workbench.clearClipboard() } label: { Label(workbench.text("Очистить историю", "Clear history"), systemImage: "trash") }.buttonStyle(PumpkinButtonStyle()).disabled(workbench.clipboard.entries.isEmpty)
            }
            if !workbench.prefs.clipboardEnabled {
                GlassCard { VStack(spacing: 16) { Image(systemName: "clipboard").font(.system(size: 48)).foregroundStyle(GlassPalette.orange); Text(workbench.text("История выключена", "History is off")).font(.title2.bold()); Text(workbench.text("Начнём сохранять новый скопированный текст только после включения. Всё остаётся в памяти этого Mac.", "New clipboard text is captured only after you enable history. Everything stays in this Mac's memory.")).multilineTextAlignment(.center); Button(workbench.text("Включить историю", "Enable history")) { workbench.setClipboardEnabled(true) }.buttonStyle(PumpkinButtonStyle(primary: true)) }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity) }
            } else if workbench.clipboard.entries.isEmpty {
                GlassCard { VStack(spacing: 15) { Text("🎃").font(.system(size: 64)); Text(workbench.text("Скопируй текст — он появится здесь", "Copy some text — it will appear here")).font(.title2.bold()).multilineTextAlignment(.center); Text(workbench.prefs.clipboardShortcut.label + " · " + workbench.text("быстрый буфер у курсора", "quick clipboard at your cursor")).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    GlassCard(padding: 12) {
                        VStack {
                            ScrollView {
                                LazyVStack(spacing: 4) {
                                    ForEach(Array(workbench.clipboard.entries.enumerated()), id: \.element.id) { index, entry in
                                        Button { selectedID = entry.id } label: {
                                            HStack(spacing: 10) { Text("\(index + 1)").font(.caption.bold()).frame(width: 26, height: 28).background(GlassPalette.orange.opacity(selected?.id == entry.id ? 0.8 : 0.12), in: RoundedRectangle(cornerRadius: 9)); Image(systemName: entry.symbol).frame(width: 18); Text(entry.preview).lineLimit(1); Spacer(minLength: 0); Text(entry.copiedAt, style: .relative).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }.font(.system(size: 13, weight: .medium)).padding(8).background(selected?.id == entry.id ? Color.white.opacity(0.32) : .clear, in: RoundedRectangle(cornerRadius: 16))
                                        }.buttonStyle(.plain).accessibilityAddTraits(selected?.id == entry.id ? .isSelected : [])
                                    }
                                }
                            }
                            HStack { Text("\(workbench.clipboard.entries.count) / 60"); Spacer(); Text(workbench.text("Сначала новое", "Newest first")) }.font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    GlassCard {
                        if let selected {
                            VStack(alignment: .leading, spacing: 16) {
                                StatusPill(title: workbench.text("\(selected.text.count) символов", "\(selected.text.count) characters"), symbol: selected.symbol, color: GlassPalette.orange)
                                ScrollView { Text(selected.text).font(.system(size: 16)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(14) }.background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                                Button { workbench.copy(selected) } label: { Label(workbench.text("Скопировать", "Copy"), systemImage: "doc.on.doc").frame(maxWidth: .infinity) }.buttonStyle(PumpkinButtonStyle(primary: true))
                                Text(workbench.text("Текст останется в системном буфере. Это окно ничего не вставляет само.", "The text stays on the system clipboard. This window never pastes into another app.")).font(.caption).foregroundStyle(.secondary)
                                Button(workbench.prefs.clipboardShortcut.label + " " + workbench.text("Быстрый буфер", "Quick clipboard")) { workbench.showQuickClipboard() }.font(.caption)
                            }
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
