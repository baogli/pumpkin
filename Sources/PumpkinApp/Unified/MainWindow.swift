import AppKit
import SwiftUI
import PumpkinCore

@MainActor
final class WorkbenchWindow: NSWindowController, NSWindowDelegate {
    let workbench: Workbench
    init(workbench: Workbench) {
        self.workbench = workbench
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Pumpkin"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 760, height: 600)
        window.backgroundColor = .clear; window.isOpaque = false; window.appearance = workbench.prefs.appearance
        window.contentView = NSHostingView(rootView: WorkbenchRoot().environment(workbench))
        super.init(window: window); window.delegate = self; window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    func present() { window?.appearance = workbench.prefs.appearance; workbench.windowVisible = true; NSApp.activate(); window?.makeKeyAndOrderFront(nil) }
    func windowWillClose(_ notification: Notification) { workbench.windowVisible = false }
    func windowDidMiniaturize(_ notification: Notification) { workbench.windowVisible = false }
    func windowDidDeminiaturize(_ notification: Notification) { workbench.windowVisible = true }
    func windowDidBecomeKey(_ notification: Notification) { workbench.windowVisible = true; workbench.recorder.refreshPermissions() }
}

struct WorkbenchRoot: View {
    @Environment(Workbench.self) private var workbench
    var body: some View {
        ZStack {
            GlassBackdrop()
            if workbench.intro { WelcomeView().padding(34).padding(.top, 14) }
            else {
                HStack(spacing: 0) {
                    sidebar.frame(width: 210).padding(10)
                    VStack(spacing: 14) {
                        if workbench.recorder.busy && workbench.section != .recording { recordingBanner }
                        if let notice = workbench.notice {
                            HStack { Label(notice, systemImage: "checkmark.circle"); Spacer(); if let action = workbench.noticeAction { Button(workbench.text("Открыть", "Open")) { workbench.section = action; workbench.notice = nil } }; Button { workbench.notice = nil; workbench.noticeAction = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }.font(.callout).padding(10).background(GlassPalette.sage.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        }
                        Group {
                            switch workbench.section {
                            case .recording: RecordingWorkspace()
                            case .clipboard: ClipboardWorkspace()
                            case .cleanup: CleanupWorkspace()
                            case .settings: UnifiedSettingsView()
                            case .access: AccessWorkspace()
                            }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }.padding(.leading, 12).padding(.trailing, 24).padding(.top, 28).padding(.bottom, 22)
                }
            }
        }.tint(GlassPalette.orange).environment(\.locale, Locale(identifier: workbench.prefs.language == "en" ? "en" : "ru"))
            .preferredColorScheme(workbench.prefs.theme == "dark" ? .dark : workbench.prefs.theme == "light" ? .light : nil)
            .clipShape(RoundedRectangle(cornerRadius: 28))
    }
    private var sidebar: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 36, height: 36)
                    VStack(alignment: .leading) { Text("Pumpkin").font(.system(size: 21, weight: .heavy, design: .rounded)); Text(workbench.text("версия 2.0", "version 2.0")).font(.caption).foregroundStyle(.secondary) }
                }.padding(.horizontal, 6).padding(.top, 38).padding(.bottom, 18)
                navigation(.recording, workbench.text("Запись", "Record"), "record.circle")
                navigation(.clipboard, workbench.text("Буфер", "Clipboard"), "clipboard")
                navigation(.cleanup, workbench.text("Очистка", "Cleanup"), "timer", badge: workbench.files.prompts.reduce(0) { $0 + $1.items.count })
                Spacer(minLength: 20)
                GlassCard(padding: 12) {
                    HStack {
                        Image(systemName: workbench.files.isPaused ? "pause.circle" : "timer").font(.title2).foregroundStyle(GlassPalette.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workbench.files.isPaused ? workbench.text("Таймеры на паузе", "Timers paused") : workbench.text("Таймеры идут", "Timers running")).font(.system(size: 12, weight: .semibold))
                            if let item = workbench.files.soonest {
                                TimelineView(.periodic(from: .now, by: 10)) { context in Text(Formatting.compactRemaining(item.remaining(at: workbench.files.clock(context.date)))).font(.caption).foregroundStyle(.secondary) }
                            } else { Text(workbench.text("Нет активных сроков", "No active timers")).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                navigation(.settings, workbench.text("Настройки", "Settings"), "gearshape")
            }.frame(maxHeight: .infinity)
        }
    }
    private func navigation(_ section: WorkspaceSection, _ title: String, _ symbol: String, badge: Int = 0) -> some View {
        Button { workbench.section = section } label: {
            HStack { Image(systemName: symbol).frame(width: 24).foregroundStyle(workbench.section == section ? GlassPalette.orange : .secondary); Text(title); Spacer(); if badge > 0 { Text("\(badge)").font(.caption.bold()).padding(6).background(GlassPalette.orange, in: Circle()) } }
                .font(.system(size: 15, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 12)
                .background(workbench.section == section ? Color.white.opacity(0.32) : .clear, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityAddTraits(workbench.section == section ? .isSelected : [])
    }
    private var recordingBanner: some View {
        HStack { Label(workbench.recorder.phase == .recording ? workbench.recorder.elapsed : workbench.text("Подготовка / сохранение", "Preparing / saving"), systemImage: "record.circle.fill").foregroundStyle(.red); Spacer(); Button(workbench.text("К записи", "Show recorder")) { workbench.section = .recording }; if workbench.recorder.phase == .recording { Button(workbench.text("Остановить и сохранить", "Stop and save")) { workbench.recorder.toggle() } } }.font(.callout).padding(10).background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
