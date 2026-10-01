import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class PanelPresentation {
    var scene: PanelScene = .list
}

/// Borderless panel that can take clicks and keys without activating Pumpkin,
/// so the browser you're downloading from keeps focus.
final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { makeKeyAndOrderFront(nil) }
        super.sendEvent(event)
    }
}

final class PanelHostingView: NSHostingView<AnyView> {
    var onIntrinsicSizeChange: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in
            self?.onIntrinsicSizeChange?()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if event.trackingArea === hoverArea {
            onHoverChange?(true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if event.trackingArea === hoverArea {
            onHoverChange?(false)
        }
    }
}

@MainActor
final class PanelController: NSObject {
    static let width: CGFloat = 360
    static let cornerRadius: CGFloat = 20
    private static let gap: CGFloat = 6

    private let model: AppModel
    private let workbench: Workbench?
    private let statusItem: NSStatusItem
    private let presentation = PanelPresentation()
    private let panel: MenuPanel
    private let hostingView: PanelHostingView
    private var isShown = false
    private var transitionRevision = 0
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var keyMonitor: Any?
    private var notificationTokens: [NSObjectProtocol] = []
    private let observeOutsideEvents: Bool

    /// For the QA tool.
    var window: NSPanel { panel }
    var contentHost: PanelHostingView { hostingView }

