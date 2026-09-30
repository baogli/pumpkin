import AppKit
import PumpkinCore
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private var onClose: (() -> Void)?

    init(model: AppModel, onFinish: @escaping (_ launchAtLogin: Bool) -> Void, onClose: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 580),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.title = "Welcome to Pumpkin"
        self.onClose = onClose
        super.init(window: window)

        window.contentView = NSHostingView(rootView: OnboardingView(onFinish: { [weak self] launchAtLogin in
            onFinish(launchAtLogin)
            self?.close()
        }).environment(model))
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func present() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        onClose = nil
    }
}

private enum AccessState: Equatable {
    case unknown, checking, granted, denied
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    let onFinish: (Bool) -> Void

    @State private var step: Int
    @State private var access: AccessState = .unknown
    @State private var screenshotAccess: Bool?
    @State private var launchAtLogin = true

    private let stepCount = 4

    init(startAt step: Int = 0, onFinish: @escaping (Bool) -> Void) {
        self.onFinish = onFinish
        _step = State(initialValue: step)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                .padding(.top, 44)
                .padding(.leading, -6)

            Group {
                switch step {
                case 0: welcome
                case 1: downloadsAccess
                case 2: tryIt
                default: allSet
                }
            }
            .id(step)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 16)), removal: .opacity))

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                Button(step == stepCount - 1 ? "Finish" : "Continue") { advance() }
                    .buttonStyle(.pillProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canContinue)
                    .opacity(canContinue ? 1 : 0.45)
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            PageDots(count: stepCount, current: step)
                .frame(maxWidth: .infinity)
                .padding(.top, 26)
        }
        .padding(.horizontal, 44)
        .padding(.bottom, 24)
        .frame(width: 520, height: 580)
        .background(alignment: .top) {
            LinearGradient(
                colors: [Brand.gradientTop.opacity(0.22), Brand.gradientBottom.opacity(0.06), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
        .tint(Brand.tint)
        .animation(.smooth(duration: 0.3), value: step)
        .animation(.smooth(duration: 0.25), value: access)
        .animation(.smooth(duration: 0.25), value: model.demoStatus)
    }

    private var canContinue: Bool {
        step != 1 || access == .granted
    }

    private func advance() {
        if step < stepCount - 1 {
            step += 1
        } else {
            onFinish(launchAtLogin)
        }
    }

    // MARK: Steps

    private var welcome: some View {
        StepText(
            title: "Welcome to Pumpkin",
            message: "Every file gets its midnight. Pick 30 minutes, a day, or keep it forever — when time’s up, Pumpkin moves the file to the Trash. Everything stays on your Mac."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(symbol: "arrow.down.circle", title: "Download or screenshot as usual", detail: "A small question drops down from the menu bar.")
                FeatureRow(symbol: "timer", title: "Pick its midnight", detail: "10 minutes to 30 days — or keep it forever.")
                FeatureRow(symbol: "arrow.uturn.backward.circle", title: "Change your mind", detail: "Put anything back from the Trash in one click.")
            }
        }
    }

    private var downloadsAccess: some View {
        StepText(
            title: "See Your Downloads",
            message: "Pumpkin watches your \(model.prefs.watchedFolderName) folder so it can ask about each new file — and, if you like, your \(screenshotFolderName) for new screenshots. macOS asks for permission to those folders. Nothing else is read, and nothing leaves your Mac."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                accessStatus
                Toggle("Also ask about new screenshots on the \(screenshotFolderName)", isOn: Binding(
                    get: { model.prefs.watchScreenshots },
                    set: { enabled in
                        model.prefs.watchScreenshots = enabled
                        if access == .granted {
                            requestAccess()
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12.5))
                if access == .granted, model.prefs.watchScreenshots, screenshotAccess == false {
                    StatusLine(symbol: "exclamationmark.circle.fill", color: .orange, text: "No access to the \(screenshotFolderName) yet — screenshots will be skipped.")
                }
            }
        }
    }

    private var screenshotFolderName: String {
        model.folderName(for: model.resolveScreenshotFolder())
    }

    @ViewBuilder
    private var accessStatus: some View {
        Group {
            switch access {
            case .granted:
                StatusLine(symbol: "checkmark.circle.fill", color: .green, text: "\(model.prefs.watchedFolderName) access is enabled")
            case .denied:
                VStack(alignment: .leading, spacing: 10) {
                    StatusLine(symbol: "xmark.circle.fill", color: .orange, text: "Pumpkin can’t see \(model.prefs.watchedFolderName) yet")
                    Text("Turn on Pumpkin under Privacy & Security › Files & Folders, then check again.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Open Privacy Settings") { FolderAccess.openPrivacySettings() }
                            .buttonStyle(.pill)
                        Button("Check Again") { requestAccess() }
                            .buttonStyle(.pill)
                    }
                }
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for macOS…").font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
            case .unknown:
                Button {
                    requestAccess()
                } label: {
                    Label("Allow Access", systemImage: "folder.badge.gearshape")
                }
                .buttonStyle(.pill)
            }
        }
    }

    private var tryIt: some View {
        StepText(
            title: "Try It",
            message: "Drop a sample file into \(model.prefs.watchedFolderName). Pumpkin drops down from the menu bar and asks how long to keep it. Pick 30s and watch it go to the Trash."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                switch model.demoStatus {
                case .idle, .failed:
                    Button {
                        model.dropSampleFile()
                    } label: {
                        Label("Drop a Sample File", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.pill)
                    if case .failed(let message) = model.demoStatus {
                        StatusLine(symbol: "exclamationmark.triangle.fill", color: .orange, text: message)
                    } else {
                        Text("The sample is a tiny text file named “Pumpkin Sample.txt”.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.tertiary)
                    }
                case .waitingForAnswer:
                    StatusLine(symbol: "arrow.up.circle.fill", color: Brand.tint, text: "Look up at the menu bar — pick 30s and press Done.")
                case .scheduled(let date):
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = max(0, Int(date.timeIntervalSince(context.date).rounded(.up)))
                        StatusLine(symbol: "timer", color: Brand.tint, text: seconds > 0 ? "Scheduled — off to the Trash in \(Formatting.compactRemaining(TimeInterval(seconds)))" : "Moving it to the Trash…")
                    }
                case .kept:
                    StatusLine(symbol: "pin.fill", color: .blue, text: "Kept. The sample stays in \(model.prefs.watchedFolderName).")
                    Button("Try Again") { model.dropSampleFile() }
                        .buttonStyle(.pill)
                case .trashed:
                    StatusLine(symbol: "checkmark.circle.fill", color: .green, text: "Moved to Trash. That’s the whole workflow.")
                }
            }
        }
    }

    private var allSet: some View {
        StepText(
            title: "You’re All Set",
            message: "Pumpkin lives in your menu bar. Click it any time to see what’s expiring, change a timer, or put something back."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(nsImage: StatusIcon.image(fraction: 0.7, paused: false, asking: false))
                        .renderingMode(.template)
                        .foregroundStyle(.primary)
                    Text("Look for this in your menu bar.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))

                Toggle("Open Pumpkin at login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))
            }
        }
    }

    private func requestAccess() {
        access = .checking
        let folder = model.prefs.watchedFolder
        let screenshots = model.prefs.watchScreenshots ? model.resolveScreenshotFolder() : nil
        Task {
            let granted = await FolderAccess.check(folder)
            if let screenshots {
                screenshotAccess = await FolderAccess.check(screenshots)
            } else {
                screenshotAccess = nil
            }
            access = granted ? .granted : .denied
            if granted {
                model.startWatching()
            }
        }
    }
}

private struct StepText<Accessory: View>: View {
    let title: String
    let message: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 24)
            Text(message)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            accessory
                .padding(.top, 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatusLine: View {
    let symbol: String
    let color: Color
    let text: String

    var body: some View {
        Label {
            Text(text).font(.system(size: 12.5, weight: .medium))
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
        .foregroundStyle(color == .green ? AnyShapeStyle(Color.green) : AnyShapeStyle(.primary))
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(Brand.tint) : AnyShapeStyle(Color.primary.opacity(0.18)))
                    .frame(width: index == current ? 16 : 6, height: 6)
            }
        }
        .animation(.smooth(duration: 0.3), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}
