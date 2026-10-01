import AppKit
import SwiftUI
import Observation

@MainActor @Observable
final class QuickClipboardState {
    var entries: [ClipboardEntry] = []
    var selected = 0
    var expanded = false
    var insertMode = false
    var copyConfirmation = false
}

@MainActor
final class QuickClipboardController {
    private let workbench: Workbench
    private let accessibilityTrusted: () -> Bool
    private let state = QuickClipboardState()
    private let panel: MenuPanel
    private var target: NSRunningApplication?
    private var focused: AXUIElement?
    private var globalClick: Any?
    private var localEvents: Any?
    private var presentation = UUID()
    private(set) var visible = false
    var window: NSPanel { panel }

    init(workbench: Workbench, accessibilityTrusted: @escaping () -> Bool = AXIsProcessTrusted, observeOutsideClicks: Bool = true) {
        self.workbench = workbench
        self.accessibilityTrusted = accessibilityTrusted
        panel = MenuPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 330), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.level = .popUpMenu; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: QuickClipboardView(state: state, choose: { [weak self] index in self?.choose(index) }, close: { [weak self] in self?.hide() }).environment(workbench))
        if observeOutsideClicks { globalClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.hide() } }
        localEvents = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.visible else { return event }
            if event.type != .keyDown { if event.window !== self.panel { self.hide() }; return event }
            guard event.window === self.panel else { return event }
            switch event.keyCode {
            case 53: self.hide(); return nil
            case 125: self.state.selected = max(0, min(self.state.entries.count - 1, self.state.selected + 1)); return nil
            case 126: self.state.selected = max(0, self.state.selected - 1); return nil
            case 36, 76: self.choose(max(0, self.state.selected)); return nil
            default:
                let shown = self.state.expanded ? self.state.entries.count : min(self.workbench.prefs.visibleClips, self.state.entries.count)
                if let chars = event.charactersIgnoringModifiers, let number = Int(chars), (1...min(9, max(1, shown))).contains(number), number <= shown, event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                    self.choose(number - 1); return nil
                }
                return event
            }
        }
    }
    func toggle() {
        if visible { hide(); return }
        guard workbench.prefs.clipboardEnabled, !workbench.intro else { workbench.open(.clipboard); return }
        presentation = UUID()
        target = NSWorkspace.shared.frontmostApplication
        var bounds: CGRect?
        focused = nil
        if accessibilityTrusted(), let target, target.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            var element: CFTypeRef?
            if AXUIElementCopyAttributeValue(AXUIElementCreateApplication(target.processIdentifier), kAXFocusedUIElementAttribute as CFString, &element) == .success, let element, CFGetTypeID(element) == AXUIElementGetTypeID() {
                focused = (element as! AXUIElement)
                var selection: CFTypeRef?
                if AXUIElementCopyAttributeValue(focused!, kAXSelectedTextRangeAttribute as CFString, &selection) == .success, let selection, CFGetTypeID(selection) == AXValueGetTypeID() {
                    var rect: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(focused!, kAXBoundsForRangeParameterizedAttribute as CFString, selection, &rect) == .success, let rect, CFGetTypeID(rect) == AXValueGetTypeID() {
                        var frame = CGRect.zero
                        if AXValueGetValue(rect as! AXValue, .cgRect, &frame), frame.width >= 0, frame.height > 0 { bounds = frame }
                    }
                }
            }
        }
        state.insertMode = accessibilityTrusted() && focused.map(ClipboardHistory.acceptsPaste) == true
        state.entries = workbench.clipboard.entries
        state.selected = 0; state.expanded = false; state.copyConfirmation = false
        let mouse = NSEvent.mouseLocation
        let anchor = bounds.map { NSPoint(x: $0.minX, y: CGDisplayBounds(CGMainDisplayID()).height - $0.maxY) } ?? mouse
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        let available = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)
        let height = min(available.height - 16, CGFloat(min(workbench.prefs.visibleClips, max(1, state.entries.count))) * 49 + 144)
        let frame = Self.clampFrame(anchor: anchor, size: NSSize(width: min(420, available.width - 16), height: height), screen: available)
        panel.appearance = workbench.prefs.appearance; panel.setFrame(frame, display: true)
        workbench.clipboardVisible = true; visible = true
        workbench.files.isListOpen = false; workbench.hideWindow()
        panel.alphaValue = 1; panel.makeKeyAndOrderFront(nil)
    }
    static func clampFrame(anchor: NSPoint, size: NSSize, screen: NSRect) -> NSRect {
        let width = min(size.width, max(1, screen.width - 16)), height = min(size.height, max(1, screen.height - 16))
        let below = anchor.y - height - 8
        let y = below >= screen.minY + 8 ? below : anchor.y + 22
        return NSRect(x: max(screen.minX + 8, min(anchor.x, screen.maxX - width - 8)), y: max(screen.minY + 8, min(y, screen.maxY - height - 8)), width: width, height: height)
    }
    func hide() {
        presentation = UUID(); visible = false; panel.orderOut(nil); workbench.clipboardVisible = false
        state.entries = []; state.copyConfirmation = false; target = nil; focused = nil
    }
    private func choose(_ index: Int) {
        guard workbench.clipboard.enabled, !state.copyConfirmation, state.entries.indices.contains(index) else { return }
        let entry = state.entries[index], target = self.target, focused = self.focused
        let insert = state.insertMode
        hide()
        let expected = presentation
        if insert {
            workbench.clipboard.paste(entry, target: target, focusedElement: focused) { [weak self] delivered in
                guard let self, self.presentation == expected else { return }
                if !delivered {
                    self.workbench.notice = self.workbench.text("Не удалось вставить в исходное поле. Выбери текст в Буфере и нажми «Скопировать».", "The original field is unavailable. Select the item in Clipboard and press Copy.")
                    self.workbench.noticeIsError = true
                    self.workbench.open(.clipboard)
                }
            }
        } else {
            workbench.copy(entry)
            state.copyConfirmation = true
            let previous = panel.frame
            panel.setFrame(NSRect(x: previous.minX, y: previous.maxY - 90, width: previous.width, height: 90), display: true)
            // A brief non-key confirmation; ⌘V immediately goes to the original app.
            visible = true; workbench.clipboardVisible = true; panel.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                guard let self, self.presentation == expected, self.state.copyConfirmation else { return }; self.hide()
            }
        }
    }
    deinit {
        if let globalClick { NSEvent.removeMonitor(globalClick) }
        if let localEvents { NSEvent.removeMonitor(localEvents) }
    }
}

