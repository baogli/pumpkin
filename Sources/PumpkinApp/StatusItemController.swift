import AppKit
import PumpkinCore

/// Draws the menu bar glyph: a ring that drains as the next file's time runs out,
/// around a pumpkin (or pause bars while paused).
enum StatusIcon {
    static func image(fraction: Double?, paused: Bool, asking: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 7.3

            let ring = NSBezierPath()
            ring.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            ring.lineWidth = 1.5

            if let fraction, !asking {
                NSColor.black.withAlphaComponent(0.3).setStroke()
                ring.stroke()
                let arc = NSBezierPath()
                arc.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: 90,
                    endAngle: 90 - 360 * CGFloat(max(0.03, min(1, fraction))),
                    clockwise: true
                )
                arc.lineWidth = 1.9
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            } else {
                NSColor.black.setStroke()
                ring.stroke()
            }

            NSColor.black.set()
            if paused {
                for dx in [-1.9, 1.9] {
                    let bar = NSBezierPath(roundedRect: NSRect(x: center.x + dx - 0.85, y: center.y - 3.2, width: 1.7, height: 6.4), xRadius: 0.85, yRadius: 0.85)
                    bar.fill()
                }
            } else {
                // Three lobes and a stem stay legible at menu bar size.
                for dx in [-2.1, 0.0, 2.1] {
                    NSBezierPath(ovalIn: NSRect(x: center.x + dx - 2.0, y: center.y - 3.5, width: 4.0, height: 6.0)).fill()
                }
                let stem = NSBezierPath()
                stem.move(to: NSPoint(x: center.x, y: center.y + 2.0))
                stem.curve(to: NSPoint(x: center.x + 1.2, y: center.y + 4.4), controlPoint1: NSPoint(x: center.x - 0.4, y: center.y + 3.0), controlPoint2: NSPoint(x: center.x + 0.2, y: center.y + 4.1))
                stem.lineWidth = 1.3
                stem.lineCapStyle = .round
                stem.stroke()
                NSColor.clear.setFill()

            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Pumpkin"
        return image
    }
}

@MainActor
final class StatusItemController: NSObject {
    let statusItem: NSStatusItem
    private let model: AppModel
    private let workbench: Workbench?
    private var tickTimer: Timer?
    private var tickInterval: TimeInterval = 0

    init(model: AppModel, workbench: Workbench? = nil) {
        self.model = model
        self.workbench = workbench
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.autosaveName = "Pumpkin"
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Pumpkin")
        }

        observeContinuously { [weak self] in
            self?.refresh()
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if workbench == nil && (event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true) {
            showMenu()
        } else {
            workbench?.hideQuickClipboard()
            model.isListOpen.toggle()
        }
    }

    private func showMenu() {
        model.isListOpen = false
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Expiring Files", action: #selector(openList), keyEquivalent: "").target = self
        menu.addItem(withTitle: model.isPaused ? "Resume Timers" : "Pause Timers", action: #selector(togglePause), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Pumpkin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openList() { model.isListOpen = true }
    @objc private func togglePause() { model.togglePause() }
    @objc private func openSettings() { model.actions.showSettings() }

    /// Redraws the icon and title. Reads the model, so it re-runs on every relevant change.
    private func refresh() {
        guard let button = statusItem.button else { return }
        if let workbench, workbench.recorder.busy {
            button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
            button.contentTintColor = .systemRed
            button.title = workbench.recorder.phase == .recording ? workbench.recorder.elapsed : workbench.recorder.phase == .finalizing ? "…" : "◉"
            button.toolTip = workbench.text("Pumpkin — запись / сохранение", "Pumpkin — recording / saving")
            scheduleTick(for: nil)
            return
        }
        button.contentTintColor = nil
        let soonest = model.soonest
        let reference = model.clock(Date())
        let asking = !model.prompts.isEmpty
        let fraction = soonest.map { $0.fractionRemaining(at: reference) }

        button.image = StatusIcon.image(fraction: fraction, paused: model.isPaused, asking: asking)

        if model.prefs.showCountdown, let soonest, !asking {
            let text = Formatting.compactRemaining(soonest.remaining(at: reference))
            button.attributedTitle = NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .baselineOffset: 0.5,
            ])
        } else {
            button.title = ""
        }

        if let soonest {
            let count = model.items.count
            let files = count == 1 ? "1 file" : "\(count) files"
            let label = model.isPaused ? "paused" : "next goes \(Formatting.expiryLabel(for: soonest.expiresAt))"
            button.toolTip = "Pumpkin — \(files) expiring, \(label)"
        } else {
            button.toolTip = model.isPaused ? "Pumpkin — paused" : "Pumpkin"
        }

        scheduleTick(for: soonest.map { $0.remaining(at: reference) })
    }

    /// Ticks once a second in the last two minutes, otherwise every 10 seconds.
    private func scheduleTick(for remaining: TimeInterval?) {
        let interval: TimeInterval
        if let remaining, !model.isPaused {
            interval = remaining < 120 ? 1 : 10
        } else {
            interval = 0
        }
        guard interval != tickInterval else { return }
        tickInterval = interval
        tickTimer?.invalidate()
        tickTimer = nil
        guard interval > 0 else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func tick() {
        // Called outside observation tracking: time passing isn't an observable change.
        refresh()
    }
}
