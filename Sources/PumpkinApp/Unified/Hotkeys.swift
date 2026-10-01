import Carbon

@MainActor
final class GlobalHotkeys {
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private let workbench: Workbench
    init(workbench: Workbench) {
        self.workbench = workbench
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr else { return result }
            let owner = Unmanaged<GlobalHotkeys>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                if id.id == 1 { owner.workbench.showQuickClipboard() }
                if id.id == 2 { owner.workbench.requestRecording() }
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register() {
        for reference in references { UnregisterEventHotKey(reference) }; references.removeAll()
        guard handler != nil else { workbench.shortcutError = workbench.text("Не удалось включить обработчик глобальных клавиш.", "Global shortcut handler could not be installed."); return }
        var errors: [String] = []
        let choices: [(Bool, GlobalShortcut, UInt32)] = [(workbench.prefs.clipboardEnabled, workbench.prefs.clipboardShortcut, 1), (workbench.prefs.recordingEnabled, workbench.prefs.recordingShortcut, 2)]
        for (enabled, shortcut, id) in choices where enabled {
            if workbench.capturingShortcut == id { continue }
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(shortcut.key, shortcut.modifiers, EventHotKeyID(signature: 0x504D504B, id: id), GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference { references.append(reference) }
            else { errors.append(workbench.text("\(shortcut.label) занята другим приложением. Выбери другую клавишу в настройках.", "\(shortcut.label) is used by another app. Choose another shortcut in Settings.")) }
        }
        workbench.shortcutError = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }
    deinit { for reference in references { UnregisterEventHotKey(reference) }; if let handler { RemoveEventHandler(handler) } }
}
