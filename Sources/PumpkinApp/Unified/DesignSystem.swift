import AppKit
import SwiftUI

enum GlassPalette {
    static let orange = Color(red: 1, green: 0.478, blue: 0.102)
    static let forest = Color(red: 0.078, green: 0.22, blue: 0.165)
    static let sage = Color(red: 0.365, green: 0.733, blue: 0.541)
    static let cream = Color(red: 1, green: 0.922, blue: 0.827)
}

struct NativeGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let effect = NSGlassEffectView(); effect.cornerRadius = 36; return effect
        }
        let effect = NSVisualEffectView(); effect.material = .underWindowBackground; effect.blendingMode = .behindWindow; effect.state = .active
        return effect
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct GlassBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if reduceTransparency { (scheme == .dark ? Color(red: 0.09, green: 0.16, blue: 0.12) : Color(red: 0.984, green: 0.945, blue: 0.902)) }
            else {
                NativeGlass()
                LinearGradient(colors: scheme == .dark ? [GlassPalette.forest.opacity(0.86), Color(red: 0.16, green: 0.09, blue: 0.2).opacity(0.67)] : [GlassPalette.cream.opacity(0.66), Color.orange.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
                GeometryReader { geometry in
                    Circle().fill(RadialGradient(colors: [GlassPalette.orange.opacity(scheme == .dark ? 0.22 : 0.27), .clear], center: .center, startRadius: 0, endRadius: geometry.size.width * 0.38)).frame(width: geometry.size.width * 0.85).offset(x: -190, y: geometry.size.height * 0.38)
                    Circle().fill(RadialGradient(colors: [GlassPalette.sage.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: geometry.size.width * 0.40)).frame(width: geometry.size.width * 0.85).offset(x: geometry.size.width * 0.45, y: geometry.size.height * 0.20)
                    Circle().fill(RadialGradient(colors: [Color.indigo.opacity(scheme == .dark ? 0.24 : 0.25), .clear], center: .center, startRadius: 0, endRadius: geometry.size.width * 0.33)).frame(width: geometry.size.width * 0.70).offset(x: geometry.size.width * 0.52, y: -190)
                }
            }
        }.clipped()
    }
}

struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = 18
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(padding).background(scheme == .dark ? Color.white.opacity(0.065) : Color.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(scheme == .dark ? 0.13 : 0.8), lineWidth: 1))
            .shadow(color: .black.opacity(scheme == .dark ? 0.08 : 0.035), radius: 12, y: 5)
    }
}

/// Static foreground colors keep transient hosting views readable even when
/// AppKit draws them in a cached context with a different native appearance.
struct PumpkinContentColor: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View { content.foregroundStyle(scheme == .dark ? Color.white : Color(red: 0.15, green: 0.13, blue: 0.11)) }
}

struct PumpkinButtonStyle: ButtonStyle {
    var primary = false
    var destructive = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .semibold)).padding(.horizontal, 17).padding(.vertical, 11)
            .foregroundStyle(primary ? Color(red: 0.17, green: 0.075, blue: 0.016) : destructive ? Color.red : Color.primary)
            .background {
                if primary { Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.67, blue: 0.32), GlassPalette.orange], startPoint: .top, endPoint: .bottom)) }
                else { Capsule().fill(Color.white.opacity(scheme == .dark ? 0.10 : 0.75)) }
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.42), lineWidth: 1))
            .shadow(color: primary ? GlassPalette.orange.opacity(0.17) : Color.black.opacity(0.04), radius: 6, y: 3)
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
    }
}

struct StatusPill: View {
    var title: String
    var symbol = "checkmark.circle"
    var color = GlassPalette.sage
    var body: some View { Label(title, systemImage: symbol).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 11).padding(.vertical, 6).background(color.opacity(0.16), in: Capsule()) }
}

struct LevelMeter: View {
    var level: Float
    var channel: String
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<12) { i in RoundedRectangle(cornerRadius: 2).fill(Double(i) / 12 < Double(min(1, level * 2)) ? (i > 9 ? Color.red : GlassPalette.sage) : Color.secondary.opacity(0.13)).frame(width: 5, height: 10) }
        }.accessibilityElement(children: .ignore).accessibilityLabel(channel).accessibilityValue(level < 0.0005 ? "Silence" : "\(Int(min(1, level) * 100)) percent")
    }
}

struct ScreenHeader: View {
    var title: String
    var subtitle: String
    var body: some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 30, weight: .heavy, design: .rounded)); Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary) } }
}

struct PillSegments<Value: Hashable>: View {
    @Binding var selection: Value
    var choices: [(String, Value)]
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                Button { selection = choice.1 } label: {
                    Text(choice.0).font(.system(size: 12, weight: selection == choice.1 ? .semibold : .medium)).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).padding(.horizontal, 5).padding(.vertical, 8)
                        .background(selection == choice.1 ? Color.white.opacity(scheme == .dark ? 0.17 : 0.9) : .clear, in: Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(selection == choice.1 ? .isSelected : [])
            }
        }.padding(3).background(Color.primary.opacity(0.07), in: Capsule())
    }
}
