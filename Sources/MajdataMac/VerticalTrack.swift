import SwiftUI
import AppKit
import QuartzCore
import MajdataCore

/// Columns of the vertical track: bar gutter | keys 8…1 | Touch | BPM. Time runs upward.
struct VerticalTrackLayout: Equatable {
    static let gutter = 34.0, aux = 46.0
    /// Place of a touch among the touches that share its instant; they sit side by side so each can be clicked.
    struct TouchSlot: Equatable { var index: Int; var count: Int }
    var size: CGSize
    var viewport: TimelineViewport
    var touchSlots: [Int: TouchSlot] = [:]
    static func touchSlots(for notes: [Note]) -> [Int: TouchSlot] {
        var slots: [Int: TouchSlot] = [:]
        let touches = notes.filter { $0.kind == .touch || $0.kind == .touchHold }
        for group in Dictionary(grouping: touches, by: { Int64(($0.time * 1_000_000).rounded()) }).values where group.count > 1 {
            for (index, note) in group.sorted(by: { $0.id < $1.id }).enumerated() { slots[note.id] = TouchSlot(index: index, count: group.count) }
        }
        return slots
    }
    /// Three or more touches at one instant are drawn as a small map of the stage, one dot per zone:
    /// no row of glyphs stays readable when a chart fills every zone at once.
    func inCluster(_ note: Note) -> Bool { (touchSlots[note.id]?.count ?? 1) > 2 }
    static let clusterRadius = aux - 5
    var clusterX: Double { keysEnd + Self.aux }
    /// Glyph size of a touch: full size alone, half the column for a pair, a dot inside a cluster.
    func touchSize(_ note: Note) -> Double {
        let full = min(headSize, Self.aux - 10)
        guard let slot = touchSlots[note.id] else { return full }
        return slot.count > 2 ? 8 : min(full, (Self.aux - 4) / 2 - 2)
    }
    var laneWidth: Double { max(12, (size.width - Self.gutter - Self.aux * 2) / 8) }
    var keysEnd: Double { Self.gutter + laneWidth * 8 }
    var touchX: Double { keysEnd + Self.aux / 2 }
    var headSize: Double { min(40, laneWidth - 6) }
    func x(lane: Int) -> Double { Self.gutter + (Double(8 - min(8, max(1, lane))) + 0.5) * laneWidth }
    func y(_ time: Double) -> Double { size.height - viewport.x(at: time, width: size.height) }
    func time(atY y: Double) -> Double { viewport.time(at: size.height - y, width: size.height) }
    /// Key 1…8 under `x`; nil over the gutter, Touch and BPM columns.
    func lane(atX x: Double) -> Int? {
        let index = Int(floor((x - Self.gutter) / laneWidth))
        return (0..<8).contains(index) ? 8 - index : nil
    }
    func isTouch(_ note: Note) -> Bool { note.kind == .touch || note.kind == .touchHold }
    func center(of note: Note) -> CGPoint {
        guard isTouch(note) else { return CGPoint(x: x(lane: note.lane), y: y(note.time)) }
        guard let slot = touchSlots[note.id] else { return CGPoint(x: touchX, y: y(note.time)) }
        if slot.count > 2 {
            // Same placement as on the stage: the outer A / D ring sits at 0.85 of the radius.
            let zone = SlideGeometry.touch(note.area, lane: note.lane), scale = Self.clusterRadius / 0.95
            return CGPoint(x: clusterX + zone.x * scale, y: y(note.time) + zone.y * scale)
        }
        let size = touchSize(note)
        return CGPoint(x: keysEnd + 2 + (size + 2) * (Double(slot.index) + 0.5), y: y(note.time))
    }
    /// The note under the pointer. Holds are hit along their whole body, everything else on its head.
    func note(at point: CGPoint, in notes: [Note]) -> Note? {
        var best: (note: Note, distance: Double)?
        for note in notes {
            let head = center(of: note), reach = (isTouch(note) ? touchSize(note) : headSize) / 2 + (touchSlots[note.id] == nil ? 3 : 1)
            guard abs(point.x - head.x) <= reach else { continue }
            let sustained = note.kind == .hold || note.kind == .touchHold
            let top = sustained ? y(note.endTime) : head.y
            guard point.y >= top - reach, point.y <= head.y + reach else { continue }
            let distance = Double(abs(point.y - head.y))
            if best == nil || Self.prefers(note, distance, over: best!.note, best!.distance) { best = (note, distance) }
        }
        return best?.note
    }
    /// Tie-break when a click lands on more than one note (a Tap sitting on a Hold body, stacked Touches).
    // TODO(Daniel): 这是你的取舍。现在是「离音符头最近的赢」；你可以改成「短音符优先于长押」之类的规则。
    static func prefers(_ a: Note, _ aDistance: Double, over b: Note, _ bDistance: Double) -> Bool {
        aDistance < bDistance
    }
}

