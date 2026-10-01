// Developer QA for Pumpkin.
//
//   swift run PumpkinQA [output-dir]
//
// 1. Drives the real AppModel end to end against a scratch folder and the real
//    Trash (everything it trashes is put back and the folder removed afterwards).
// 2. Checks the real drop-down panel's size and anchoring under a status item.
// 3. Renders every panel state, light and dark, to PNG for visual review.
import AppKit
import PumpkinCore
import SwiftUI
@testable import PumpkinApp

@MainActor
final class QA {
    let out: URL
    let folder: URL
    let desktop: URL
    let stateURL: URL
    let defaults: UserDefaults
    let suiteName = "PumpkinQA-\(UUID().uuidString)"
    var failures: [String] = []
    var passes = 0
    var models: [AppModel] = []

    init(out: URL) {
        self.out = out
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("PumpkinQA-\(UUID().uuidString.prefix(6))")
        folder = base.appendingPathComponent("Downloads", isDirectory: true)
        desktop = base.appendingPathComponent("Desktop", isDirectory: true)
        try! FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        stateURL = base.appendingPathComponent("state.json")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: suiteName)!
    }

    // MARK: Helpers

    func check(_ condition: Bool, _ label: String, file: StaticString = #fileID, line: UInt = #line) {
        if condition {
            passes += 1
            print("  ✓ \(label)")
        } else {
            failures.append("\(label) (\(file):\(line))")
            print("  ✘ \(label)")
        }
    }

    func waitUntil(_ timeout: TimeInterval = 6, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    @discardableResult
    func makeFile(_ name: String, bytes: Int = 2_400_000, in dir: URL? = nil) -> URL {
        let url = (dir ?? folder).appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 0x2A, count: bytes))
        return url
    }

    /// A synthetic screenshot (a drawn mock window), tagged the way macOS tags real ones.
    @discardableResult
    func makeScreenshot(_ name: String, in dir: URL? = nil, tagged: Bool = true) -> URL {
        let url = (dir ?? desktop).appendingPathComponent(name)
        let size = NSSize(width: 1440, height: 900)
        let image = NSImage(size: size, flipped: true) { rect in
            NSGradient(colors: [NSColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 1), NSColor(red: 0.75, green: 0.45, blue: 0.85, alpha: 1)])?.draw(in: rect, angle: 45)
            let window = NSRect(x: 180, y: 120, width: 1080, height: 660)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: window, xRadius: 18, yRadius: 18).fill()
            NSColor(white: 0.93, alpha: 1).setFill()
            NSRect(x: window.minX, y: window.minY + 18, width: window.width, height: 34).fill()
            for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: window.minX + 20 + CGFloat(i) * 22, y: window.minY + 22, width: 13, height: 13)).fill()
            }
            NSColor(white: 0.88, alpha: 1).setFill()
            NSRect(x: window.minX + 24, y: window.minY + 90, width: 240, height: 540).fill()
            for row in 0..<6 {
                NSColor(white: row == 1 ? 0.55 : 0.8, alpha: 1).setFill()
                NSRect(x: window.minX + 300, y: window.minY + 100 + CGFloat(row) * 60, width: row == 0 ? 520 : 700, height: 22).fill()
            }
            return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try! rep.representation(using: .png, properties: [:])!.write(to: url)
        if tagged {
            let data = try! PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
            _ = data.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, data.count, 0, 0) }
        }
        return url
    }

    func makeModel(freshState: Bool = true) -> AppModel {
        if freshState {
            try? FileManager.default.removeItem(at: stateURL)
        }
        let prefs = Preferences(defaults: defaults)
        prefs.customFolderPath = folder.path
        prefs.promptTimeout = 30
        prefs.unansweredPolicy = .keep
        prefs.playSound = false
        prefs.defaultDuration = 86_400
        prefs.watchScreenshots = true
        let model = AppModel(prefs: prefs, store: StateStore(url: stateURL))
        let desktop = self.desktop
        model.resolveScreenshotFolder = { desktop }
        models.append(model)
        return model
    }

    func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
    }

    // MARK: End to end

    func runEndToEnd() async {
        print("\n▸ End-to-end against \(folder.path)")
        makeFile("already-here.pdf")
        let model = makeModel()
        model.startWatching()
        check(model.isWatching, "watcher starts")
        await pause(2.5)
        check(model.prompts.isEmpty, "files present at launch are not asked about")

        // A download arrives.
        makeFile("Installer.dmg")
        check(await waitUntil { model.prompts.count == 1 }, "new file triggers a question")
        check(model.prompts.first?.primary.name == "Installer.dmg", "question names the file")
        check(model.prompts.first?.selectedDuration == .days(1), "preselects 1 day")
        if case .prompt? = model.scene { check(true, "panel shows the question") } else { check(false, "panel shows the question") }
        model.nudgeSelection(by: -2)
        check(model.prompts.first?.selectedDuration == .minutes(30), "arrow keys move the selection")
        let batchID = model.prompts[0].id
        model.confirm(batchID)
        check(model.items.count == 1 && model.items[0].name == "Installer.dmg", "Done starts a timer")
        check(abs(model.items[0].expiresAt.timeIntervalSinceNow - 1_800) < 5, "timer is 30 minutes")
        if case .confirmation(let confirmation)? = model.scene, case .scheduled = confirmation.kind {
            check(true, "confirmation shown")
        } else {
            check(false, "confirmation shown")
        }
        check(await waitUntil(3) { model.confirmation == nil }, "confirmation tucks itself away")

        // Time passes.
        model.expireDue(now: Date().addingTimeInterval(1_801))
        check(!exists("Installer.dmg"), "file moved out of the folder when due")
        check(model.items.isEmpty, "timer removed after trashing")
        check(model.history.first?.name == "Installer.dmg", "recorded in Recently Trashed")
        check(model.history.first?.canPutBack == true, "file is sitting in the real Trash")
        if case .toast(let toast)? = model.scene, case .trashed = toast.kind {
            check(true, "“Moved to Trash” notice shown")
        } else {
            check(false, "“Moved to Trash” notice shown")
        }

        // Put it back; it must not be asked about again.
        model.putBack([model.history[0]])
        check(exists("Installer.dmg"), "Put Back restores the file")
        check(model.history.first?.restoredAt != nil, "history marks it as put back")
        await pause(2.5)
        check(model.prompts.isEmpty, "restored file isn't treated as a new download")

        // Keep forever.
        makeFile("keep-me.zip")
        check(await waitUntil { model.prompts.count == 1 }, "second download asked about")
        model.keep(model.prompts[0].id)
        check(model.items.isEmpty, "Keep Forever sets no timer")
        if case .confirmation(let confirmation)? = model.scene, confirmation.kind == .kept {
            check(true, "“Keeping it” confirmation shown")
        } else {
            check(false, "“Keeping it” confirmation shown")
        }
        _ = await waitUntil(3) { model.confirmation == nil }

        // Several files at once become one question.
        makeFile("photo-1.jpg", bytes: 1_000)
        makeFile("photo-2.jpg", bytes: 1_000)
        makeFile("photo-3.jpg", bytes: 1_000)
        check(await waitUntil { model.prompts.first?.items.count == 3 }, "three files arriving together make one question")
        check(model.prompts.count == 1, "only one question queued")
        model.confirm(model.prompts[0].id)
        check(model.items.count == 3, "one Done sets three timers")
        _ = await waitUntil(3) { model.confirmation == nil }

        // Rename in place: timer follows the file.
        let photo1 = model.items.first { $0.name == "photo-1.jpg" }!
        try? FileManager.default.moveItem(at: folder.appendingPathComponent("photo-1.jpg"), to: folder.appendingPathComponent("Holiday.jpg"))
        check(await waitUntil { model.items.contains { $0.id == photo1.id && $0.name == "Holiday.jpg" } }, "renamed file keeps its timer under the new name")

        // Moved into a subfolder: Pumpkin lets it go.
        let sub = folder.appendingPathComponent("Sorted", isDirectory: true)
        try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let photo2 = model.items.first { $0.name == "photo-2.jpg" }!
        try? FileManager.default.moveItem(at: folder.appendingPathComponent("photo-2.jpg"), to: sub.appendingPathComponent("photo-2.jpg"))
        check(await waitUntil { !model.items.contains { $0.id == photo2.id } }, "file moved to a subfolder drops its timer")
        // Answer the question about the new "Sorted" folder so it doesn't linger.
        if await waitUntil(4, { !model.prompts.isEmpty }) {
            check(model.prompts[0].primary.snapshot.isFolder, "new folders are asked about too")
            model.keep(model.prompts[0].id)
            _ = await waitUntil(3) { model.confirmation == nil }
        }

        // Pause freezes timers.
        model.togglePause()
        check(model.isPaused, "pause")
        model.expireDue(now: Date().addingTimeInterval(10 * 86_400))
        check(exists("Holiday.jpg") && exists("photo-3.jpg"), "nothing is trashed while paused")
        makeFile("while-paused.txt", bytes: 10)
        await pause(2.5)
        check(model.prompts.count == 1 && model.scene == nil && model.promptDeadline == nil, "paused downloads wait without showing a question or starting its timeout")
        await pause(1.0)
        let before = model.items.map(\.expiresAt)
        model.togglePause()
        let shifted = zip(before, model.items.map(\.expiresAt)).allSatisfy { $1.timeIntervalSince($0) >= 0.9 }
        check(!model.isPaused && shifted, "resuming shifts every timer by the paused time")
        if let pending = model.prompts.first {
            model.keep(pending.id)
            _ = await waitUntil(3) { model.confirmation == nil }
        }

        // Trash now + multiple expiring together produce one notice.
        model.expireDue(now: Date().addingTimeInterval(2 * 86_400))
        check(!exists("Holiday.jpg") && !exists("photo-3.jpg"), "both remaining files trashed together")
        if case .toast(let toast)? = model.scene, case .trashed(let records) = toast.kind {
            check(records.count == 2, "one notice for both files")
        } else {
            check(false, "one notice for both files")
        }

        // Chrome-style partial download.
        let partial = makeFile("Unconfirmed 81723.crdownload", bytes: 50_000)
        await pause(2.5)
        check(model.prompts.isEmpty, "in-progress .crdownload isn't asked about")
        try? FileManager.default.moveItem(at: partial, to: folder.appendingPathComponent("slides.key"))
        check(await waitUntil { model.prompts.first?.primary.name == "slides.key" }, "finished download asked about under its final name")

        // Unanswered question with "keep" policy.
        model.prefs.promptTimeout = 1
        model.isPointerInside = true
        model.isPointerInside = false
        check(await waitUntil(3) { model.prompts.isEmpty }, "unanswered question tucks itself away")
        check(!model.items.contains { $0.name == "slides.key" }, "…and keeps the file by default")

        // Unanswered with "use preselected time" policy.
        model.prefs.unansweredPolicy = .useDefault
        makeFile("notes.md", bytes: 500)
        check(await waitUntil { model.items.contains { $0.name == "notes.md" } }, "unanswered question uses the preselected time when set to")
        check(abs((model.items.first { $0.name == "notes.md" }?.expiresAt.timeIntervalSinceNow ?? 0) - 86_400) < 10, "…which is 1 day")
        model.prefs.promptTimeout = 30
        model.prefs.unansweredPolicy = .keep
        _ = await waitUntil(3) { model.confirmation == nil }

        // Persistence and "while you were away".
        model.saveNow()
        let trackedCount = model.items.count
        await pause(1.1)
        makeFile("arrived-while-quit.pdf", bytes: 100)
        let relaunched = makeModel(freshState: false)
        check(relaunched.items.count == trackedCount, "timers survive a relaunch")
        relaunched.startWatching()
        check(await waitUntil { relaunched.prompts.first?.primary.name == "arrived-while-quit.pdf" }, "downloads that arrived while quit are asked about on launch")
        relaunched.keep(relaunched.prompts[0].id)

        // Onboarding sample: the whole loop in real time.
        print("  … onboarding sample (waits 30 seconds in real time)")
        relaunched.dropSampleFile()
        check(await waitUntil { relaunched.prompts.contains { $0.isDemo } }, "sample file is asked about")
        let demo = relaunched.prompts.first { $0.isDemo }!
        check(demo.selectedDuration == .seconds(30), "sample question preselects 30 seconds")
        _ = await waitUntil(3) { relaunched.confirmation == nil }
        relaunched.confirm(demo.id)
        if case .scheduled = relaunched.demoStatus { check(true, "sample scheduled") } else { check(false, "sample scheduled") }
        check(await waitUntil(40) { relaunched.demoStatus == .trashed }, "sample goes to the Trash after 30 seconds")
        check(!exists("Pumpkin Sample.txt"), "sample file is gone from the folder")

        // Screenshots.
        print("  … screenshots")
        FileManager.default.createFile(atPath: desktop.appendingPathComponent("Project Plan.key").path, contents: Data(count: 100))
        makeScreenshot("my-own-render.png", tagged: false)
        await pause(2.5)
        check(relaunched.prompts.isEmpty, "ordinary files on the Desktop are never asked about")
        makeScreenshot("Screenshot 2026-09-29 at 21.40.12.png")
        check(await waitUntil { relaunched.prompts.first?.kind == .screenshot }, "a new screenshot is asked about")
        check(relaunched.prompts.first?.primary.source == "Desktop", "question says it’s on the Desktop")
        let shot = relaunched.prompts[0]
        relaunched.select(0, in: shot.id)
        relaunched.confirm(shot.id)
        let tracked = relaunched.items.first { $0.name.hasPrefix("Screenshot 2026-09-29") }
        check(tracked.map { ItemLocator.canonicalPath($0.folderURL) == ItemLocator.canonicalPath(desktop) } ?? false, "screenshot timer belongs to the Desktop")
        relaunched.expireDue(now: Date().addingTimeInterval(601))
        check(!FileManager.default.fileExists(atPath: desktop.appendingPathComponent("Screenshot 2026-09-29 at 21.40.12.png").path), "screenshot moved to the Trash when due")
        check(FileManager.default.fileExists(atPath: desktop.appendingPathComponent("Project Plan.key").path), "other Desktop files untouched")
        if let record = relaunched.history.first, record.name.hasPrefix("Screenshot") {
            relaunched.putBack([record])
        }
        await pause(2.5)
        check(relaunched.prompts.isEmpty, "a put-back screenshot isn't asked about again")
        makeScreenshot("custom name tagged by macOS.png")
        makeScreenshot("Screenshot 2026-09-29 at 21.41.00.png")
        check(await waitUntil { relaunched.prompts.first?.items.count == 2 }, "screenshots taken together make one question, whatever their names")
        makeFile("while-screenshots.zip", bytes: 1_000)
        check(await waitUntil { relaunched.prompts.count == 2 }, "downloads and screenshots are never mixed in one question")
        check(relaunched.prompts[1].kind == .download, "…the download waits as its own question")
        relaunched.keep(relaunched.prompts[0].id)
        relaunched.keep(relaunched.prompts[0].id)
        _ = await waitUntil(3) { relaunched.confirmation == nil }
        relaunched.setWatchScreenshots(false)
        await pause(0.5)
        makeScreenshot("Screenshot 2026-09-29 at 21.42.00.png")
        await pause(2.5)
        check(relaunched.prompts.isEmpty, "turning screenshots off stops the questions")
        relaunched.setWatchScreenshots(true)
        await pause(0.5)

        // Screenshots saved straight into Downloads are asked about once, not twice.
        let sameFolder = makeModel()
        let downloads = folder
        sameFolder.resolveScreenshotFolder = { downloads }
        sameFolder.startWatching()
        makeScreenshot("Screenshot 2026-09-29 at 21.50.00.png", in: folder)
        check(await waitUntil { !sameFolder.prompts.isEmpty }, "screenshot saved into Downloads is asked about")
        await pause(2.0)
        check(sameFolder.prompts.count == 1 && sameFolder.prompts[0].items.count == 1, "…exactly once")
        sameFolder.keep(sameFolder.prompts[0].id)

        // Missing folder.
        let broken = makeModel()
        broken.prefs.customFolderPath = folder.appendingPathComponent("nope").path
        broken.startWatching()
        check(!broken.isWatching && broken.folderProblem != nil, "missing folder is reported, not crashed on")
        broken.prefs.customFolderPath = folder.path

        // Clean up the real Trash: put back everything this run trashed.
        for model in models {
            let leftovers = model.history.filter(\.canPutBack)
            if !leftovers.isEmpty {
                model.putBack(leftovers)
            }
        }
        await pause(0.3)
    }

    // MARK: Real panel geometry

    func runInteractivePanel() async {
        let model = makeModel(); model.startWatching()
        let status = StatusItemController(model: model)
        let panel = PanelController(model: model, statusItem: status.statusItem)
        model.prefs.promptTimeout = 0
        makeFile("Pumpkin Keyboard Acceptance.txt", bytes: 80)
        _ = await waitUntil { !model.prompts.isEmpty && panel.window.isVisible }
        print("INTERACTIVE PANEL READY: click a duration, use arrows, then Return. Synthetic file only.")
        let confirmed = await waitUntil(60) { !model.items.isEmpty }
        check(confirmed, "native keyboard interaction confirmed a timer")
        if let item = model.items.first { print("Confirmed duration: \(Int(item.expiresAt.timeIntervalSinceNow.rounded())) seconds") }
        NSStatusBar.system.removeStatusItem(status.statusItem)
    }

    func runPanelGeometry() async {
        print("\n▸ Panel geometry")
        let model = makeModel()
        model.startWatching()
        let status = StatusItemController(model: model)
        let panelController = PanelController(model: model, statusItem: status.statusItem)
        _ = panelController

        let panel = panelController.window
        let host = panelController.contentHost

        model.isListOpen = true
        let opened = Date()
        let didOpen = await waitUntil(3) { panel.isVisible && panel.alphaValue > 0.99 }
        print("    first open took \(Int(Date().timeIntervalSince(opened) * 1000))ms, frame \(panel.frame), status window \(String(describing: status.statusItem.button?.window?.frame))")
        await pause(0.3)
        check(didOpen, "list opens")
        let emptyHeight = panel.frame.height
        check(abs(emptyHeight - host.intrinsicContentSize.height) < 1.5, "panel height matches content (\(Int(emptyHeight))pt)")
        check(abs(panel.frame.maxY - expectedTop(status)) < 1.5, "panel hangs just below the status item (or the menu bar, if the item is hidden)")
        capture(panel: panel, name: "live-list-empty")

        model.isListOpen = false
        await pause(0.5)
        check(!panel.isVisible, "list closes")

        makeFile("Quarterly Report.pdf", bytes: 812_000)
        _ = await waitUntil { !model.prompts.isEmpty }
        await pause(0.8)
        check(panel.isVisible, "question drops down on its own")
        check(abs(panel.frame.height - host.intrinsicContentSize.height) < 1.5, "question panel height matches content (\(Int(panel.frame.height))pt)")
        let promptHeight = panel.frame.height
        capture(panel: panel, name: "live-prompt")

        model.confirm(model.prompts[0].id)
        await pause(0.8)
        check(panel.frame.height < promptHeight, "panel shrinks to the confirmation")
        check(abs(panel.frame.height - host.intrinsicContentSize.height) < 1.5, "confirmation height matches content (\(Int(panel.frame.height))pt)")
        let top = panel.frame.maxY
        capture(panel: panel, name: "live-confirmation")
        _ = await waitUntil(4) { !panel.isVisible }
        check(!panel.isVisible, "panel hides after the confirmation")

        // Real clicks and keys, delivered while this app is not active,
        // exactly like a question dropping down over a browser.
        makeFile("Receipt.pdf", bytes: 40_000)
        _ = await waitUntil { !model.prompts.isEmpty }
        await pause(0.8)
        check(!NSApp.isActive, "Pumpkin is not the active app while asking")
        do {
            click(at: stopPoint(0, in: panel), in: panel)
            await pause(0.4)
            check(model.prompts.first?.selectedDuration == .minutes(10), "clicking a stop selects it on the first click")
            check(NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier, "clicking the question doesn't steal focus from the frontmost app")
            check(panel.isKeyWindow, "the question takes keyboard input after a click")
            press(keyCode: 124, in: panel)
            press(keyCode: 124, in: panel)
            await pause(0.3)
            check(model.prompts.first?.selectedDuration == .hours(1), "→ moves along the stops")
        }
        do {
            click(at: buttonPoint(done: true, in: panel), in: panel)
            await pause(0.4)
            check(model.items.contains { $0.name == "Receipt.pdf" && abs($0.expiresAt.timeIntervalSinceNow - 3_600) < 10 }, "clicking Done sets a 1 hour timer")
        }
        _ = await waitUntil(4) { !panel.isVisible }

        makeFile("meme.gif", bytes: 9_000)
        _ = await waitUntil { !model.prompts.isEmpty }
        await pause(0.8)
        do {
            click(at: buttonPoint(done: false, in: panel), in: panel)
            await pause(0.4)
            check(model.prompts.isEmpty && !model.items.contains { $0.name == "meme.gif" }, "clicking Keep Forever keeps it")
        }
        _ = await waitUntil(4) { !panel.isVisible }

        makeFile("screenshot.png", bytes: 9_000)
        _ = await waitUntil { !model.prompts.isEmpty }
        await pause(0.8)
        do {
            click(at: stopPoint(4, in: panel), in: panel)
            await pause(0.3)
            press(keyCode: 36, in: panel)
            await pause(0.4)
            check(model.items.contains { $0.name == "screenshot.png" && abs($0.expiresAt.timeIntervalSinceNow - 7 * 86_400) < 10 }, "dragging-free click on 1w, then Return confirms")
        }
        _ = await waitUntil(4) { !panel.isVisible }

        model.isListOpen = true
        await pause(0.8)
        check(abs(panel.frame.maxY - expectedTop(status)) < 1.5 && abs(top - panel.frame.maxY) < 40, "top edge stays anchored across sizes (top \(Int(panel.frame.maxY)), expected \(Int(expectedTop(status))), earlier \(Int(top)))")
        check(abs(panel.frame.height - host.intrinsicContentSize.height) < 1.5, "list with one item fits content (\(Int(panel.frame.height))pt)")
        capture(panel: panel, name: "live-list-one")
        model.isListOpen = false
        await pause(0.4)

        status.statusItem.isVisible = false
        NSStatusBar.system.removeStatusItem(status.statusItem)
    }

    /// Centre of a slider stop on the question card (fixed metrics: 18pt padding, six columns).
    func stopPoint(_ index: Int, in panel: NSWindow) -> NSPoint {
        let column = (PanelController.width - 36) / 6
        return NSPoint(x: panel.frame.minX + 18 + column * (CGFloat(index) + 0.5), y: panel.frame.maxY - 136)
    }

    /// Centre of Done (trailing) or Keep Forever (leading) on the question card.
    func buttonPoint(done: Bool, in panel: NSWindow) -> NSPoint {
        NSPoint(x: done ? panel.frame.maxX - 48 : panel.frame.minX + 84, y: panel.frame.maxY - 200)
    }

    func click(at screenPoint: NSPoint, in window: NSWindow) {
        let point = window.convertPoint(fromScreen: screenPoint)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) {
                // Dispatch through AppKit immediately; its inactive-app event queue
                // can discard synthetic events in an automated graphical session.
                NSApp.sendEvent(event)
            }
        }
    }

    func press(keyCode: UInt16, in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode) {
                NSApp.sendEvent(event)
            }
        }
    }

    /// Where the panel's top edge belongs: 6pt under the status item, or under
    /// the menu bar when a crowded menu bar has pushed the item off screen.
    func expectedTop(_ status: StatusItemController) -> CGFloat {
        if let window = status.statusItem.button?.window, let screen = window.screen,
           screen.frame.contains(NSPoint(x: window.frame.midX, y: window.frame.midY)) {
            return min(window.frame.minY, screen.visibleFrame.maxY) - 6
        }
        return (NSScreen.main ?? NSScreen.screens[0]).visibleFrame.maxY - 6
    }

    func capture(panel: NSWindow, name: String) {
        if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(panel.windowNumber), [.boundsIgnoreFraming, .bestResolution]),
           image.width > 10 {
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("\(name).png"))
            return
        }
        guard let view = panel.contentView else { return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("\(name).png"))
    }

    // MARK: Snapshots

    func runSnapshots() async {
        print("\n▸ Snapshots → \(out.path)")
        let model = makeModel()
        model.startWatching()
        let presentation = PanelPresentation()

        func render(_ name: String) async {
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                await renderPanel(model: model, presentation: presentation, appearance: appearance, to: out.appendingPathComponent("\(name)-\(suffix).png"))
            }
        }

        presentation.scene = .list
        await render("01-list-empty")

        makeFile("TempCat (4).dmg", bytes: 2_500_000)
        _ = await waitUntil { !model.prompts.isEmpty }
        presentation.scene = model.scene ?? .list
        await render("02-prompt")

        model.select(1, in: model.prompts[0].id)
        presentation.scene = model.scene ?? .list
        await render("03-prompt-30m")

        let batch = model.prompts[0]
        model.confirm(batch.id)
        presentation.scene = model.scene ?? .list
        await render("04-confirmation")
        _ = await waitUntil(3) { model.confirmation == nil }

        makeFile("IMG_2041.HEIC", bytes: 3_100_000)
        makeFile("IMG_2042.HEIC", bytes: 2_900_000)
        makeFile("boarding-pass.pdf", bytes: 180_000)
        _ = await waitUntil { model.prompts.first?.items.count == 3 }
        presentation.scene = model.scene ?? .list
        await render("05-prompt-multiple")
        model.select(0, in: model.prompts[0].id)
        model.confirm(model.prompts[0].id)
        _ = await waitUntil(3) { model.confirmation == nil }

        makeScreenshot("Screenshot 2026-09-29 at 22.05.31.png")
        _ = await waitUntil { model.prompts.first?.kind == .screenshot }
        await pause(0.8)
        presentation.scene = model.scene ?? .list
        await render("05b-prompt-screenshot")
        model.select(2, in: model.prompts[0].id)
        model.confirm(model.prompts[0].id)
        _ = await waitUntil(3) { model.confirmation == nil }

        makeFile("Zoom Recording.mp4", bytes: 48_000_000)
        _ = await waitUntil { !model.prompts.isEmpty }
        model.select(4, in: model.prompts[0].id)
        model.confirm(model.prompts[0].id)
        _ = await waitUntil(3) { model.confirmation == nil }

        // One file is nearly due: 40 seconds left.
        if let first = model.items.first(where: { $0.name.hasPrefix("IMG_2041") }) {
            model.setTimer(for: first.id, to: .seconds(40))
        }
        model.expireDue(now: Date().addingTimeInterval(700))
        presentation.scene = model.scene ?? .list
        await render("06-toast-trashed")
        model.dismissToast()

        makeFile("contract-final-v3.docx", bytes: 96_000)
        _ = await waitUntil { !model.prompts.isEmpty }
        model.isListOpen = true
        presentation.scene = .list
        await render("07-list-with-question")
        model.keep(model.prompts[0].id)
        _ = await waitUntil(1) { true }

        presentation.scene = .list
        await render("08-list")

        model.togglePause()
        presentation.scene = .list
        await render("09-list-paused")
        model.togglePause()

        model.isListOpen = false
        for record in model.history where record.canPutBack {
            model.putBack([record])
            break
        }
        presentation.scene = model.scene ?? .list
        await render("10-toast-restored")

        // Onboarding and Settings windows.
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for step in 0..<4 {
                await renderWindowContent(OnboardingView(startAt: step, onFinish: { _ in }).environment(model), appearance: appearance, to: out.appendingPathComponent("2\(step)-onboarding-\(suffix).png"))
            }
            await renderWindowContent(SettingsView().environment(model), appearance: appearance, to: out.appendingPathComponent("30-settings-\(suffix).png"))
        }

        // Menu bar glyphs.
        let glyphs: [(String, NSImage)] = [
            ("idle", StatusIcon.image(fraction: nil, paused: false, asking: false)),
            ("75", StatusIcon.image(fraction: 0.75, paused: false, asking: false)),
            ("30", StatusIcon.image(fraction: 0.3, paused: false, asking: false)),
            ("paused", StatusIcon.image(fraction: 0.5, paused: true, asking: false)),
        ]
        let strip = NSImage(size: NSSize(width: 18 * 4 + 12 * 5, height: 30), flipped: false) { rect in
            NSColor(white: 0.93, alpha: 1).setFill()
            rect.fill()
            for (index, glyph) in glyphs.enumerated() {
                glyph.1.draw(in: NSRect(x: 12 + CGFloat(index) * 30, y: 6, width: 18, height: 18))
            }
            return true
        }
        writePNG(strip, scale: 4, to: out.appendingPathComponent("40-menubar-glyphs.png"))

        for record in model.history where record.canPutBack {
            model.putBack([record])
        }
    }

    func renderPanel(model: AppModel, presentation: PanelPresentation, appearance: NSAppearance.Name, to url: URL) async {
        let host = PanelHostingView(rootView: AnyView(PanelRootView(presentation: presentation).environment(model)))
        host.sizingOptions = [.intrinsicContentSize]
        host.appearance = NSAppearance(named: appearance)
        host.frame = NSRect(x: 0, y: 0, width: PanelController.width, height: 400)
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: PanelController.width + 48, height: 800), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        let backdrop = Backdrop(frame: window.contentView!.bounds, dark: appearance == .darkAqua)
        window.contentView = backdrop
        backdrop.addSubview(host)
        window.orderFrontRegardless()
        await pause(0.45)
        host.layoutSubtreeIfNeeded()
        let height = ceil(host.intrinsicContentSize.height)
        window.setContentSize(NSSize(width: PanelController.width + 48, height: height + 48))
        backdrop.frame = window.contentView!.bounds
        host.frame = NSRect(x: 24, y: 24, width: PanelController.width, height: height)
        backdrop.panelRect = host.frame
        await pause(0.35)
        writeView(backdrop, to: url)
        window.orderOut(nil)
    }

    func renderWindowContent<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL) async {
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.titlebarAppearsTransparent = true
        let background = WindowBackground(frame: NSRect(origin: .zero, size: size))
        host.frame = background.bounds
        host.autoresizingMask = [.width, .height]
        background.addSubview(host)
        window.contentView = background
        window.orderFrontRegardless()
        await pause(1.2)
        background.layoutSubtreeIfNeeded()
        background.display()
        if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]),
           image.width > 10 {
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
        } else {
            writeView(background, to: url)
        }
        window.orderOut(nil)
    }

    func writeView(_ view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if isMostlyBlank(rep), let layered = renderLayers(of: view) {
            try? layered.representation(using: .png, properties: [:])?.write(to: url)
            return
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// Some AppKit-backed SwiftUI views (grouped forms) only exist as layers.
    func renderLayers(of view: NSView) -> NSBitmapImageRep? {
        guard let layer = view.layer else { return nil }
        let scale = view.window?.backingScaleFactor ?? 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * scale), pixelsHigh: Int(view.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        guard let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { return nil }
        context.scaleBy(x: scale, y: scale)
        if !layer.isGeometryFlipped && !view.isFlipped {
            context.translateBy(x: 0, y: view.bounds.height)
            context.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context)
        return rep
    }

    func isMostlyBlank(_ rep: NSBitmapImageRep) -> Bool {
        var colors = Set<Int>()
        for y in stride(from: 0, to: rep.pixelsHigh, by: max(1, rep.pixelsHigh / 40)) {
            for x in stride(from: 0, to: rep.pixelsWide, by: max(1, rep.pixelsWide / 40)) {
                if let c = rep.colorAt(x: x, y: y) {
                    colors.insert(Int(c.redComponent * 20) * 441 + Int(c.greenComponent * 20) * 21 + Int(c.blueComponent * 20))
                }
            }
        }
        return colors.count < 4
    }

    func writePNG(_ image: NSImage, scale: CGFloat, to url: URL) {
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    func finish() {
        for model in models {
            model.saveNow()
        }
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
        defaults.removePersistentDomain(forName: suiteName)
        let plist = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: plist)
        print("\n\(failures.isEmpty ? "✓" : "✘") \(passes) checks passed, \(failures.count) failed")
        for failure in failures {
            print("  ✘ \(failure)")
        }
    }
}

/// The window background, which offscreen captures of a content view leave out.
final class WindowBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}

