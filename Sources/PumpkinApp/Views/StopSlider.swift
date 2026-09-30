import AppKit
import PumpkinCore
import SwiftUI

/// A track of fixed stops ("10m … 30d"). Click a stop or drag across; it snaps.
struct StopSlider: View {
    let stops: [ShelfDuration]
    let selection: Int
    let onSelect: (Int) -> Void

    private let trackY: CGFloat = 11
    private let labelY: CGFloat = 35

    var body: some View {
        GeometryReader { geometry in
            let step = geometry.size.width / CGFloat(max(stops.count, 1))
            let center = { (index: Int) -> CGFloat in step * (CGFloat(index) + 0.5) }

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: center(stops.count - 1) - center(0), height: 4)
                    .offset(x: center(0), y: trackY - 2)

                Capsule()
                    .fill(.tint)
                    .frame(width: max(0, center(selection) - center(0)), height: 4)
                    .offset(x: center(0), y: trackY - 2)

                ForEach(stops.indices, id: \.self) { index in
                    StopDot(state: index < selection ? .passed : (index == selection ? .selected : .upcoming))
                        .position(x: center(index), y: trackY)

                    Text(stops[index].shortLabel)
                        .font(.system(size: 11, weight: index == selection ? .bold : .medium).monospacedDigit())
                        .foregroundStyle(index == selection ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .position(x: center(index), y: labelY)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let index = min(max(Int(value.location.x / step), 0), stops.count - 1)
                        if index != selection {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                            onSelect(index)
                        }
                    }
            )
        }
        .frame(height: 46)
        .animation(.spring(duration: 0.28, bounce: 0.25), value: selection)
        .accessibilityElement()
        .accessibilityLabel("Keep for")
        .accessibilityValue(stops.indices.contains(selection) ? stops[selection].longLabel : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSelect(min(selection + 1, stops.count - 1))
            case .decrement: onSelect(max(selection - 1, 0))
            @unknown default: break
            }
        }
    }
}

private struct StopDot: View {
    enum State { case passed, selected, upcoming }
    let state: State

    var body: some View {
        switch state {
        case .selected:
            Circle()
                .fill(.tint)
                .frame(width: 20, height: 20)
                .overlay(Circle().fill(.white).frame(width: 7, height: 7))
                .shadow(color: Brand.tint.opacity(0.45), radius: 5, y: 1)
        case .passed:
            Circle().fill(.tint).frame(width: 8, height: 8)
        case .upcoming:
            Circle().fill(Color.primary.opacity(0.28)).frame(width: 8, height: 8)
        }
    }
}
