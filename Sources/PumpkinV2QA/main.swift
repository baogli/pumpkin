import AppKit
import Carbon
import SwiftUI
import PumpkinCore
@testable import PumpkinApp

@MainActor final class V2QA: NSObject, NSApplicationDelegate {
    var controller: WorkbenchWindow?
    func snapshot(_ window: NSWindow, _ name: String, in output: URL, content: NSView? = nil) throws {
        guard let view = content ?? window.contentView else { throw RecorderError(message: "Window missing") }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds), view.bounds.width > 10, view.bounds.height > 10 else { throw RecorderError(message: "Invalid panel geometry") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw RecorderError(message: "Snapshot failed") }
        try data.write(to: output.appendingPathComponent(name + ".png"))
    }
    func key(_ code: UInt16, text: String = "", in window: NSWindow) {
        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code) { NSApp.sendEvent(event) }
    }
    func checkExclusiveHotkey(_ workbench: Workbench, in scratch: URL) async throws {
        let ready = scratch.appendingPathComponent("hotkey-ready")
        let child = Process(); child.executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--hold-hotkey", ready.path]; child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
        try child.run()
        defer { if child.isRunning { child.terminate() } }
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: ready.path), child.isRunning, Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        guard (try? String(contentsOf: ready, encoding: .utf8)) == "0" else { throw RecorderError(message: "External hotkey fixture did not start") }
        workbench.prefs.recordingEnabled = false
        workbench.prefs.clipboardShortcut = GlobalShortcut(key: UInt32(kVK_F19), modifiers: UInt32(controlKey | cmdKey | optionKey | shiftKey))
        let hotkeys = GlobalHotkeys(workbench: workbench); hotkeys.register()
        if hotkeys.registeredIDs == [1], workbench.shortcutError == nil {
            // Some macOS versions let an exclusive registration replace shared
            // delivery. Prove that a second process cannot also own it exclusively.
            try Data().write(to: ready.appendingPathExtension("probe"))
            let probe = ready.appendingPathExtension("exclusive"), limit = Date().addingTimeInterval(3)
            while !FileManager.default.fileExists(atPath: probe.path), Date() < limit { try await Task.sleep(nanoseconds: 50_000_000) }
            guard let result = try? String(contentsOf: probe, encoding: .utf8), Int32(result) == OSStatus(eventHotKeyExistsErr) else { throw RecorderError(message: "Second process did not report an exclusive shortcut conflict") }
        } else {
            guard hotkeys.registeredIDs.isEmpty, workbench.shortcutError != nil else { throw RecorderError(message: "Shared shortcut neither became exclusive nor reported a conflict") }
        }
        child.terminate()
        let exitDeadline = Date().addingTimeInterval(3)
        while child.isRunning, Date() < exitDeadline { try await Task.sleep(nanoseconds: 50_000_000) }
        guard !child.isRunning else { throw RecorderError(message: "Hotkey fixture did not exit") }
        hotkeys.register()
        guard hotkeys.registeredIDs == [1], workbench.shortcutError == nil else { throw RecorderError(message: "Exclusive shortcut did not recover after owner quit") }
        workbench.prefs.clipboardEnabled = false; hotkeys.register()
        print("Cross-process hotkey QA PASSED: exclusive ownership against another process; retry after its exit.")
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            NSApplication.shared.applicationIconImage = NSImage(contentsOfFile: "Resources/AppIcon.icns")
            let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/PumpkinV2QA", isDirectory: true)
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("PumpkinV2QA-\(UUID().uuidString)")
            let suite = "PumpkinV2QA-\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
            let board = NSPasteboard(name: .init(suite))
            defer { defaults.removePersistentDomain(forName: suite); board.releaseGlobally(); try? FileManager.default.removeItem(at: scratch) }
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                defaults.set(false, forKey: "watchScreenshots"); defaults.set(false, forKey: "playSound"); defaults.set(false, forKey: "watchDownloads")
                defaults.set(true, forKey: "v2.completedIntro"); defaults.set(true, forKey: "v2.clipboardEnabled")
                let prefs = Preferences(defaults: defaults); prefs.customFolderPath = scratch.path
                let files = AppModel(prefs: prefs, store: StateStore(url: scratch.appendingPathComponent("state.json")))
                let recorder = RecorderModel(files: files, defaults: defaults, deviceProvider: { [InputDevice(id: 100, uid: "demo", name: "USB Audio Interface", channels: 12, rate: 48000)] }, displayProvider: {
                    [DisplayChoice(id: 1, name: "Built-in Display", width: 3024, height: 1964, isMain: true), DisplayChoice(id: 2, name: "External Display", width: 3840, height: 2160, isMain: false)]
                })
                recorder.options.displayID = 2; recorder.options.withAudio = true; recorder.options.deviceUID = "demo"; recorder.options.left = 11; recorder.options.right = 12; recorder.options.channelsConfirmed = true
                let history = ClipboardHistory(pasteboard: board)
                let workbench = Workbench(files: files, prefs: UnifiedPreferences(defaults: defaults), clipboard: history, recorder: recorder)
                for text in ["Готово! 🎃", "Список\nна сегодня\nбез спешки", "hello@example.com", "const greeting = \"Hello, Pumpkin\";", "Забрать прошлый фрагмент текста", "https://example.com/pumpkin"] { board.clearContents(); board.setString(text, forType: .string); history.poll() }
                let pending = scratch.appendingPathComponent("demo-notes.pdf"); try Data("Synthetic demo document".utf8).write(to: pending)
                files.handleNewItems([FolderScanner.snapshot(of: pending)!], kind: .download)
                let video = scratch.appendingPathComponent("Recording-demo.mp4"); try Data("UI fixture only; not a video".utf8).write(to: video)
                let id = try files.beginRecording(url: video, screen: "External Display", audio: "USB Audio Interface · 11 / 12", format: "1080p · 30 fps · H.264"); files.finishRecording(id, duration: 42)
                controller = WorkbenchWindow(workbench: workbench)
                workbench.showWindow = { [weak self] in self?.controller?.present() }
                var checks = 0
                for theme in ["light", "dark"] {
                    workbench.prefs.theme = theme
                    for section in [WorkspaceSection.recording, .clipboard, .cleanup, .settings, .access] {
                        workbench.section = section; controller?.present()
                        try await Task.sleep(nanoseconds: 450_000_000)
                        guard let window = controller?.window, let view = window.contentView else { throw RecorderError(message: "Window missing") }
                        view.layoutSubtreeIfNeeded()
                        guard view.bounds.width >= 760 && view.bounds.height >= 600, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw RecorderError(message: "Window has invalid layout") }
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(section.rawValue)-\(theme).png"))
                        checks += 1
                    }
                }
                workbench.section = .recording; controller?.window?.setContentSize(NSSize(width: 760, height: 600)); controller?.present()
                try await Task.sleep(nanoseconds: 400_000_000)
                if let view = controller?.window?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) { view.cacheDisplay(in: view.bounds, to: bitmap); try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("recording-minimum.png")); checks += 1 }
                workbench.intro = true; controller?.window?.setContentSize(NSSize(width: 920, height: 700)); controller?.present()
                try await Task.sleep(nanoseconds: 400_000_000)
                if let view = controller?.window?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) { view.cacheDisplay(in: view.bounds, to: bitmap); try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("welcome.png")); checks += 1 }
                workbench.intro = false; workbench.prefs.language = "en"; workbench.section = .recording; controller?.present()
                try await Task.sleep(nanoseconds: 350_000_000)
                try snapshot(controller!.window!, "recording-english", in: output); checks += 1
                workbench.prefs.language = "ru"; controller?.window?.orderOut(nil); workbench.windowVisible = false
                let status = StatusItemController(model: files, workbench: workbench)
                let panels = PanelController(model: files, statusItem: status.statusItem, workbench: workbench, observeOutsideEvents: false)
                files.isListOpen = true
                try await Task.sleep(nanoseconds: 600_000_000)
                guard panels.window.isVisible else { throw RecorderError(message: "Unified menu did not appear") }
                try snapshot(panels.window, "menu", in: output, content: panels.contentHost); checks += 1
                panels.window.makeKey(); key(36, in: panels.window)
                guard files.items.isEmpty, files.prompts.count == 1 else { throw RecorderError(message: "Menu Return changed hidden questions: items=\(files.items.count), pending=\(files.prompts.count), list=\(files.isListOpen), main=\(workbench.windowVisible)") }
                files.isListOpen = false
                try await Task.sleep(nanoseconds: 600_000_000)
                guard files.promptDeadline != nil, panels.window.isVisible else { throw RecorderError(message: "Pending question not resumed") }
                try snapshot(panels.window, "expiry-prompt", in: output, content: panels.contentHost); checks += 1
                panels.window.makeKey(); key(124, in: panels.window)
                let selected = files.prompts[0].selectedDuration
                key(36, in: panels.window)
                guard files.prompts.isEmpty, files.items.count == 1, abs(files.items[0].remaining(at: Date()) - selected.seconds) < 3 else { throw RecorderError(message: "Prompt arrows / Return did not confirm one timer") }
                try await Task.sleep(nanoseconds: 400_000_000)
                try snapshot(panels.window, "expiry-confirmation", in: output, content: panels.contentHost); checks += 1
                let quick = QuickClipboardController(workbench: workbench, accessibilityTrusted: { false }, observeOutsideClicks: false)
                workbench.hideQuickClipboard = { quick.hide() }
                workbench.section = .clipboard; controller?.present()
                NSApp.activate(); quick.toggle()
                try await Task.sleep(nanoseconds: 400_000_000)
                guard quick.visible, !workbench.windowVisible, controller?.window?.isVisible == false, files.automaticPanelsSuppressed, files.scene == nil else { throw RecorderError(message: "Clipboard priority: popup=\(quick.visible), main=\(workbench.windowVisible), nativeMain=\(controller?.window?.isVisible == true), suppressed=\(files.automaticPanelsSuppressed)") }
                try snapshot(quick.window, "quick-clipboard", in: output); checks += 1
                let intended = history.entries[1].text
                key(125, in: quick.window)
                board.clearContents(); board.setString("A newer synthetic copy", forType: .string); history.poll()
                key(36, in: quick.window)
                guard board.string(forType: .string) == intended else { throw RecorderError(message: "A live history update changed the selected quick clipboard item") }
                try snapshot(quick.window, "clipboard-copied", in: output); checks += 1
                try await Task.sleep(nanoseconds: 250_000_000)
                quick.hide(); quick.toggle(); key(36, in: quick.window)
                try await Task.sleep(nanoseconds: 700_000_000)
                guard quick.visible else { throw RecorderError(message: "An old confirmation timer closed a newer clipboard presentation") }
                try await Task.sleep(nanoseconds: 300_000_000)
                guard !quick.visible else { throw RecorderError(message: "Copy confirmation did not expire") }
                quick.hide(); quick.toggle(); key(53, in: quick.window)
                guard !quick.visible, !workbench.clipboardVisible else { throw RecorderError(message: "Escape did not close quick clipboard") }
                quick.toggle(); workbench.open(.cleanup)
                guard !quick.visible, controller?.window?.isVisible == true else { throw RecorderError(message: "Opening main workspace must dismiss transient clipboard") }
                quick.toggle(); workbench.setClipboardEnabled(false)
                guard !quick.visible, history.entries.isEmpty, !workbench.clipboardVisible else { throw RecorderError(message: "Disabling clipboard did not dismiss its retained history") }
                workbench.setClipboardEnabled(true)
                quick.toggle(); key(125, in: quick.window); key(36, in: quick.window); key(53, in: quick.window)
                guard !quick.visible else { throw RecorderError(message: "Empty clipboard keyboard handling failed") }
                try await checkExclusiveHotkey(workbench, in: scratch)
                history.setEnabled(false); controller?.window?.orderOut(nil)
                NSStatusBar.system.removeStatusItem(status.statusItem)
                print("V2 UI QA PASSED: \(checks) layouts / snapshots; single clipboard window, stable selection during capture, repeated copy confirmation, disable, empty keyboard input, menu/prompt priority and cross-process exclusive hotkeys. All data synthetic; device list injected. No live recording performed.")
                exit(0)
            } catch { fputs("V2 UI QA FAILED: \(error.localizedDescription)\n", stderr); exit(1) }
        }
    }
}
setvbuf(stdout, nil, _IONBF, 0)
if CommandLine.arguments.dropFirst().first == "--hold-hotkey" {
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        var reference: EventHotKeyRef?
        let result = RegisterEventHotKey(UInt32(kVK_F19), UInt32(controlKey | cmdKey | optionKey | shiftKey), EventHotKeyID(signature: 0x5141484B, id: 99), GetApplicationEventTarget(), 0, &reference)
        let ready = URL(fileURLWithPath: CommandLine.arguments[2])
        try? Data("\(result)".utf8).write(to: ready)
        let timer = Timer(timeInterval: 0.05, repeats: true) { timer in
            guard FileManager.default.fileExists(atPath: ready.appendingPathExtension("probe").path) else { return }
            timer.invalidate()
            if let reference { UnregisterEventHotKey(reference) }
            reference = nil
            let probe = RegisterEventHotKey(UInt32(kVK_F19), UInt32(controlKey | cmdKey | optionKey | shiftKey), EventHotKeyID(signature: 0x5141484B, id: 99), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
            try? Data("\(probe)".utf8).write(to: ready.appendingPathExtension("exclusive"))
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.run()
    }
    exit(0)
}
MainActor.assumeIsolated { let app = NSApplication.shared; app.setActivationPolicy(.accessory); let delegate = V2QA(); app.delegate = delegate; app.run() }
