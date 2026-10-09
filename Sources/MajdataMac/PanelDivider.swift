import SwiftUI
import AppKit

/// Uses AppKit tracking so dragging also works on an inactive window.
struct PanelDivider: View {
    enum Axis { case vertical, horizontal }
    var axis: Axis
    @Binding var value: Double
    var displayedValue: Double
    var limits: ClosedRange<Double>
    var label: String
    var reverse = false
    var body: some View {
        DividerSurface(axis: axis, value: displayedValue, limits: limits, label: label, reverse: reverse) { value = $0 }
            .frame(width: axis == .vertical ? 7 : nil, height: axis == .horizontal ? 7 : nil)
    }
}
private struct DividerSurface: NSViewRepresentable {
    var axis: PanelDivider.Axis
    var value: Double
    var limits: ClosedRange<Double>
    var label: String
    var reverse: Bool
    var change: (Double) -> Void
    func makeNSView(context: Context) -> DividerHandle { DividerHandle() }
    func updateNSView(_ view: DividerHandle, context: Context) {
        view.axis = axis; view.value = value; view.limits = limits; view.reverse = reverse; view.change = change
        view.setAccessibilityLabel(label); view.setAccessibilityValue(Int(value))
        view.toolTip = "拖动调整尺寸；尺寸会自动保存"
        view.window?.invalidateCursorRects(for: view); view.needsDisplay = true
    }
}
@MainActor private final class DividerHandle: NSView {
    var axis = PanelDivider.Axis.vertical
    var value = 0.0
    var limits = 0.0...1.0
    var reverse = false
    var change: ((Double) -> Void)?
    private var origin: (NSPoint, Double)?
    override init(frame: NSRect) { super.init(frame: frame); setAccessibilityElement(true); setAccessibilityRole(.splitter) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: axis == .vertical ? .resizeLeftRight : .resizeUpDown) }
    override func mouseDown(with event: NSEvent) { origin = (event.locationInWindow, value); needsDisplay = true }
    override func mouseDragged(with event: NSEvent) {
        guard let (point, initial) = origin else { return }
        let delta = axis == .vertical ? (event.locationInWindow.x - point.x) * (reverse ? -1 : 1) : event.locationInWindow.y - point.y
        change?(min(limits.upperBound, max(limits.lowerBound, initial + delta)))
    }
    override func mouseUp(with event: NSEvent) { mouseDragged(with: event); origin = nil; needsDisplay = true }
    override func accessibilityPerformIncrement() -> Bool { change?(min(limits.upperBound, value + 20)); return true }
    override func accessibilityPerformDecrement() -> Bool { change?(max(limits.lowerBound, value - 20)); return true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.2).setFill(); bounds.fill()
        (origin == nil ? NSColor.separatorColor : NSColor.systemCyan).setFill()
        let line = axis == .vertical ? NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height)
            : NSRect(x: 0, y: bounds.midY - 0.5, width: bounds.width, height: 1)
        line.fill()
    }
}
