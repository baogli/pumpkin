import AppKit
import PumpkinCore
import SwiftUI

struct PanelRootView: View {
    let presentation: PanelPresentation

    var body: some View {
        let scene = presentation.scene
        ZStack(alignment: .top) {
            content(for: scene)
                .id(scene.transitionKey)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: -6)),
                    removal: .opacity
                ))
        }
        .frame(width: PanelController.width)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: 0.28), value: scene.transitionKey)
        .tint(Brand.tint)
    }

    @ViewBuilder
    private func content(for scene: PanelScene) -> some View {
        switch scene {
        case .list:
            ListPanelView()
        case .prompt(let batch):
            PromptCard(batchID: batch.id, fallback: batch)
        case .confirmation(let confirmation):
            ConfirmationView(confirmation: confirmation)
        case .toast(let toast):
            ToastView(toast: toast)
        }
    }
}

// MARK: - The question

struct PromptCard: View {
    @Environment(AppModel.self) private var model
    let batchID: UUID
    /// Used while the panel fades out after the batch has been answered.
    let fallback: PromptBatch
    var embedded = false

    var body: some View {
        let batch = model.prompts.first { $0.id == batchID } ?? fallback
        VStack(alignment: .leading, spacing: 14) {
            header(batch)
            fileRow(batch)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Text("Keep for")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ExpiryPill(duration: batch.selectedDuration)
                }
                StopSlider(stops: batch.stops, selection: batch.selection) { index in
                    model.select(index, in: batch.id)
                }
            }
            HStack(spacing: 8) {
                Button {
                    model.keep(batch.id)
                } label: {
                    Label("Keep Forever", systemImage: "pin.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.pill)
                .help("Leave \(batch.items.count == 1 ? "this file" : "these files") alone (K)")

                Spacer()

                Button("Done") {
                    model.confirm(batch.id)
                }
                .buttonStyle(.pillProminent)
                .help("Move to the Trash after \(batch.selectedDuration.longLabel) (Return)")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, embedded ? 16 : 18)
        .overlay(alignment: .bottom) {
            if !embedded {
                DeadlineBar(deadline: model.promptDeadline, total: model.prefs.promptTimeout)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 6)
            }
        }
    }

    private func headline(_ batch: PromptBatch) -> String {
        if batch.isDemo {
            return "Sample in \(model.prefs.watchedFolderName)"
        }
        if batch.kind == .screenshot {
            return batch.items.count == 1 ? "New Screenshot" : "New Screenshots"
        }
        return "New in \(model.prefs.watchedFolderName)"
    }

    private func header(_ batch: PromptBatch) -> some View {
        HStack(spacing: 6) {
            Image(systemName: batch.kind == .screenshot ? "camera.viewfinder" : "arrow.down.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tint)
            Text(headline(batch))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
            if batch.items.count > 1 {
                Text("\(batch.items.count)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(Capsule().fill(Color.primary.opacity(0.1)))
            }
            Spacer()
            if model.queuedPromptCount > 0 {
                Text("\(model.queuedPromptCount) more waiting")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func fileRow(_ batch: PromptBatch) -> some View {
        HStack(spacing: 12) {
            StackedIcons(items: batch.items, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(batch.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle(batch))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ batch: PromptBatch) -> String {
        if batch.items.count > 1 {
            let names = batch.items.map(\.name).joined(separator: ", ")
            return "\(Formatting.size(batch.totalSize)) · \(names)"
        }
        let item = batch.primary
        var parts: [String] = []
        if let source = item.source {
            parts.append(source)
        }
        if item.snapshot.isFolder {
            parts.append("Folder")
        }
        parts.append(Formatting.size(item.snapshot.size))
        return parts.joined(separator: " · ")
    }
}

/// "Trash · Tomorrow 12:04" — when the file will go if the current stop is chosen.
struct ExpiryPill: View {
    let duration: ShelfDuration

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            HStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.system(size: 9.5, weight: .bold))
                Text(Formatting.expiryLabel(for: context.date.addingTimeInterval(duration.seconds), now: context.date))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.tint)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(Brand.tint.opacity(0.14)))
            .animation(.smooth(duration: 0.2), value: duration)
        }
        .accessibilityLabel("Moves to the Trash \(Formatting.expiryLabel(for: Date().addingTimeInterval(duration.seconds)))")
    }
}

// MARK: - After answering

struct ConfirmationView: View {
    @Environment(AppModel.self) private var model
    let confirmation: Confirmation
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 12) {
            BadgedIcon(
                path: confirmation.iconPath,
                isFolder: confirmation.isFolder,
                size: 34,
                symbol: isScheduled ? "timer" : "pin.fill",
                badgeColor: isScheduled ? Brand.tint : .blue
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(isScheduled ? "Trash scheduled" : "Keeping it")
                    .font(.system(size: 13.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: appeared)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .onAppear { appeared = true }
        .accessibilityElement(children: .combine)
    }

    private var isScheduled: Bool {
        if case .scheduled = confirmation.kind { return true }
        return false
    }

    private var detail: String {
        switch confirmation.kind {
        case .scheduled(let date):
            return "\(Formatting.expiryLabel(for: date)) · \(confirmation.title)"
        case .kept:
            return "\(confirmation.title) won’t be touched"
        }
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    let toast: Toast

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(isFailure ? 3 : 1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if case .trashed(let records) = toast.kind, records.contains(where: \.canPutBack) {
                Button("Put Back") {
                    model.putBack(records)
                }
                .buttonStyle(.pill)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    @ViewBuilder
    private var icon: some View {
        switch toast.kind {
        case .trashed(let records):
            let first = records[0]
            BadgedIcon(path: first.trashedPath ?? first.originalPath, isFolder: first.isFolder, size: 34, symbol: "trash.fill", badgeColor: Brand.tint)
        case .restored:
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)
                .frame(width: 38, height: 34)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.orange)
                .frame(width: 38, height: 34)
        }
    }

    private var isFailure: Bool {
        if case .failed = toast.kind { return true }
        return false
    }

    private var title: String {
        switch toast.kind {
        case .trashed(let records): return records.count == 1 ? "Moved to Trash" : "Moved \(records.count) items to Trash"
        case .restored(_, let count): return count == 1 ? "Put back from the Trash" : "Put back \(count) items"
        case .failed(let title, _): return title
        }
    }

    private var subtitle: String {
        switch toast.kind {
        case .trashed(let records):
            return records.map(\.name).joined(separator: ", ")
        case .restored(let name, _):
            return name
        case .failed(_, let message):
            return message
        }
    }
}