    init(model: AppModel, statusItem: NSStatusItem, workbench: Workbench? = nil, observeOutsideEvents: Bool = true) {
        self.model = model
        self.workbench = workbench
        self.statusItem = statusItem
        self.observeOutsideEvents = observeOutsideEvents
        if let workbench {
            hostingView = PanelHostingView(rootView: AnyView(UnifiedTransientPanel(presentation: presentation).environment(workbench)))
        } else {
            hostingView = PanelHostingView(rootView: AnyView(PanelRootView(presentation: presentation).environment(model)))
        }
        hostingView.sizingOptions = [.intrinsicContentSize]
        panel = MenuPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        configurePanel()
        installMonitors()

        hostingView.onIntrinsicSizeChange = { [weak self] in
            self?.resizeToFit(animated: true)
        }
        hostingView.onHoverChange = { [weak self] inside in
            self?.model.isPointerInside = inside
        }

        if observeOutsideEvents {
            notificationTokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.isListOpen = false }
            })
        }
        notificationTokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resizeToFit(animated: false) }
        })

        observeContinuously { [weak self] in
            self?.sync()
        }
    }

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.setAccessibilityLabel("Pumpkin")

        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = makeBackground(containing: hostingView)
    }

    private func makeBackground(containing content: NSView) -> NSView {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let background = NSView()
            background.wantsLayer = true; background.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            background.layer?.cornerRadius = Self.cornerRadius
            content.frame = background.bounds; background.addSubview(content)
            return background
        }
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Self.cornerRadius
            glass.contentView = content
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = .roundedMask(radius: 14)
        content.frame = effect.bounds
        effect.addSubview(content)
        return effect
    }

    // MARK: - Showing and hiding

    /// Mirrors the model's scene. Re-runs whenever the scene changes.
    private func sync() {
        if let workbench { panel.appearance = workbench.prefs.appearance }
        let scene = model.scene
        let listOpen = model.isListOpen
        statusItem.button?.highlight(listOpen)
        updateOutsideClickMonitor(listOpen)

        guard let scene else {
            hide()
            return
        }
        presentation.scene = scene
        show()
    }

    private func show() {
        if isShown {
            resizeToFit(animated: true)
            return
        }
        isShown = true
        transitionRevision += 1
        let revision = transitionRevision
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            hostingView.layoutSubtreeIfNeeded(); panel.setFrame(targetFrame(), display: true)
            panel.alphaValue = 1; panel.orderFrontRegardless(); return
        }
        panel.alphaValue = 0
        panel.setFrame(targetFrame().offsetBy(dx: 0, dy: 10), display: false)
        panel.orderFrontRegardless()

        // Let SwiftUI lay out the new scene before measuring it.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isShown, self.transitionRevision == revision else { return }
            self.hostingView.layoutSubtreeIfNeeded()
            let frame = self.targetFrame()
            self.panel.setFrame(frame.offsetBy(dx: 0, dy: 10), display: true)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
                self.panel.animator().setFrame(frame, display: true)
                self.panel.animator().alphaValue = 1
            } completionHandler: {
                MainActor.assumeIsolated { self.panel.invalidateShadow() }
            }
            // AppKit can suspend window animations for an accessory process.
            // Visibility must not depend on the animation callback arriving.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
                guard let self, self.isShown, self.transitionRevision == revision else { return }
                self.panel.setFrame(self.targetFrame(), display: true)
                self.panel.alphaValue = 1
                self.panel.invalidateShadow()
            }
        }
    }

    private func hide() {
        guard isShown else { return }
        isShown = false
        transitionRevision += 1
        let revision = transitionRevision
        model.isPointerInside = false
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 0; panel.orderOut(nil); return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.panel.animator().alphaValue = 0
            self.panel.animator().setFrame(self.panel.frame.offsetBy(dx: 0, dy: 6), display: true)
        } completionHandler: {
            MainActor.assumeIsolated {
                guard !self.isShown, self.transitionRevision == revision else { return }
                self.panel.orderOut(nil)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self, !self.isShown, self.transitionRevision == revision else { return }
            self.panel.alphaValue = 0
            self.panel.orderOut(nil)
        }
    }

    private func resizeToFit(animated: Bool) {
        guard isShown else { return }
        let frame = targetFrame()
        guard frame != panel.frame else { return }
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            transitionRevision += 1
            let revision = transitionRevision
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.8, 0.25, 1)
                self.panel.animator().setFrame(frame, display: true)
            } completionHandler: {
                MainActor.assumeIsolated { self.panel.invalidateShadow() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
                guard let self, self.isShown, self.transitionRevision == revision else { return }
                self.panel.setFrame(self.targetFrame(), display: true)
                self.panel.alphaValue = 1
                self.panel.invalidateShadow()
            }
        } else {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
        }
    }

    private func targetFrame() -> NSRect {
        let intrinsic = hostingView.intrinsicContentSize.height
        let height = intrinsic > 0 ? ceil(intrinsic) : 120
        let (anchor, bounds) = anchorPoint()
        let x = min(max(anchor.x - Self.width / 2, bounds.minX + 8), bounds.maxX - Self.width - 8)
        return NSRect(x: round(x), y: round(anchor.y - height), width: Self.width, height: height)
    }

    /// Just under the status item, or the top-right corner if the item is hidden
    /// (for example behind the notch or by a menu bar manager).
    private func anchorPoint() -> (NSPoint, NSRect) {
        if let button = statusItem.button, let window = button.window, let screen = window.screen {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            if screen.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) {
                // Hang from the bottom of the menu bar, which on notched Macs is
                // taller than the button itself.
                return (NSPoint(x: rect.midX, y: min(window.frame.minY, screen.visibleFrame.maxY) - Self.gap), screen.visibleFrame)
            }
        }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        return (NSPoint(x: visible.maxX - Self.width / 2 - 8, y: visible.maxY - Self.gap), visible)
    }

    // MARK: - Events

    private func updateOutsideClickMonitor(_ listOpen: Bool) {
        guard observeOutsideEvents else { return }
        if listOpen, outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.isListOpen = false }
            }
        } else if !listOpen, let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func installMonitors() {
        // Clicks in Pumpkin's own windows (Settings, onboarding) close the list too.
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.model.isListOpen, let window = event.window else { return }
                let isOurs = window === self.panel || window === self.statusItem.button?.window
                if !isOurs && window.level < .popUpMenu {
                    self.model.isListOpen = false
                }
            }
            return event
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.panel else { return false }
                return self.handleKey(event)
            }
            return handled ? nil : event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        guard modifiers.isEmpty else { return false }
        let prompt: PromptBatch?
        if case .prompt(let batch)? = model.scene { prompt = batch } else { prompt = nil }

        switch event.keyCode {
        case 53: // Escape
            if model.isListOpen {
                model.isListOpen = false
            } else if prompt != nil {
                model.dismissCurrentPrompt()
            } else {
                model.dismissToast()
            }
            return true
        case 36, 76: // Return, Enter
            guard let prompt else { return false }
            model.confirm(prompt.id)
            return true
        case 123: // Left
            guard prompt != nil else { return false }
            model.nudgeSelection(by: -1)
            return true
        case 124: // Right
            guard prompt != nil else { return false }
            model.nudgeSelection(by: 1)
            return true
        default:
            if let prompt, event.charactersIgnoringModifiers?.lowercased() == "k" {
                model.keep(prompt.id)
                return true
            }
            return false
        }
    }
    deinit {
        panel.orderOut(nil)
        for monitor in [outsideClickMonitor, localClickMonitor, keyMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        for token in notificationTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
    }
}

extension NSImage {
    /// Stretchable mask giving an NSVisualEffectView rounded corners.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
