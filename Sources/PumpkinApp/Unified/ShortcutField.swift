import AppKit
import Carbon
import SwiftUI

struct ShortcutField: NSViewRepresentable {
    @Binding var value: GlobalShortcut
    var workbench: Workbench
    var id: UInt32
    func makeNSView(context: Context) -> ShortcutControl {
        let control = ShortcutControl(); control.bezelStyle = .rounded; control.title = value.label
        control.target = control; control.action = #selector(ShortcutControl.begin)
        control.setAccessibilityLabel(workbench.text("Изменить горячую клавишу", "Change shortcut"))
        control.onStart = { workbench.capturingShortcut = id; workbench.updateShortcuts() }
        control.onFinish = { shortcut in
            if let shortcut { value = shortcut }
            workbench.capturingShortcut = nil; workbench.updateShortcuts()
        }
        control.prompt = workbench.text("Нажми сочетание… Esc — отмена", "Press shortcut… Esc cancels")
        return control
    }
    func updateNSView(_ control: ShortcutControl, context: Context) { control.savedLabel = value.label; if !control.capturing { control.title = value.label } }
    static func dismantleNSView(_ control: ShortcutControl, coordinator: ()) { control.finish(nil) }
}

final class ShortcutControl: NSButton {
    var savedLabel = ""
    var prompt = "Press shortcut…"
    var onStart: () -> Void = {}
    var onFinish: (GlobalShortcut?) -> Void = { _ in }
    private(set) var capturing = false
    private var monitor: Any?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { begin() }
    @objc func begin() {
        guard !capturing else { return }
        capturing = true; title = prompt; window?.makeFirstResponder(self); onStart()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.capturing, event.window === self.window else { return event }
            self.keyDown(with: event); return nil
        }
    }
    override func keyDown(with event: NSEvent) {
        guard capturing else { super.keyDown(with: event); return }
        if event.keyCode == 53 { finish(nil); return }
        let flags = event.modifierFlags
        guard !flags.intersection([.control, .option, .command]).isEmpty else { NSSound.beep(); return }
        let reserved: Set<UInt16> = [UInt16(kVK_ANSI_Q), UInt16(kVK_ANSI_C), UInt16(kVK_ANSI_V), UInt16(kVK_ANSI_X), UInt16(kVK_ANSI_A), UInt16(kVK_ANSI_Z), UInt16(kVK_ANSI_H), UInt16(kVK_ANSI_M), UInt16(kVK_ANSI_W), UInt16(kVK_ANSI_Comma)]
        if flags.intersection([.command, .control, .option, .shift]) == .command && reserved.contains(event.keyCode) { NSSound.beep(); return }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let raw = event.charactersIgnoringModifiers?.uppercased()
        let printable = raw.flatMap { $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 } ? $0 : nil }
        finish(GlobalShortcut(key: UInt32(event.keyCode), modifiers: modifiers, character: printable))
    }
    func finish(_ shortcut: GlobalShortcut?) {
        guard capturing else { return }
        capturing = false; title = savedLabel
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        onFinish(shortcut)
    }
    override func resignFirstResponder() -> Bool { finish(nil); return super.resignFirstResponder() }
}
