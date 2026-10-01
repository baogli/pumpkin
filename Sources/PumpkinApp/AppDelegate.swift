import AppKit
import PumpkinCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var workbench: Workbench!
    private var mainWindow: WorkbenchWindow!
    private var clipboardPanel: QuickClipboardController!
    private var hotkeys: GlobalHotkeys!
    private var finishingQuit = false
    private var model: AppModel!
    private var statusController: StatusItemController!
    private var panelController: PanelController!
    private var onboarding: OnboardingWindowController?
    private var settings: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = makeMainMenu()

        let prefs = Preferences()
        model = AppModel(prefs: prefs)
        workbench = Workbench(files: model, prefs: UnifiedPreferences())
        mainWindow = WorkbenchWindow(workbench: workbench)
        clipboardPanel = QuickClipboardController(workbench: workbench)
        hotkeys = GlobalHotkeys(workbench: workbench)
        workbench.showWindow = { [weak self] in self?.mainWindow.present() }
        workbench.showQuickClipboard = { [weak self] in self?.clipboardPanel.toggle() }
        workbench.hideQuickClipboard = { [weak self] in self?.clipboardPanel.hide() }
        workbench.updateShortcuts = { [weak self] in self?.hotkeys.register() }
        model.actions = AppActions(
            showSettings: { [weak self] in self?.showSettings() },
            showOnboarding: { [weak self] in self?.showOnboarding() },
            showAbout: { [weak self] in self?.showAbout() }
        )
        statusController = StatusItemController(model: model, workbench: workbench)
        panelController = PanelController(model: model, statusItem: statusController.statusItem, workbench: workbench)
        hotkeys.register()
        if prefs.hasCompletedOnboarding { model.retryWatching() }
        if workbench.intro { mainWindow.present() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !finishingQuit, let workbench else { return .terminateNow }
        switch workbench.recorder.phase {
        case .idle: return .terminateNow
        case .monitoring:
            Task { await workbench.recorder.stopMonitor(); finishingQuit = true; sender.reply(toApplicationShouldTerminate: true) }
            return .terminateLater
        case .preparing, .countdown:
            workbench.recorder.cancel()
            Task {
                while workbench.recorder.phase != .idle { try? await Task.sleep(nanoseconds: 50_000_000) }
                finishingQuit = true; sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        case .finalizing:
            Task {
                while workbench.recorder.phase == .finalizing { try? await Task.sleep(nanoseconds: 50_000_000) }
                finishingQuit = true; sender.reply(toApplicationShouldTerminate: self.confirmQuitAfterFailure())
            }
            return .terminateLater
        case .recording:
            let alert = NSAlert()
            alert.messageText = workbench.text("Идёт запись", "Recording is in progress")
            alert.informativeText = workbench.text("Остановить и сохранить перед выходом?", "Stop and save before quitting?")
            alert.addButton(withTitle: workbench.text("Остановить и выйти", "Stop and quit"))
            alert.addButton(withTitle: workbench.text("Отмена", "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
            Task {
                await workbench.recorder.stop()
                finishingQuit = true; sender.reply(toApplicationShouldTerminate: self.confirmQuitAfterFailure())
            }
            return .terminateLater
        }
    }
    private func confirmQuitAfterFailure() -> Bool {
        guard let message = workbench.recorder.error else { return true }
        let alert = NSAlert(); alert.messageText = workbench.text("Не удалось сохранить запись", "The recording could not be saved")
        alert.informativeText = message + "\n" + workbench.text("Промежуточный файл оставлен на диске и может не открыться.", "The partial file remains on disk and may not be playable.")
        alert.addButton(withTitle: workbench.text("Выйти", "Quit")); alert.addButton(withTitle: workbench.text("Остаться", "Stay"))
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        if !confirmed { finishingQuit = false; workbench.open(.recording) }
        return confirmed
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.saveNow()
        workbench?.clipboard.setEnabled(false)
    }

    func applicationDidHide(_ notification: Notification) { workbench?.windowVisible = false; clipboardPanel?.hide(); model?.isListOpen = false }
    func applicationDidUnhide(_ notification: Notification) { workbench?.windowVisible = mainWindow?.window?.isVisible ?? false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app again from Finder or Spotlight shows the list.
        if !flag {
            mainWindow.present()
        }
        return false
    }

    // MARK: - Windows

    private func showOnboarding() { workbench.intro = true; mainWindow.present() }
    private func showSettings() { model.isListOpen = false; workbench.open(.settings) }

    private func showAbout() {
        model.isListOpen = false
        NSApp.activate()
        let credits = NSAttributedString(
            string: "Record. Paste. Keep what matters.\nScreen recording, clipboard and file expiry.\nOpen source. Everything stays on your Mac.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    return style
                }(),
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    // MARK: - Menu

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Pumpkin", action: #selector(aboutAction), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(settingsAction), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Pumpkin", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Pumpkin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        return main
    }

    @objc private func aboutAction() { showAbout() }
    @objc private func settingsAction() { showSettings() }
}

public enum PumpkinApplication {
    @MainActor
    public static func run() {
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        NSApplication.shared.run()
    }
}
