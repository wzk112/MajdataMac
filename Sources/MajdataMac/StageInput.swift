import SwiftUI
import AppKit
import MajdataCore

/// Mouse input on the stage for the tools that need zones: Touch placement and drawing a star's tail.
/// It sits above the live stage and lets clicks through whenever neither is active.
struct StageInputSurface: NSViewRepresentable {
    var model: StudioModel
    var tool: TrackTool
    var pending: PendingSlide?
    func makeNSView(context: Context) -> StageInputView { StageInputView(model: model) }
    func updateNSView(_ view: StageInputView, context: Context) { view.model = model; view.needsDisplay = true }
}

@MainActor final class StageInputView: NSView {
    var model: StudioModel
    /// Zones crossed by the stroke in order, and the stroke itself in view coordinates.
    private var crossed: [String] = []
    private var stroke: [CGPoint] = []
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    init(model: StudioModel) { self.model = model; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private var active: Bool { model.pendingSlide != nil || model.trackTool == .touch || model.trackTool == .touchHold }
    override func hitTest(_ point: NSPoint) -> NSView? { active ? super.hitTest(point) : nil }
    /// Same scale as `StageDrawing`: the judgement ring has radius 4.8 world units.
    private var unit: Double { min(bounds.width, bounds.height) / 11.465929 }
    private func world(_ point: CGPoint) -> Point { Point((point.x - bounds.midX) / unit, (point.y - bounds.midY) / unit) }
    private func name(_ polygon: SensorPolygon) -> String { polygon.name.hasPrefix("C") ? "C" : polygon.name }
    private func zones(at point: CGPoint, radius: Double) -> [String] {
        let ids = SensorGeometry.contacts(at: world(point), slide: true, radius: radius)
        return SensorGeometry.polygons.filter { ids.contains($0.id) }.map(name)
    }
    /// Key whose direction is closest to the point, for a stroke that ends between zones.
    private func key(toward point: CGPoint) -> Int {
        let p = world(point), degrees = atan2(p.y, p.x) * 180 / .pi
        return ((Int(((degrees + 112.5) / 45).rounded()) - 1) % 8 + 8) % 8 + 1
    }
    private func extend(_ point: CGPoint) {
        stroke.append(point)
        for zone in zones(at: point, radius: 0.2) where crossed.last != zone { crossed.append(zone) }
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if model.pendingSlide != nil { crossed = []; stroke = []; extend(point); return }
        if let zone = zones(at: point, radius: 0).first { model.placeTouch(zone: zone) } else { NSSound.beep() }
    }
    override func mouseDragged(with event: NSEvent) { if model.pendingSlide != nil { extend(convert(event.locationInWindow, from: nil)) } }
    override func mouseUp(with event: NSEvent) {
        guard model.pendingSlide != nil, !stroke.isEmpty else { return }
        let point = convert(event.locationInWindow, from: nil); extend(point)
        // The tail ends on the last outer key the stroke reached; otherwise on the key it was heading for.
        let end = crossed.last(where: { $0.hasPrefix("A") }).flatMap { Int($0.dropFirst()) } ?? key(toward: point)
        let points = stroke.map { point in
            let p = world(point)
            return Point(p.x / 4.8, p.y / 4.8)
        }
        model.finishSlide(zones: Set(crossed), end: end, stroke: points)
        crossed = []; stroke = []; needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard active, let context = NSGraphicsContext.current?.cgContext else { return }
        let unit = unit
        func path(_ polygon: SensorPolygon) -> NSBezierPath {
            let path = NSBezierPath()
            for (i, v) in polygon.vertices.enumerated() {
                let p = CGPoint(x: bounds.midX + v.x * unit, y: bounds.midY + v.y * unit)
                if i == 0 { path.move(to: p) } else { path.line(to: p) }
            }
            path.close(); return path
        }
        let hit = Set(crossed)
        for polygon in SensorGeometry.polygons {
            let shape = path(polygon), on = hit.contains(name(polygon))
            if on { NSColor.systemCyan.withAlphaComponent(0.32).setFill(); shape.fill() }
            (on ? NSColor.systemCyan : NSColor.white.withAlphaComponent(0.55)).setStroke(); shape.lineWidth = on ? 2 : 1; shape.stroke()
        }
        if let pending = model.pendingSlide {
            let start = SlideGeometry.lane(pending.from ?? pending.lane, radius: 4.8), size = unit * 1.1
            let rect = NSRect(x: bounds.midX + start.x * unit - size / 2, y: bounds.midY + start.y * unit - size / 2, width: size, height: size)
            model.skinImages["star"]?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        guard stroke.count > 1 else { return }
        context.setStrokeColor(NSColor.systemCyan.cgColor); context.setLineWidth(4); context.setLineCap(.round); context.setLineJoin(.round)
        context.addLines(between: stroke); context.strokePath()
    }
}
