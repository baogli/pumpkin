import AppKit
import Carbon

@MainActor
final class GlobalHotkeys {
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var terminationObserver: NSObjectProtocol?
    private let workbench: Workbench
    private(set) var registeredIDs: Set<UInt32> = []
    init(workbench: Workbench) {
        self.workbench = workbench
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr else { return result }
            guard id.signature == 0x504D504B, id.id == 1 || id.id == 2 else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalHotkeys>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                if id.id == 1 { owner.workbench.showQuickClipboard() }
                if id.id == 2 { owner.workbench.requestRecording() }
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.workbench.shortcutError != nil { self?.register() } }
        }
    }
    func register() {
        for reference in references { UnregisterEventHotKey(reference) }; references.removeAll(); registeredIDs.removeAll()
        guard handler != nil else { workbench.shortcutError = workbench.text("Не удалось включить обработчик глобальных клавиш.", "Global shortcut handler could not be installed."); return }
        var errors: [String] = []
        let choices: [(Bool, GlobalShortcut, UInt32)] = [(workbench.prefs.clipboardEnabled, workbench.prefs.clipboardShortcut, 1), (workbench.prefs.recordingEnabled, workbench.prefs.recordingShortcut, 2)]
        let duplicate = choices[0].0 && choices[1].0 && choices[0].1.key == choices[1].1.key && choices[0].1.modifiers == choices[1].1.modifiers
        if duplicate {
            workbench.shortcutError = workbench.text("У буфера и записи одинаковая клавиша. Выбери разные сочетания в настройках.", "Clipboard and recording share a shortcut. Choose different shortcuts in Settings.")
            return
        }
        for (enabled, shortcut, id) in choices where enabled {
            if workbench.capturingShortcut == id { continue }
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(shortcut.key, shortcut.modifiers, EventHotKeyID(signature: 0x504D504B, id: id), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
            if result == noErr, let reference { references.append(reference); registeredIDs.insert(id) }
            else if result == OSStatus(eventHotKeyExistsErr) { errors.append(workbench.text("\(shortcut.label) занята другим приложением. Закрой его или выбери другую клавишу в настройках.", "\(shortcut.label) is used by another app. Close it or choose another shortcut in Settings.")) }
            else { errors.append(workbench.text("Не удалось включить \(shortcut.label) (\(result)). Выбери другую клавишу в настройках.", "Could not enable \(shortcut.label) (\(result)). Choose another shortcut in Settings.")) }
        }
        workbench.shortcutError = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }
    deinit {
        for reference in references { UnregisterEventHotKey(reference) }; if let handler { RemoveEventHandler(handler) }
        if let terminationObserver { NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver) }
    }
}