/// Stand-in for the desktop and the glass material, which offscreen rendering can't capture.
final class Backdrop: NSView {
    let dark: Bool
    var panelRect: NSRect = .zero

    init(frame: NSRect, dark: Bool) {
        self.dark = dark
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let colors = dark
            ? [NSColor(red: 0.16, green: 0.10, blue: 0.30, alpha: 1), NSColor(red: 0.36, green: 0.12, blue: 0.34, alpha: 1)]
            : [NSColor(red: 0.93, green: 0.70, blue: 0.86, alpha: 1), NSColor(red: 0.62, green: 0.72, blue: 0.95, alpha: 1)]
        NSGradient(colors: colors)?.draw(in: bounds, angle: -60)
        guard panelRect != .zero else { return }
        let shape = NSBezierPath(roundedRect: panelRect, xRadius: PanelController.cornerRadius, yRadius: PanelController.cornerRadius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.set()
        (dark ? NSColor(white: 0.13, alpha: 0.86) : NSColor(white: 0.985, alpha: 0.86)).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(dark ? 0.12 : 0.6).setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }
}

extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let match = subview.firstDescendant(of: type) { return match }
        }
        return nil
    }
}

@MainActor
final class QADelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        let path = args.dropFirst().first { !$0.hasPrefix("--") } ?? "qa-output"
        let out = URL(fileURLWithPath: path, isDirectory: true)
        let qa = QA(out: out)
        let snapshotsOnly = args.contains("--snapshots-only")
        let panelsOnly = args.contains("--panels-only")
        Task { @MainActor in
            if args.contains("--interactive-panel") || Bundle.main.bundleIdentifier == "app.pumpkin.QANative" {
                await qa.runInteractivePanel(); qa.finish(); exit(qa.failures.isEmpty ? 0 : 1)
            }
            if !snapshotsOnly {
                if !panelsOnly { await qa.runEndToEnd() }
                await qa.runPanelGeometry()
            }
            if !panelsOnly { await qa.runSnapshots() }
            qa.finish()
            exit(qa.failures.isEmpty ? 0 : 1)
        }
    }
}

setvbuf(stdout, nil, _IONBF, 0)

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = QADelegate()
    app.delegate = delegate
    app.run()
}
