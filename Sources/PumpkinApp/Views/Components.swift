import AppKit
import PumpkinCore
import SwiftUI

struct FileIconView: View {
    let path: String
    var isFolder = false
    var size: CGFloat = 32

    var body: some View {
        Group {
            if !isFolder, let thumbnail = Thumbnails.shared.thumbnail(for: path) {
                let shape = RoundedRectangle(cornerRadius: max(2, size * 0.08), style: .continuous)
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                    .padding(size * 0.04)
            } else {
                Image(nsImage: FileIcons.icon(path: path, isFolder: isFolder))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A file icon with a small circular badge in the corner.
struct BadgedIcon: View {
    let path: String
    var isFolder = false
    var size: CGFloat = 36
    let symbol: String
    let badgeColor: Color

    var body: some View {
        FileIconView(path: path, isFolder: isFolder, size: size)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.46, height: size * 0.46)
                    .background(Circle().fill(badgeColor))
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                    .offset(x: size * 0.1, y: size * 0.08)
            }
    }
}

/// Two or three overlapping icons for a multi-file question.
struct StackedIcons: View {
    let items: [PromptItem]
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            ForEach(Array(items.prefix(3).enumerated().reversed()), id: \.element.id) { index, item in
                FileIconView(path: item.url.path, isFolder: item.snapshot.isFolder, size: size - CGFloat(index) * 4)
                    .rotationEffect(.degrees(items.count > 1 ? Double(index) * -8 : 0))
                    .offset(x: CGFloat(index) * 5, y: CGFloat(index) * -2)
                    .opacity(index == 0 ? 1 : 0.85)
            }
        }
        .frame(width: size + 8, height: size)
    }
}

/// A small clock-style pie that empties as the timer runs down.
struct CountdownRing: View {
    let fraction: Double
    var urgent = false

    var body: some View {
        let color = urgent ? Brand.tint : Color.secondary
        ZStack {
            Circle().strokeBorder(color, lineWidth: 1.3)
            PieSlice(fraction: fraction)
                .fill(color)
                .padding(2.8)
        }
        .animation(.smooth(duration: 0.4), value: fraction)
    }
}

struct PieSlice: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clamped = min(max(fraction, 0), 1)
        guard clamped > 0.001 else { return path }
        if clamped > 0.999 {
            path.addEllipse(in: rect)
            return path
        }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(center: center, radius: min(rect.width, rect.height) / 2, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * clamped), clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct IconButton: View {
    let systemImage: String
    let help: String
    var role: ButtonRole?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? .primary : .secondary)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A capsule button that looks at home on glass.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var color: Color = Brand.tint

    func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(configuration: configuration, prominent: prominent, color: color)
    }

    private struct PillButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let color: Color
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 28)
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background {
                    Capsule().fill(prominent ? AnyShapeStyle(color) : AnyShapeStyle(Color.primary.opacity(hovering ? 0.14 : 0.09)))
                }
                .overlay {
                    if prominent {
                        Capsule().fill(.white.opacity(hovering ? 0.1 : 0))
                    }
                }
                .opacity(configuration.isPressed ? 0.75 : 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var pillProminent: PillButtonStyle { PillButtonStyle(prominent: true) }
}

/// Thin bar that drains until the question tucks itself away.
struct DeadlineBar: View {
    let deadline: Date?
    let total: TimeInterval
    @State private var progress: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(Brand.tint.opacity(0.55))
                .frame(width: max(0, geometry.size.width * progress), height: 2)
        }
        .frame(height: 2)
        .opacity(deadline == nil ? 0 : 1)
        .animation(.easeOut(duration: 0.2), value: deadline == nil)
        .onAppear(perform: restart)
        .onChange(of: deadline) { restart() }
        .accessibilityHidden(true)
    }

    private func restart() {
        guard let deadline, total > 0 else {
            progress = 1
            return
        }
        let remaining = max(0, deadline.timeIntervalSinceNow)
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { progress = CGFloat(remaining / total) }
        DispatchQueue.main.async {
            withAnimation(.linear(duration: remaining)) { progress = 0 }
        }
    }
}

struct Banner: View {
    let systemImage: String
    let color: Color
    let title: String
    let message: String
    var buttons: [(String, () -> Void)] = []

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !buttons.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(buttons.indices, id: \.self) { index in
                            Button(buttons[index].0, action: buttons[index].1)
                                .buttonStyle(PillButtonStyle(prominent: index == 0, color: color))
                                .controlSize(.small)
                        }
                    }
                    .padding(.top, 5)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.1)))
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            trailing
        }
        .padding(.horizontal, 8)
        .frame(height: ListMetrics.headerHeight)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

enum ListMetrics {
    static let rowHeight: CGFloat = 46
    static let headerHeight: CGFloat = 28
    static let maxListHeight: CGFloat = 400
}