struct QuickClipboardView: View {
    @Environment(Workbench.self) private var workbench
    var state: QuickClipboardState
    var choose: (Int) -> Void
    var close: () -> Void
    private var count: Int { state.expanded ? state.entries.count : min(workbench.prefs.visibleClips, state.entries.count) }
    var body: some View {
        ZStack {
            GlassBackdrop()
            VStack(alignment: .leading, spacing: 10) {
                if state.copyConfirmation {
                    Label(workbench.text("Скопировано — вставь ⌘V", "Copied — paste with ⌘V"), systemImage: "checkmark.circle").font(.headline).padding(.vertical, 8)
                } else {
                HStack { Label(workbench.text("Быстрый буфер", "Quick clipboard"), systemImage: "clipboard").font(.headline); Spacer(); Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain) }
                HStack { Text(state.insertMode ? workbench.text("Вставить", "Paste") : workbench.text("Скопировать · затем ⌘V", "Copy · then ⌘V")).font(.caption).foregroundStyle(.secondary); Spacer(); if workbench.clipboard.paused { StatusPill(title: workbench.text("Пауза", "Paused"), symbol: "pause", color: .orange) } }
                if state.entries.isEmpty { Text(workbench.text("Скопируй текст и открой буфер снова", "Copy some text and reopen the clipboard")).font(.callout).padding(.vertical, 14) }
                else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 3) {
                                ForEach(Array(state.entries.prefix(count).enumerated()), id: \.element.id) { index, entry in
                                    Button { choose(index) } label: {
                                        HStack(spacing: 10) { Text(index < 9 ? "\(index + 1)" : "·").font(.caption.bold()).frame(width: 24, height: 27).background(GlassPalette.orange.opacity(state.selected == index ? 0.75 : 0.15), in: RoundedRectangle(cornerRadius: 8)); Image(systemName: entry.symbol).frame(width: 18); Text(entry.preview).lineLimit(1); Spacer(minLength: 0) }.font(.system(size: 13, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).background(state.selected == index ? Color.white.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 14))
                                    }.buttonStyle(.plain).id(index).onHover { if $0 { state.selected = index } }
                                }
                            }
                        }.onChange(of: state.selected) { _, index in
                            if index >= count { state.expanded = true }
                            DispatchQueue.main.async { proxy.scrollTo(index) }
                        }
                    }
                }
                if !state.expanded && state.entries.count > count { Button(workbench.text("Ещё история", "More history")) { state.expanded = true }.buttonStyle(.plain).font(.caption) }
                if workbench.clipboard.paused { Button(workbench.text("Продолжить историю", "Resume history")) { workbench.clipboard.paused = false }.font(.caption) }
                Text("1–9 · ↑↓ · Return · Esc").font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(16)
        }.clipShape(RoundedRectangle(cornerRadius: 26)).tint(GlassPalette.orange)
            .modifier(PumpkinContentColor())
            .preferredColorScheme(workbench.prefs.theme == "dark" ? .dark : workbench.prefs.theme == "light" ? .light : nil)
            .environment(\.locale, Locale(identifier: workbench.prefs.language == "en" ? "en" : "ru"))
    }
}
