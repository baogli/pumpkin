import AppKit
import PumpkinCore
import SwiftUI

/// The panel shown when the menu bar icon is clicked.
struct ListPanelView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.sortedItems
        let history = model.recentHistory

        VStack(spacing: 0) {
            if let batch = model.prompts.first {
                PromptCard(batchID: batch.id, fallback: batch, embedded: true)
                separator
            }

            if let problem = model.folderProblem {
                Banner(
                    systemImage: "exclamationmark.triangle.fill",
                    color: .orange,
                    title: problem,
                    message: "Allow access in System Settings › Privacy & Security › Files & Folders, then try again.",
                    buttons: [
                        ("Open Settings", { FolderAccess.openPrivacySettings() }),
                        ("Try Again", { model.retryWatching() }),
                    ]
                )
                .padding([.horizontal, .top], 10)
            }

            if let problem = model.screenshotProblem, model.folderProblem == nil {
                Banner(
                    systemImage: "camera.viewfinder",
                    color: .orange,
                    title: problem,
                    message: "Allow access in System Settings › Privacy & Security › Files & Folders, or turn screenshots off in Settings.",
                    buttons: [
                        ("Open Settings", { FolderAccess.openPrivacySettings() }),
                        ("Try Again", { model.retryWatching() }),
                    ]
                )
                .padding([.horizontal, .top], 10)
            }

            if model.isPaused {
                Banner(
                    systemImage: "pause.circle.fill",
                    color: .blue,
                    title: "Timers are paused",
                    message: "Nothing goes to the Trash and new downloads aren’t asked about.",
                    buttons: [("Resume", { model.togglePause() })]
                )
                .padding([.horizontal, .top], 10)
            }

            if items.isEmpty && history.isEmpty {
                EmptyStateView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !items.isEmpty {
                            SectionHeader(title: "Expiring") {
                                Text("\(items.count)")
                                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            ForEach(items) { item in
                                ExpiringRow(item: item)
                            }
                        }
                        if !history.isEmpty {
                            SectionHeader(title: "Recently Trashed") {
                                Button("Clear") { model.clearHistory() }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .help("Forget this list (files stay in the Trash)")
                            }
                            ForEach(history) { record in
                                TrashedRow(record: record)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.automatic)
                .frame(height: listHeight(items: items.count, history: history.count))
            }

            separator
            FooterBar()
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private func listHeight(items: Int, history: Int) -> CGFloat {
        let headers = (items > 0 ? 1 : 0) + (history > 0 ? 1 : 0)
        let natural = CGFloat(headers) * ListMetrics.headerHeight + CGFloat(items + history) * ListMetrics.rowHeight + 12
        return min(natural, ListMetrics.maxListHeight)
    }
}

private struct EmptyStateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text("Nothing temporary right now")
                .font(.system(size: 13.5, weight: .semibold))
            Text("New downloads will show up here.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

private struct ExpiringRow: View {
    @Environment(AppModel.self) private var model
    let item: TrackedItem
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            FileIconView(path: item.path, isFolder: item.isFolder, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(item.lastError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if hovering {
                actions.transition(.opacity)
            } else {
                countdown.transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: ListMetrics.rowHeight)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(hovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
        }
        .onTapGesture(count: 2) { model.open(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu { contextMenu }
        .help(item.path)
    }

    private var subtitle: String {
        if item.lastError != nil {
            return "Couldn’t move to Trash — retrying soon"
        }
        let when = model.isPaused ? "Paused" : Formatting.expiryLabel(for: item.expiresAt)
        return "\(when) · \(Formatting.size(item.size))"
    }

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let reference = model.clock(context.date)
            let remaining = item.remaining(at: reference)
            let urgent = remaining < 300
            HStack(spacing: 6) {
                Text(Formatting.compactRemaining(remaining))
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(urgent ? AnyShapeStyle(Brand.tint) : AnyShapeStyle(.secondary))
                    .contentTransition(.numericText(countsDown: true))
                CountdownRing(fraction: item.fractionRemaining(at: reference), urgent: urgent)
                    .frame(width: 15, height: 15)
            }
            .animation(.smooth(duration: 0.3), value: Formatting.compactRemaining(remaining))
        }
        .accessibilityLabel("\(Formatting.compactRemaining(item.remaining(at: model.clock(Date())))) left")
    }

    private var actions: some View {
        HStack(spacing: 0) {
            Menu {
                timerMenuItems
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(.secondary)
            .frame(width: 26, height: 26)
            .fixedSize()
            .help("Change timer")

            IconButton(systemImage: "pin", help: "Keep forever") { model.keepForever(item.id) }
            IconButton(systemImage: "trash", help: "Move to Trash now") { model.trashNow(item.id) }
        }
    }

    @ViewBuilder
    private var timerMenuItems: some View {
        Section("Trash After") {
            ForEach(ShelfDuration.standardStops) { duration in
                Button(duration.longLabel) { model.setTimer(for: item.id, to: duration) }
            }
        }
        Divider()
        Button("Keep Forever") { model.keepForever(item.id) }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Open") { model.open(item) }
        Button("Show in Finder") { model.reveal(item) }
        Divider()
        Menu("Trash After") {
            ForEach(ShelfDuration.standardStops) { duration in
                Button(duration.longLabel) { model.setTimer(for: item.id, to: duration) }
            }
        }
        Button("Keep Forever") { model.keepForever(item.id) }
        Divider()
        Button("Move to Trash Now") { model.trashNow(item.id) }
    }
}

private struct TrashedRow: View {
    @Environment(AppModel.self) private var model
    let record: TrashRecord
    @State private var hovering = false

    var body: some View {
        let canPutBack = record.canPutBack
        HStack(spacing: 10) {
            FileIconView(path: record.trashedPath ?? record.originalPath, isFolder: record.isFolder, size: 30)
                .opacity(canPutBack ? 0.9 : 0.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.name)
                    .font(.system(size: 13))
                    .foregroundStyle(canPutBack ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if canPutBack {
                Button("Put Back") { model.putBack([record]) }
                    .buttonStyle(.pill)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: ListMetrics.rowHeight)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(hovering ? 0.05 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.revealInTrash(record) }
        .contextMenu {
            if canPutBack {
                Button("Put Back") { model.putBack([record]) }
                Button("Show in Trash") { model.revealInTrash(record) }
            }
        }
    }

    private var status: String {
        if record.restoredAt != nil {
            return "Put back"
        }
        let ago = Formatting.agoLabel(for: record.trashedAt)
        if record.canPutBack {
            return "Trashed \(ago.prefix(1).lowercased() + ago.dropFirst()) · \(Formatting.size(record.size))"
        }
        return "No longer in the Trash"
    }
}

private struct FooterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            Button {
                model.openWatchedFolder()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                    Text(model.prefs.watchedFolderName)
                }
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 8)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open \(model.prefs.watchedFolderName) in Finder")

            if let screenshots = model.screenshotFolder,
               ItemLocator.canonicalPath(screenshots) != ItemLocator.canonicalPath(model.prefs.watchedFolder) {
                Button {
                    NSWorkspace.shared.open(screenshots)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.viewfinder")
                        Text(model.folderName(for: screenshots))
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Screenshots are watched here. Open in Finder")
            }

            Spacer()

            IconButton(
                systemImage: model.isPaused ? "play.fill" : "pause.fill",
                help: model.isPaused ? "Resume timers" : "Pause all timers"
            ) {
                model.togglePause()
            }

            Menu {
                Button("Settings…") { model.actions.showSettings() }
                Button("Welcome Guide") { model.actions.showOnboarding() }
                Button("About Pumpkin") { model.actions.showAbout() }
                Divider()
                Button("Quit Pumpkin") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(.secondary)
            .frame(width: 26, height: 26)
            .fixedSize()
            .help("Settings")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
