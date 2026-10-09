import SwiftUI
import AppKit

/// Explicit pane dimensions avoid recursive min/max layout negotiation between
/// nested SwiftUI split hosts. Drag translation uses window coordinates.
struct PanelDivider: View {
    enum Axis { case vertical, horizontal }
    var axis: Axis
    @Binding var value: Double
    var displayedValue: Double
    var limits: ClosedRange<Double>
    var label: String
    var reverse = false
    @State private var origin: Double?
    @State private var hovering = false
    private func set(_ next: Double) { value = min(limits.upperBound, max(limits.lowerBound, next)) }
    var body: some View {
        ZStack {
            Color.primary.opacity(hovering || origin != nil ? 0.10 : 0.035)
            Rectangle().fill(hovering || origin != nil ? Color.cyan : Color.primary.opacity(0.16))
                .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
        }
        .frame(width: axis == .vertical ? 7 : nil, height: axis == .horizontal ? 7 : nil)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside { (axis == .vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() }
            else { NSCursor.pop() }
        }
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { drag in
                if origin == nil { origin = displayedValue }
                set((origin ?? displayedValue) + (axis == .vertical ? drag.translation.width * (reverse ? -1 : 1) : -drag.translation.height))
            }
            .onEnded { _ in origin = nil })
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(displayedValue))")
        .accessibilityAdjustableAction { direction in set(displayedValue + (direction == .increment ? 20 : -20)) }
        .help("拖动调整尺寸；尺寸会自动保存")
    }
}
