import AppKit
import PumpkinCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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
        model.actions = AppActions(
            showSettings: { [weak self] in self?.showSettings() },
            showOnboarding: { [weak self] in self?.showOnboarding() },
            showAbout: { [weak self] in self?.showAbout() }
        )
        statusController = StatusItemController(model: model)
        panelController = PanelController(model: model, statusItem: statusController.statusItem)

        if prefs.hasCompletedOnboarding {
            model.retryWatching()
        } else {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.saveNow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app again from Finder or Spotlight shows the list.
        if !flag {
            model.isListOpen = true
        }
        return false
    }

    // MARK: - Windows

    private func showOnboarding() {
        model.isListOpen = false
        if onboarding == nil {
            onboarding = OnboardingWindowController(
                model: model,
                onFinish: { [weak self] launchAtLogin in
                    self?.finishOnboarding(launchAtLogin: launchAtLogin)
                },
                onClose: { [weak self] in
                    self?.onboardingClosed()
                }
            )
        }
        onboarding?.present()
    }

    private func finishOnboarding(launchAtLogin: Bool) {
        model.prefs.hasCompletedOnboarding = true
        try? LoginItem.setEnabled(launchAtLogin)
        // Show where Pumpkin lives.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.model.isListOpen = true
        }
    }

    private func onboardingClosed() {
        onboarding = nil
        if !model.isWatching {
            model.retryWatching()
        }
    }

    private func showSettings() {
        model.isListOpen = false
        if settings == nil {
            settings = SettingsWindowController(model: model)
        }
        settings?.present()
    }

    private func showAbout() {
        model.isListOpen = false
        NSApp.activate()
        let credits = NSAttributedString(
            string: "Every file gets its midnight.\nDownloads and screenshots, tidied on your schedule.\nOpen source. Everything stays on your Mac.",
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