struct VerticalTrackView: View {
    var model: StudioModel
    var body: some View {
        VerticalTrackSurface(model: model, time: model.currentTime, running: model.isPlaying, revision: model.chart.renderRevision,
                             selection: model.selectedRange, span: model.trackSpan, start: model.trackStart,
                             meter: model.timelineBeatsPerBar, skin: model.skinImages.count,
                             tool: model.trackTool, divisor: model.trackDivisor, pending: model.pendingSlide)
    }
}

private struct VerticalTrackSurface: NSViewRepresentable {
    var model: StudioModel
    // Unused by the view itself: reading them makes SwiftUI call updateNSView when they change.
    var time: Double, running: Bool, revision: UUID, selection: NSRange, span: Double, start: Double, meter: Int, skin: Int
    var tool: TrackTool, divisor: Int, pending: PendingSlide?
    func makeNSView(context: Context) -> VerticalTrackCanvas { VerticalTrackCanvas(model: model) }
    func updateNSView(_ view: VerticalTrackCanvas, context: Context) { view.update(model) }
    static func dismantleNSView(_ view: VerticalTrackCanvas, coordinator: ()) { view.stop() }
}

/// Draws the whole visible range each frame; only a few bars of notes are on screen at a time.
@MainActor final class VerticalTrackCanvas: NSView {
    private var model: StudioModel
    private var link: CADisplayLink?
    private var musical: MusicalTimeline
    private var chartRevision: UUID
    private var touchSlots: [Int: VerticalTrackLayout.TouchSlot]
    private var noteIndex: TrackNoteIndex
    private var scrubbing = false
    private var resumeAfterScrub = false
    private var displayTime = 0.0
    /// Hold being dragged out: its key, where the button went down and where the pointer is now.
    private var holdDrag: (lane: Int, start: Double, end: Double)?
    /// Hold or touch hold whose far end is being dragged to a new length.
    private var resizeDrag: (note: Note, end: Double)?
    private var hover: CGPoint?
    private var tracking: NSTrackingArea?
    /// Bottom-edge time while playback scrolls the track. Kept here so the model is not written every frame.
    private var liveStart: Double?
    /// Where the playhead sits while following: a quarter of the way up, with the coming notes above it.
    static let playheadFraction = 0.25
    private let labelText = TimelineText(size: 10, bold: true)
    private let gridText = TimelineText(size: 9)
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var viewport: TimelineViewport {
        // Two screens of empty track past the end, so a chart can grow there before any music sets its length.
        let upper = model.rangeEnd + model.trackSpan * 2, length = max(0.001, upper - model.rangeStart)
        return TimelineViewport(lower: model.rangeStart, upper: upper, zoom: length / model.trackSpan, start: liveStart ?? model.trackStart)
    }
    var layout: VerticalTrackLayout {
        // A mouse edit reparses synchronously, before SwiftUI gets to call update().
        if chartRevision != model.chart.renderRevision {
            chartRevision = model.chart.renderRevision; musical = MusicalTimeline(model.chart)
            touchSlots = VerticalTrackLayout.touchSlots(for: model.chart.notes)
            noteIndex = TrackNoteIndex(model.chart.notes)
        }
        return VerticalTrackLayout(size: bounds.size, viewport: viewport, touchSlots: touchSlots)
    }
    init(model: StudioModel) {
        self.model = model; musical = MusicalTimeline(model.chart); chartRevision = model.chart.renderRevision
        touchSlots = VerticalTrackLayout.touchSlots(for: model.chart.notes)
        noteIndex = TrackNoteIndex(model.chart.notes)
        super.init(frame: .zero)
        // AppKit views draw outside their bounds unless asked not to; long notes would spill over the transport bar.
        clipsToBounds = true
        setAccessibilityElement(true); setAccessibilityLabel("竖谱：点击放置或选中音符，右键删除，拖动小节号一栏定位，滚动平移，Option 加滚动缩放")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(_ model: StudioModel) {
        self.model = model
        if chartRevision != model.chart.renderRevision {
            chartRevision = model.chart.renderRevision; musical = MusicalTimeline(model.chart)
            touchSlots = VerticalTrackLayout.touchSlots(for: model.chart.notes)
            noteIndex = TrackNoteIndex(model.chart.notes)
        }
        displayTime = model.playbackTime
        if !scrubbing { follow(displayTime) }
        let paused = !model.isPlaying
        if link?.isPaused != paused { link?.isPaused = paused }
        needsDisplay = true
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); stop()
        guard window != nil else { return }
        link = displayLink(target: self, selector: #selector(refresh(_:)))
        let rate = Float(min(120, window?.screen?.maximumFramesPerSecond ?? 60))
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, rate), maximum: rate, preferred: rate)
        link?.add(to: .main, forMode: .common); link?.isPaused = !model.isPlaying
    }
    @objc private func refresh(_ link: CADisplayLink) {
        guard window?.occlusionState.contains(.visible) == true, !isHiddenOrHasHiddenAncestor else { return }
        displayTime = model.playbackTime
        if !scrubbing { follow(displayTime) }
        needsDisplay = true
    }
    func stop() { link?.invalidate(); link = nil }
    /// While playing the track scrolls under a fixed playhead; while paused it only moves when the playhead leaves the view.
    private func follow(_ time: Double) {
        guard model.timelineFollow else { settle(); return }
        if model.isPlaying { liveStart = time - model.trackSpan * Self.playheadFraction; return }
        settle()
        let view = viewport
        if time < view.start || time > view.start + view.span * 0.9 { model.trackStart = time - view.span * Self.playheadFraction }
    }
    /// Hands the scrolled position back to the model once playback stops driving it.
    private func settle() {
        guard let start = liveStart else { return }
        liveStart = nil; model.trackStart = start
    }
    private func scrub(_ point: CGPoint) {
        let time = layout.time(atY: point.y)
        model.seek(model.timelineSnap ? musical.nearestCell(to: time) : time)
        displayTime = model.currentTime; needsDisplay = true
    }
    private func note(at point: CGPoint) -> Note? {
        let layout = layout, view = layout.viewport
        return layout.note(at: point, in: noteIndex.visible(from: view.start, through: view.start + view.span))
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseMoved(with event: NSEvent) { hover = convert(event.locationInWindow, from: nil); if model.trackTool.placesNotes { needsDisplay = true } }
    override func mouseExited(with event: NSEvent) { hover = nil; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil), layout = layout
        if let note = endHandle(at: point, layout) { model.select(note); resizeDrag = (note, note.endTime); needsDisplay = true; return }
        if let note = note(at: point) {
            // With the Slide tool a click on a star starts another tail from the same head.
            if model.trackTool == .slide, !layout.isTouch(note), model.slideHead(lane: note.lane, at: note.time) != nil {
                model.place(lane: note.lane, at: note.time)
            } else { model.select(note) }
            needsDisplay = true; return
        }
        // The bar-number gutter and the BPM column always scrub, whatever tool is active.
        if model.trackTool.placesNotes, let lane = layout.lane(atX: point.x) {
            let time = model.gridTime(layout.time(atY: point.y))
            if model.trackTool == .hold { holdDrag = (lane, time, time) } else { model.place(lane: lane, at: time) }
            needsDisplay = true; return
        }
        scrubbing = true; resumeAfterScrub = model.isPlaying
        model.pause(); scrub(point)
    }
    /// The far end of a hold or touch hold, away from its head so a short note can still be clicked whole.
    private func endHandle(at point: CGPoint, _ layout: VerticalTrackLayout) -> Note? {
        let view = layout.viewport
        return noteIndex.visible(from: view.start, through: view.start + view.span).first { note in
            guard note.kind == .hold || note.kind == .touchHold, !layout.inCluster(note), note.token != nil,
                  note.endTime >= view.start, note.time <= view.start + view.span else { return false }
            let head = layout.center(of: note), end = layout.y(note.endTime), size = layout.isTouch(note) ? layout.touchSize(note) : layout.headSize
            return abs(point.x - head.x) <= size / 2 + 3 && abs(point.y - end) <= 8 && head.y - end > size * 0.75
        }
    }
    override func rightMouseDown(with event: NSEvent) {
        if let note = note(at: convert(event.locationInWindow, from: nil)) { model.delete(note); needsDisplay = true }
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if resizeDrag != nil { resizeDrag?.end = model.gridTime(layout.time(atY: point.y)); needsDisplay = true }
        else if holdDrag != nil { holdDrag?.end = model.gridTime(layout.time(atY: point.y)); needsDisplay = true }
        else if scrubbing { scrub(point) }
    }
    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        switch (event.charactersIgnoringModifiers ?? "").lowercased() {
        case "z" where command: if event.modifierFlags.contains(.shift) { model.redoVisualEdit() } else { model.undoVisualEdit() }
        case _ where command: super.keyDown(with: event); return
        case "v": model.trackTool = .select
        case "1": model.trackTool = .tap
        case "2": model.trackTool = .hold
        case "3": model.trackTool = .slide
        case "4": model.trackTool = .touch
        case "5": model.trackTool = .touchHold
        case "b": model.toggleFlag("b")
        case "x": model.toggleFlag("x")
        case "f": model.toggleFlag("f")
        case "w": model.toggleFlag("w")
        case "h": model.toggleFlag("h")
        case "s": model.toggleFlag("s")
        case "o": model.slideWaitsOneBeat.toggle()
        case "\r": model.pendingSlide = nil
        case " ": model.togglePlayback()
        case "\u{1B}": model.pendingSlide = nil
        case "\u{7F}", "\u{F728}": model.deleteSelectedNotes()
        default: super.keyDown(with: event); return
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if let drag = resizeDrag {
            resizeDrag = nil
            if abs(drag.end - drag.note.endTime) > 1e-6 { model.resize(drag.note, until: drag.end) }
            needsDisplay = true; return
        }
        if let drag = holdDrag {
            holdDrag = nil; model.place(lane: drag.lane, at: min(drag.start, drag.end), until: max(drag.start, drag.end)); needsDisplay = true; return
        }
        guard scrubbing else { return }
        scrub(convert(event.locationInWindow, from: nil)); scrubbing = false
        if resumeAfterScrub { model.play() }
        resumeAfterScrub = false
    }
    private func zoom(by factor: Double, at point: CGPoint) {
        let anchor = layout.time(atY: point.y), fraction = 1 - min(1, max(0, point.y / max(1, bounds.height)))
        liveStart = nil
        model.trackSpan = min(60, max(0.5, model.trackSpan * factor))
        model.trackStart = anchor - model.trackSpan * fraction
        model.timelineFollow = false; needsDisplay = true
    }
    override func magnify(with event: NSEvent) { zoom(by: exp(-event.magnification * 2), at: convert(event.locationInWindow, from: nil)) }
    override func scrollWheel(with event: NSEvent) {
        guard !scrubbing else { return }
        if event.modifierFlags.contains(.option) {
            zoom(by: exp(event.scrollingDeltaY * 0.015), at: convert(event.locationInWindow, from: nil)); return
        }
        let view = viewport, distance = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 12)
        liveStart = nil
        // Content follows the fingers: dragging it down brings later bars in from the top.
        model.trackStart = TimelineViewport(lower: view.lower, upper: view.upper, zoom: (view.upper - view.lower) / view.span,
            start: view.start + distance / max(1, bounds.height) * view.span).start
        model.timelineFollow = false; needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let layout = layout, view = layout.viewport, width = bounds.width, height = bounds.height
        let gutter = VerticalTrackLayout.gutter, lane = layout.laneWidth, keysEnd = layout.keysEnd
        context.clear(bounds)
        NSColor.textBackgroundColor.withAlphaComponent(0.4).setFill(); bounds.fill()
        NSColor.labelColor.withAlphaComponent(0.045).setFill()
        NSRect(x: 0, y: 0, width: gutter, height: height).fill()
        NSRect(x: keysEnd, y: 0, width: width - keysEnd, height: height).fill()
        func vertical(_ x: Double, _ alpha: Double) {
            NSColor.labelColor.withAlphaComponent(alpha).setFill(); NSRect(x: x, y: 0, width: 1, height: height).fill()
        }
        func horizontal(_ y: Double, from x: Double, to end: Double, _ alpha: Double) {
            NSColor.labelColor.withAlphaComponent(alpha).setFill(); NSRect(x: x, y: y, width: end - x, height: 1).fill()
        }
        for index in 0...8 { vertical(gutter + Double(index) * lane, index == 0 || index == 8 ? 0.32 : 0.08) }
        vertical(keysEnd + VerticalTrackLayout.aux, 0.08)
        for item in musical.grid(in: view, width: height, beatsPerBar: model.timelineBeatsPerBar) {
            let y = layout.y(item.time)
            switch item.kind {
            case .bar:
                horizontal(y, from: gutter, to: width, 0.42)
                let text = gridText.layout("\(item.bar)")
                gridText.draw(text, at: CGPoint(x: (gutter - text.width) / 2, y: y - gridText.height - 3), color: .labelColor, in: context)
            case .beat: horizontal(y, from: gutter, to: width, 0.13)
            case .subdivision: break
            }
        }
        // The placement grid: one line per 1/divisor step, hidden when zoomed out too far to tell them apart.
        let step = musical.step(at: view.start + view.span / 2, divisor: model.trackDivisor)
        if step > 0, step / view.span * height >= 5 {
            for time in musical.divisions(in: view, divisor: model.trackDivisor) { horizontal(layout.y(time), from: gutter, to: keysEnd, 0.055) }
        }
        var lastBPM = -1.0, lastDivider = -1.0, lastY = Double.infinity
        for point in model.chart.timings {
            let changed = point.bpm != lastBPM || point.subdivision != lastDivider
            let bpmChanged = point.bpm != lastBPM
            lastBPM = point.bpm; lastDivider = point.subdivision
            let y = layout.y(point.time)
            guard changed, y >= 0, y <= height, lastY - y > 24 else { continue }
            let text = gridText.layout(bpmChanged ? String(format: "%.4g", point.bpm) : String(format: "{%.3g}", point.subdivision))
            gridText.draw(text, at: CGPoint(x: keysEnd + VerticalTrackLayout.aux * 1.5 - text.width / 2, y: y - gridText.height - 2),
                          color: bpmChanged ? .labelColor : .systemTeal, in: context)
            lastY = y
        }
        let notes = noteIndex.visible(from: view.start, through: view.start + view.span)
        for note in notes where note.kind == .hold { drawHold(note, layout) }
        for note in notes where note.kind == .touchHold { drawTouchHoldBody(note, layout) }
        for note in notes where note.kind == .slide { drawSlideTail(note, layout) }
        // A slide's star is its head Tap; the slide note itself only owns the tail, so headless slides stay headless.
        drawTouchLabels(notes, layout, context)
        for note in notes where note.kind != .hold && note.kind != .slide { drawHead(note, layout, context) }
        for note in notes where model.isSelected(note) { drawSelection(note, layout) }
        drawGhosts(layout)
        if let time = musical.sourceTime(at: model.selectedRange.location) { cursor(time, layout, color: .systemPurple, dashed: true, context) }
        cursor(model.isPlaying ? displayTime : model.currentTime, layout, color: .systemCyan, dashed: false, context)
    }
    /// What the next click would do: the hover ring, the hold being dragged, the star waiting for its tail.
    private func drawGhosts(_ layout: VerticalTrackLayout) {
        let size = layout.headSize
        func ring(_ lane: Int, _ time: Double, dashed: Bool) {
            let path = NSBezierPath(ovalIn: NSRect(x: layout.x(lane: lane) - size / 2, y: layout.y(time) - size / 2, width: size, height: size))
            NSColor.controlAccentColor.setStroke(); path.lineWidth = 2
            if dashed { path.setLineDash([4, 3], count: 2, phase: 0) }; path.stroke()
        }
        func span(_ x: Double, _ width: Double, from: Double, to: Double) {
            let top = layout.y(max(from, to)) - width / 2, bottom = layout.y(min(from, to)) + width / 2
            let body = NSBezierPath(roundedRect: NSRect(x: x - width / 2, y: top, width: width, height: bottom - top), xRadius: width / 2, yRadius: width / 2)
            NSColor.controlAccentColor.withAlphaComponent(0.25).setFill(); body.fill()
            NSColor.controlAccentColor.setStroke(); body.lineWidth = 2; body.stroke()
        }
        if let drag = resizeDrag {
            let touch = layout.isTouch(drag.note)
            span(layout.center(of: drag.note).x, touch ? layout.touchSize(drag.note) : size, from: drag.note.time, to: max(drag.end, drag.note.time))
        } else if let drag = holdDrag {
            span(layout.x(lane: drag.lane), size, from: drag.start, to: drag.end)
        } else if let pending = model.pendingSlide {
            let rect = NSRect(x: layout.x(lane: pending.lane) - size / 2, y: layout.y(pending.time) - size / 2, width: size, height: size)
            model.skinImages["star"]?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.7, respectFlipped: true, hints: nil)
            ring(pending.lane, pending.time, dashed: true)
        } else if model.trackTool.placesNotes, model.trackTool != .touch, model.trackTool != .touchHold,
                  let hover, let lane = layout.lane(atX: hover.x), note(at: hover) == nil {
            ring(lane, model.gridTime(layout.time(atY: hover.y)), dashed: true)
        }
    }
    private func sprite(_ name: String, _ note: Note) -> NSImage? {
        let variant = note.isBreak ? "_break" : (note.isEach ? "_each" : "")
        return model.skinImages[name + variant] ?? model.skinImages[name]
    }
    private func accent(_ note: Note) -> NSColor { note.isBreak ? .systemOrange : (note.isEach ? .systemYellow : .systemCyan) }
    private func drawHold(_ note: Note, _ layout: VerticalTrackLayout) {
        guard let image = sprite("hold", note) else { return }
        let size = layout.headSize, x = layout.x(lane: note.lane) - size / 2
        let top = layout.y(note.endTime) - size / 2, bottom = layout.y(note.time) + size / 2
        let cap = min(size / 2, (bottom - top) / 2), source = image.size, sourceCap = source.height * 0.305
        // Three slices keep the pointed ends of the hexagon undistorted while the body stretches.
        image.draw(in: NSRect(x: x, y: top, width: size, height: cap), from: NSRect(x: 0, y: source.height - sourceCap, width: source.width, height: sourceCap),
                   operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        image.draw(in: NSRect(x: x, y: top + cap, width: size, height: max(0, bottom - top - cap * 2)),
                   from: NSRect(x: 0, y: sourceCap, width: source.width, height: source.height - sourceCap * 2),
                   operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        image.draw(in: NSRect(x: x, y: bottom - cap, width: size, height: cap), from: NSRect(x: 0, y: 0, width: source.width, height: sourceCap),
                   operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    private func drawTouchHoldBody(_ note: Note, _ layout: VerticalTrackLayout) {
        let top = layout.y(note.endTime), bottom = layout.y(note.time)
        NSColor.systemPurple.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: NSRect(x: layout.center(of: note).x - 3, y: top, width: 6, height: max(1, bottom - top)), xRadius: 3, yRadius: 3).fill()
    }
    /// The tail follows the star: at every moment it sits over the key the star is nearest to on the stage,
    /// so a slide that sweeps round the ring is drawn sweeping across the lanes. The wait before it moves is fainter.
    private func drawSlideTail(_ note: Note, _ layout: VerticalTrackLayout) {
        let color = accent(note), head = layout.x(lane: note.lane)
        guard let first = note.segments.first else { return }
        color.withAlphaComponent(0.28).setFill()
        let waitTop = layout.y(first.startTime), waitBottom = layout.y(note.time)
        NSBezierPath(roundedRect: NSRect(x: head - 2, y: waitTop, width: 4, height: max(1, waitBottom - waitTop)), xRadius: 2, yRadius: 2).fill()
        let path = NSBezierPath(); path.lineWidth = 4; path.lineJoinStyle = .round; path.lineCapStyle = .round
        for segment in note.segments {
            for branch in segment.shape == "w" ? [-1, 0, 1] : [0] {
                let points = SlideGeometry.points(for: segment, branch: branch)
                guard points.count > 1 else { continue }
                var previous: Double?
                for step in 0...32 {
                    let progress = Double(step) / 32, point = SlideGeometry.position(on: points, progress: progress)
                    // Key n sits at n * 45 - 112.5 degrees; near the centre the direction means nothing, so hold the last one.
                    var position = previous ?? Double(segment.start)
                    if hypot(point.x, point.y) > 0.3 {
                        position = (atan2(point.y, point.x) * 180 / .pi + 112.5) / 45
                        position = position - 8 * floor((position - 0.5) / 8)
                    }
                    let spot = CGPoint(x: VerticalTrackLayout.gutter + (8.5 - position) * layout.laneWidth,
                                       y: layout.y(segment.startTime + segment.duration * progress))
                    // Passing between keys 8 and 1 wraps round the edge of the track: lift the pen instead of crossing it.
                    if let previous, abs(previous - position) < 4 { path.line(to: spot) } else { path.move(to: spot) }
                    previous = position
                }
                let end = (segment.end - 1 + branch + 8) % 8 + 1, y = layout.y(segment.startTime + segment.duration)
                color.setFill(); NSBezierPath(ovalIn: NSRect(x: layout.x(lane: end) - 4.5, y: y - 4.5, width: 9, height: 9)).fill()
            }
        }
        color.withAlphaComponent(0.7).setStroke(); path.stroke()
    }
    private func drawHead(_ note: Note, _ layout: VerticalTrackLayout, _ context: CGContext) {
        let center = layout.center(of: note), size = layout.headSize
        if layout.inCluster(note) {
            let dot = NSBezierPath(ovalIn: NSRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
            (note.kind == .touchHold ? NSColor.systemPurple : accent(note)).setFill(); dot.fill()
            NSColor.textBackgroundColor.setStroke(); dot.lineWidth = 1; dot.stroke()
            return
        }
        if layout.isTouch(note) {
            guard let image = sprite("touch", note) else { return }
            let glyph = layout.touchSize(note), w = glyph * 0.56, h = w * image.size.height / max(1, image.size.width)
            for quarter in 0..<4 {
                context.saveGState()
                context.translateBy(x: center.x, y: center.y); context.rotate(by: Double(quarter) * .pi / 2)
                // Not respecting the flipped view turns each triangle's apex toward the centre.
                image.draw(in: NSRect(x: -w / 2, y: -glyph / 2, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
                context.restoreGState()
            }
            return
        }
        let star = note.kind == .slide || note.isStar
        let rect = NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        sprite(star ? "star" : "tap", note)?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if note.isEX { model.skinImages[star ? "star_ex" : "tap_ex"]?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
    }
    /// One label per instant: touches that share a time share the Touch column, so their zones are listed together.
    private func drawTouchLabels(_ notes: [Note], _ layout: VerticalTrackLayout, _ context: CGContext) {
        let glyph = min(layout.headSize, VerticalTrackLayout.aux - 10)
        let groups = Dictionary(grouping: notes.filter(layout.isTouch), by: { Int64(($0.time * 1_000_000).rounded()) })
        for group in groups.values {
            guard let first = group.first else { continue }
            if group.count > 2 {
                // The ring the dots sit in, drawn before them so they stay on top.
                let r = VerticalTrackLayout.clusterRadius
                let ring = NSBezierPath(ovalIn: NSRect(x: layout.clusterX - r, y: layout.y(first.time) - r, width: r * 2, height: r * 2))
                NSColor.textBackgroundColor.withAlphaComponent(0.9).setFill(); ring.fill()
                NSColor.labelColor.withAlphaComponent(0.35).setStroke(); ring.lineWidth = 1; ring.stroke()
                let count = gridText.layout("\(group.count)")
                gridText.draw(count, at: CGPoint(x: layout.clusterX - count.width / 2, y: layout.y(first.time) - r - gridText.height - 1), color: .labelColor, in: context)
                continue
            }
            let names = group.map { $0.area + ($0.area == "C" ? "" : String($0.lane)) }
            let text = gridText.layout(names.joined(separator: "/"))
            // Alone: beside the glyph. Sharing the column: above the row, where the glyphs leave room.
            let origin = group.count == 1 ? CGPoint(x: layout.touchX + glyph / 2 - 2, y: layout.y(first.time) - glyph / 2 - 4)
                : CGPoint(x: layout.keysEnd + 3, y: layout.y(first.time) - layout.touchSize(first) / 2 - gridText.height - 1)
            gridText.draw(text, at: origin, color: .labelColor, in: context)
        }
    }
    private func drawSelection(_ note: Note, _ layout: VerticalTrackLayout) {
        let center = layout.center(of: note), size = (layout.isTouch(note) ? layout.touchSize(note) : layout.headSize) + 8
        let sustained = (note.kind == .hold || note.kind == .touchHold) && !layout.inCluster(note)
        let top = (sustained ? layout.y(note.endTime) : center.y) - size / 2
        let ring = NSBezierPath(roundedRect: NSRect(x: center.x - size / 2, y: top, width: size, height: center.y + size / 2 - top), xRadius: size / 2, yRadius: size / 2)
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill(); ring.fill()
        NSColor.controlAccentColor.setStroke(); ring.lineWidth = 1.5; ring.stroke()
    }
    private func cursor(_ time: Double, _ layout: VerticalTrackLayout, color: NSColor, dashed: Bool, _ context: CGContext) {
        guard time.isFinite else { return }
        let y = layout.y(time)
        guard y.isFinite, y >= 0, y <= bounds.height else { return }
        color.setStroke()
        let line = NSBezierPath(); line.move(to: CGPoint(x: 0, y: y)); line.line(to: CGPoint(x: bounds.width, y: y)); line.lineWidth = dashed ? 1.5 : 2
        if dashed { line.setLineDash([4, 3], count: 2, phase: 0) }; line.stroke()
        guard !dashed else { return }
        let text = labelText.layout(StudioModel.timeLabel(time))
        let rect = NSRect(x: bounds.width - text.width - 10, y: max(0, y - 17), width: text.width + 8, height: 15)
        NSColor.systemTeal.setFill(); NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        labelText.draw(text, at: CGPoint(x: rect.minX + 4, y: rect.minY + 2), color: .white, in: context)
    }
}
