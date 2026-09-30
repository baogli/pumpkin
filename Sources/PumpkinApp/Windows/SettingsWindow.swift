import AppKit
import PumpkinCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(model: AppModel) {
        let hosting = NSHostingController(rootView: SettingsView().environment(model))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "Pumpkin Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unifiedCompact
        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func present() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.needsApproval
    @State private var loginError: String?

    var body: some View {
        @Bindable var prefs = model.prefs

        Form {
            Section("General") {
                Toggle("Open Pumpkin at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { applyLoginItem() }
                if loginNeedsApproval {
                    HStack {
                        Text("Approve Pumpkin in Login Items to finish.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { SMAppServiceHelper.openLoginItems() }
                    }
                    .font(.callout)
                }
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.orange)
                }
                Toggle("Show time left in the menu bar", isOn: $prefs.showCountdown)
                Toggle("Play a sound when moving files to the Trash", isOn: $prefs.playSound)
            }

            Section {
                Picker("Preselected time", selection: $prefs.defaultDuration) {
                    ForEach(ShelfDuration.standardStops) { duration in
                        Text(duration.longLabel).tag(duration.seconds)
                    }
                }
                Picker("If I don’t answer", selection: $prefs.unansweredPolicy) {
                    Text("Keep the file").tag(UnansweredPolicy.keep)
                    Text("Use the preselected time").tag(UnansweredPolicy.useDefault)
                }
                Picker("Tuck the question away after", selection: $prefs.promptTimeout) {
                    Text("15 seconds").tag(15.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("Never").tag(0.0)
                }
                Toggle("Ask about new folders too", isOn: $prefs.askAboutFolders)
            } header: {
                Text("New Downloads")
            } footer: {
                Text("Keyboard: ← → to pick a time, Return for Done, K to keep, Esc to dismiss.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Ask about new screenshots too", isOn: Binding(
                    get: { prefs.watchScreenshots },
                    set: { model.setWatchScreenshots($0) }
                ))
                if prefs.watchScreenshots {
                    LabeledContent("Screenshots are saved to") {
                        let folder = model.screenshotFolder ?? model.resolveScreenshotFolder()
                        HStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path))
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(model.folderName(for: folder))
                        }
                        .help(folder.path)
                    }
                }
            } header: {
                Text("Screenshots")
            } footer: {
                Text("Screenshots are recognised by the tag macOS gives them, so other files in that folder are never asked about. To save screenshots somewhere else, press ⇧⌘5 and choose Options.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Watched folder") {
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: prefs.watchedFolder.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(prefs.watchedFolderName)
                    }
                    .help(prefs.watchedFolder.path)
                }
                HStack {
                    Spacer()
                    if !prefs.isUsingDownloads {
                        Button("Use Downloads") { model.changeWatchedFolder(to: nil) }
                    }
                    Button("Change…") { chooseFolder() }
                }
            } header: {
                Text("Folder")
            } footer: {
                Text("Pumpkin only moves files that are still directly inside this folder. Move a file anywhere else — even into a subfolder — and it’s yours to keep.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Privacy") {
                    Text("Everything stays on your Mac")
                }
                LabeledContent("Version") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
                HStack {
                    Spacer()
                    Button("Show Welcome Guide") { model.actions.showOnboarding() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .tint(Brand.tint)
    }

    private func applyLoginItem() {
        do {
            try LoginItem.setEnabled(launchAtLogin)
            loginError = nil
        } catch {
            loginError = "Couldn’t change the login item: \(error.localizedDescription)"
        }
        loginNeedsApproval = LoginItem.needsApproval
        launchAtLogin = LoginItem.isEnabled || loginNeedsApproval
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Watch Folder"
        panel.message = "Choose the folder Pumpkin should watch for new files."
        panel.directoryURL = model.prefs.watchedFolder
        if panel.runModal() == .OK, let url = panel.url {
            let isDownloads = ItemLocator.canonicalPath(url) == ItemLocator.canonicalPath(Preferences.downloadsFolder)
            model.changeWatchedFolder(to: isDownloads ? nil : url)
        }
    }
}

import ServiceManagement

enum SMAppServiceHelper {
    static func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
