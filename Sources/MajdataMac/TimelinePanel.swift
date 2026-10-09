import SwiftUI
import AppKit
import QuartzCore
import MajdataCore

struct TimelinePanel: View {
    @Bindable var model: StudioModel
    private var viewport: TimelineViewport {
        TimelineViewport(lower: model.rangeStart, upper: model.rangeEnd, zoom: model.timelineZoom, start: model.timelineStart)
    }
    private func zoom(_ factor: Double) {
        let old = viewport
        let anchor = min(old.start + old.span, max(old.start, model.currentTime))
        model.timelineZoom = min(128, max(1, model.timelineZoom * factor))
        model.timelineStart = old.zoomed(to: model.timelineZoom, anchor: anchor, fraction: (anchor - old.start) / old.span).start
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("时间轴").fontWeight(.semibold)
                Label("播放", systemImage: "line.diagonal").foregroundStyle(.cyan)
                Label("源码光标", systemImage: "line.diagonal").foregroundStyle(.purple)
                Spacer(minLength: 4)
                Picker("每小节", selection: $model.timelineBeatsPerBar) {
                    ForEach(2...12, id: \.self) { Text("\($0) 拍").tag($0) }
                }.frame(width: 104).help("小节显示按四分音符计拍；不修改 simai 的 {分音} 或音乐。")
                Toggle("吸附", isOn: $model.timelineSnap).toggleStyle(.checkbox).help("拖动定位吸附到源码中的分音位置")
                Toggle("翻页跟随", isOn: $model.timelineFollow).toggleStyle(.checkbox).help("播放线离开可见范围时翻页；手动平移后暂停跟随")
                Button { zoom(1 / 1.5) } label: { Image(systemName: "minus.magnifyingglass") }.help("缩小")
                Button { zoom(1.5) } label: { Image(systemName: "plus.magnifyingglass") }.help("放大")
                Button("全曲") { model.timelineZoom = 1; model.timelineStart = model.rangeStart }
            }.font(.caption2).buttonStyle(.plain).padding(.horizontal, 12).frame(height: 30)
            HStack(spacing: 14) {
                Label("Tap", systemImage: "circle.fill").foregroundStyle(.pink)
                Label("Hold", systemImage: "capsule.fill").foregroundStyle(.orange)
                Label("Slide", systemImage: "arrow.right").foregroundStyle(.teal)
                Label("Touch", systemImage: "diamond.fill").foregroundStyle(.purple)
                Label("TouchHold", systemImage: "diamond.lefthalf.filled").foregroundStyle(.purple)
                Label("BREAK", systemImage: "star.fill").foregroundStyle(.yellow)
                Spacer(minLength: 0)
            }.font(.system(size: 10, weight: .medium)).padding(.horizontal, 12).frame(height: 22)
            LiveTimelineSurface(model: model)
            HStack(spacing: 10) {
                Button("定位播放") { model.timelineStart = model.currentTime - viewport.span * 0.35 }
                Button("定位光标") {
                    if let time = MusicalTimeline(model.chart).sourceTime(at: model.selectedRange.location) {
                        model.timelineStart = time - viewport.span * 0.35; model.timelineFollow = false
                    }
                }
                if model.loopEnabled {
                    Button("A \(String(format: "%.2f", model.loopStart))") { model.loopStart = model.currentTime }
                    Button("B \(String(format: "%.2f", model.loopEnd))") { model.loopEnd = model.currentTime }
                }
                if model.timelineZoom > 1 {
                Text("可见范围").foregroundStyle(.secondary)
                Slider(value: Binding(get: { viewport.start }, set: { model.timelineStart = $0; model.timelineFollow = false }),
                       in: model.rangeStart...max(model.rangeStart + 0.000001, model.rangeEnd - viewport.span))
                    .accessibilityLabel("时间轴可见区间")
                } else {
                    Spacer(minLength: 0)
                    Text("双指捏合或 ⌥ 滚动缩放").foregroundStyle(.secondary)
                }
                Text(String(format: "%.1f–%.1f 秒 · %.1f×", viewport.start, viewport.start + viewport.span, model.timelineZoom))
                    .monospacedDigit().frame(minWidth: 145, alignment: .trailing)
            }.font(.caption2).buttonStyle(.plain).padding(.horizontal, 12).frame(height: 26)
        }.background(Color.primary.opacity(0.025))
    }
}

struct LiveTimelineSurface: View {
    var model: StudioModel
    var body: some View {
        TimelineSurface(model: model, time: model.currentTime, running: model.isPlaying)
    }
}

private struct TimelineSurface: NSViewRepresentable {
    var model: StudioModel
    var time: Double
    var running: Bool
    func makeNSView(context: Context) -> TimelineCanvas { TimelineCanvas(model: model) }
    func updateNSView(_ view: TimelineCanvas, context: Context) { view.update(model) }
    static func dismantleNSView(_ view: TimelineCanvas, coordinator: ()) { view.stop() }
}

/// AppKit captures the mouse for a whole drag. Only the two cursors redraw every display frame;
/// waveform, notes and grid are cached until the viewport or chart changes.
@MainActor final class TimelineCanvas: NSView {
    private var model: StudioModel
    private var link: CADisplayLink?
    private var musical: MusicalTimeline
    private var chartRevision: UUID
    private var cacheKey: CacheKey?
    private var cached: NSImage?
    private(set) var backgroundRenderCount = 0
    private var dragViewport: TimelineViewport?
    private var dragX = 0.0
    private var resumeAfterDrag = false
    private var displayTime: Double = 0
    private struct CacheKey: Equatable {
        var revision: UUID; var audio: URL?; var viewport: TimelineViewport
        var size: CGSize; var meter: Int; var dark: Bool; var loop: Bool; var a: Double; var b: Double
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var viewport: TimelineViewport {
        dragViewport ?? TimelineViewport(lower: model.rangeStart, upper: model.rangeEnd, zoom: model.timelineZoom, start: model.timelineStart)
    }
    init(model: StudioModel) {
        self.model = model; musical = MusicalTimeline(model.chart); chartRevision = model.chart.renderRevision
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityLabel("时间轴：拖动定位，滚动平移，Option 加滚动缩放")
        toolTip = "拖动：定位播放，停在左右边缘自动滚动 · 滚动：平移 · Option + 滚动：以指针为中心缩放"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(_ model: StudioModel) {
        self.model = model
        if chartRevision != model.chart.renderRevision {
            chartRevision = model.chart.renderRevision; musical = MusicalTimeline(model.chart)
        }
        displayTime = model.playbackTime
        let paused = !model.isPlaying && dragViewport == nil
        if link?.isPaused != paused { link?.isPaused = paused }
        needsDisplay = true
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); stop()
        guard window != nil else { return }
        link = displayLink(target: self, selector: #selector(refresh(_:)))
        let rate = Float(min(120, window?.screen?.maximumFramesPerSecond ?? 60))
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, rate), maximum: rate, preferred: rate)
        link?.add(to: .main, forMode: .common); link?.isPaused = !model.isPlaying && dragViewport == nil
    }
    @objc private func refresh(_ link: CADisplayLink) {
        guard window?.occlusionState.contains(.visible) == true, !isHiddenOrHasHiddenAncestor else { return }
        if dragViewport != nil {
            advanceScrub(seconds: link.targetTimestamp - link.timestamp)
            return
        }
        displayTime = model.playbackTime
        let view = viewport
        if dragViewport == nil && model.timelineFollow && (displayTime < view.start || displayTime > view.start + view.span) {
            model.timelineStart = displayTime - view.span * 0.08
        }
        needsDisplay = true
    }
    func stop() { link?.invalidate(); link = nil }
    func beginScrub(x: Double) {
        guard dragViewport == nil else { return }
        dragViewport = viewport; resumeAfterDrag = model.isPlaying
        model.pause(); scrub(x: x)
        link?.isPaused = false
    }
    func scrub(x: Double) {
        guard let fixed = dragViewport else { return }
        dragX = x
        let time = fixed.time(at: x, width: bounds.width)
        model.seek(model.timelineSnap ? musical.nearestCell(to: time) : time)
        displayTime = model.currentTime; needsDisplay = true
    }
    func advanceScrub(seconds: Double) {
        guard let fixed = dragViewport else { return }
        let shifted = fixed.autoscrolled(pointerX: dragX, width: bounds.width, seconds: seconds)
        guard shifted != fixed else { return }
        dragViewport = shifted; model.timelineStart = shifted.start
        scrub(x: dragX)
    }
    func endScrub(x: Double) {
        guard dragViewport != nil else { return }
        scrub(x: x); dragViewport = nil
        if resumeAfterDrag { model.play() }
        resumeAfterDrag = false
        link?.isPaused = !model.isPlaying
    }
    override func mouseDown(with event: NSEvent) { beginScrub(x: convert(event.locationInWindow, from: nil).x) }
    override func mouseDragged(with event: NSEvent) { scrub(x: convert(event.locationInWindow, from: nil).x) }
    override func mouseUp(with event: NSEvent) { endScrub(x: convert(event.locationInWindow, from: nil).x) }
    override func magnify(with event: NSEvent) {
        guard dragViewport == nil else { return }
        let view = viewport
        let fraction = min(1, max(0, convert(event.locationInWindow, from: nil).x / max(1, bounds.width)))
        model.timelineZoom = min(128, max(1, model.timelineZoom * exp(event.magnification * 2)))
        model.timelineStart = view.zoomed(to: model.timelineZoom, anchor: view.start + view.span * fraction, fraction: fraction).start
        model.timelineFollow = false; needsDisplay = true
    }
    override func scrollWheel(with event: NSEvent) {
        guard dragViewport == nil else { return }
        let view = viewport
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        if event.modifierFlags.contains(.option) {
            let fraction = min(1, max(0, convert(event.locationInWindow, from: nil).x / max(1, bounds.width)))
            model.timelineZoom = min(128, max(1, model.timelineZoom * exp(-delta * 0.015)))
            model.timelineStart = view.zoomed(to: model.timelineZoom, anchor: view.start + view.span * fraction, fraction: fraction).start
        } else {
            let distance = delta * (event.hasPreciseScrollingDeltas ? 1 : 12)
            model.timelineStart = TimelineViewport(lower: view.lower, upper: view.upper, zoom: model.timelineZoom,
                start: view.start - distance / max(1, bounds.width) * view.span).start
        }
        model.timelineFollow = false; needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let view = viewport
        let key = CacheKey(revision: chartRevision, audio: model.prepared?.url, viewport: view, size: bounds.size,
            meter: model.timelineBeatsPerBar, dark: effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
            loop: model.loopEnabled, a: model.loopStart, b: model.loopEnd)
        if key != cacheKey {
            let image = NSImage(size: bounds.size)
            image.lockFocusFlipped(true); drawBackground(view); image.unlockFocus()
            cached = image; cacheKey = key; backgroundRenderCount += 1
        }
        cached?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if let time = musical.sourceTime(at: model.selectedRange.location) { cursor(time, viewport: view, color: .systemPurple, dashed: true) }
        cursor(model.isPlaying ? displayTime : model.currentTime, viewport: view, color: .systemCyan, dashed: false)
    }
    private func cursor(_ time: Double, viewport: TimelineViewport, color: NSColor, dashed: Bool) {
        let px = viewport.x(at: time, width: bounds.width)
        guard px >= 0, px <= bounds.width else { return }
        color.setStroke(); color.setFill()
        if !dashed {
            color.withAlphaComponent(0.16).setFill()
            NSRect(x: px - 4, y: 0, width: 8, height: bounds.height).fill(); color.setFill()
        }
        let line = NSBezierPath(); line.move(to: CGPoint(x: px, y: 0)); line.line(to: CGPoint(x: px, y: bounds.height)); line.lineWidth = dashed ? 2 : 3
        if dashed { line.setLineDash([4, 3], count: 2, phase: 0) }; line.stroke()
        let cap = NSBezierPath()
        let y = dashed ? bounds.height : 0, direction = dashed ? -1.0 : 1.0
        cap.move(to: CGPoint(x: px - 5, y: y)); cap.line(to: CGPoint(x: px + 5, y: y)); cap.line(to: CGPoint(x: px, y: y + 7 * direction)); cap.close(); cap.fill()
        if !dashed {
            let text = StudioModel.timeLabel(time) as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.white]
            let size = text.size(withAttributes: attrs)
            let rect = NSRect(x: min(bounds.width - size.width - 8, max(0, px + 6)), y: 2, width: size.width + 8, height: 16)
            NSColor.systemTeal.setFill(); NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            text.draw(at: CGPoint(x: rect.minX + 4, y: 3), withAttributes: attrs)
        }
    }
    private func drawBackground(_ view: TimelineViewport) {
        NSColor.controlBackgroundColor.setFill(); bounds.fill()
        let width = bounds.width, height = bounds.height
        let lanesHeight = max(24, height - 84), rowHeight = lanesHeight / 8
        for lane in 0..<8 {
            NSColor.labelColor.withAlphaComponent(lane.isMultiple(of: 2) ? 0.045 : 0.015).setFill()
            NSRect(x: 0, y: 32 + Double(lane) * rowHeight, width: width, height: rowHeight).fill()
        }
        func x(_ time: Double) -> Double { view.x(at: time, width: width) }
        func line(_ px: Double, _ y1: Double, _ y2: Double, _ color: NSColor, _ thickness: Double = 1) {
            color.setStroke(); let p = NSBezierPath(); p.move(to: CGPoint(x: px, y: y1)); p.line(to: CGPoint(x: px, y: y2)); p.lineWidth = thickness; p.stroke()
        }
        func label(_ text: String, _ px: Double, _ y: Double, _ color: NSColor = .secondaryLabelColor) {
            (text as NSString).draw(at: CGPoint(x: px, y: y), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular), .foregroundColor: color])
        }
        if model.loopEnabled && model.loopEnd > model.loopStart {
            NSColor.systemOrange.withAlphaComponent(0.08).setFill()
            NSRect(x: x(model.loopStart), y: 0, width: x(model.loopEnd) - x(model.loopStart), height: height).fill()
        }
        var lastLabel = -100.0
        for item in musical.grid(in: view, width: width, beatsPerBar: model.timelineBeatsPerBar) {
            let px = x(item.time)
            switch item.kind {
            case .bar:
                line(px, 30, height, .labelColor.withAlphaComponent(0.32))
                if px - lastLabel >= 56 { label("\(item.bar)", px + 3, 1, .labelColor); lastLabel = px }
            case .beat: line(px, 30, height, .labelColor.withAlphaComponent(0.13))
            case .subdivision: line(px, height - 17, height - 10, .secondaryLabelColor.withAlphaComponent(0.6))
            }
        }
        let secondStep = max(0.025, pow(2, ceil(log2(view.span / max(1, width / 85)))))
        var second = ceil(view.start / secondStep) * secondStep
        while second < view.start + view.span {
            label(String(format: "%.2fs", second), x(second) + 3, height - 11); second += secondStep
        }
        let waveCenter = height - 34, waveHeight = 15.0
        if !model.waveform.isEmpty {
            let wave = NSBezierPath()
            for px in stride(from: 0.0, to: width, by: 2) {
                let moment = view.start + px / width * view.span
                let audioStart = model.prepared?.startTime ?? model.rangeStart
                let duration = model.prepared?.duration ?? model.duration
                let index = Int((moment - audioStart) / max(0.001, duration) * Double(model.waveform.count))
                let value = index >= 0 && index < model.waveform.count ? Double(model.waveform[index]) : 0
                wave.move(to: CGPoint(x: px, y: waveCenter - value * waveHeight)); wave.line(to: CGPoint(x: px, y: waveCenter + value * waveHeight))
            }
            NSColor.systemTeal.withAlphaComponent(0.8).setStroke(); wave.lineWidth = 1.5; wave.stroke()
        }
        for lane in 1...8 {
            let y = 32 + Double(lane - 1) * rowHeight
            label("\(lane)", 3, y, .secondaryLabelColor)
        }
        for note in model.chart.notes where note.endTime >= view.start && note.time <= view.start + view.span {
            let px = max(0, x(note.time)), end = min(width, x(note.endTime))
            let y = 32 + (Double(max(0, note.lane - 1)) + 0.5) * rowHeight
            let radius = min(4, max(2.5, rowHeight * 0.32))
            let color: NSColor = note.kind == .hold ? .systemOrange : (note.kind == .slide ? .systemTeal : (note.kind == .touch || note.kind == .touchHold ? .systemPurple : .systemPink))
            color.setFill(); color.setStroke()
            let head: NSBezierPath
            if note.kind == .touch || note.kind == .touchHold {
                head = NSBezierPath(); head.move(to: CGPoint(x: px, y: y - radius))
                head.line(to: CGPoint(x: px + radius, y: y)); head.line(to: CGPoint(x: px, y: y + radius)); head.line(to: CGPoint(x: px - radius, y: y)); head.close()
            } else { head = NSBezierPath(ovalIn: NSRect(x: px - radius, y: y - radius, width: radius * 2, height: radius * 2)) }
            if note.kind == .slide {
                let start = max(px, min(end, x(note.segments.first?.startTime ?? note.time)))
                let wait = NSBezierPath(); wait.move(to: CGPoint(x: px, y: y)); wait.line(to: CGPoint(x: start, y: y)); wait.setLineDash([2, 2], count: 2, phase: 0); wait.lineWidth = 1; wait.stroke()
                let path = NSBezierPath(); path.move(to: CGPoint(x: start, y: y)); path.line(to: CGPoint(x: end, y: y)); path.lineWidth = 2; path.stroke()
                let arrow = NSBezierPath(); arrow.move(to: CGPoint(x: end - 5, y: y - radius)); arrow.line(to: CGPoint(x: end, y: y)); arrow.line(to: CGPoint(x: end - 5, y: y + radius)); arrow.lineWidth = 2; arrow.stroke()
                NSBezierPath(ovalIn: NSRect(x: start - 2, y: y - 2, width: 4, height: 4)).fill()
            } else {
                if note.kind == .hold || note.kind == .touchHold {
                    color.withAlphaComponent(0.45).setFill()
                    NSBezierPath(roundedRect: NSRect(x: px, y: y - radius, width: max(1, end - px), height: radius * 2), xRadius: 2, yRadius: 2).fill()
                    line(end, y - radius, y + radius, color, 2)
                    color.setFill()
                }
                head.fill()
            }
            if note.isBreak {
                NSColor.systemYellow.setStroke(); head.lineWidth = 2; head.stroke()
            }
            if view.span < 30 && (note.kind == .touch || note.kind == .touchHold) {
                label(note.area + (note.area == "C" ? "" : String(note.lane)), px + radius + 2, y - 5, color)
            }
        }
        var lastTempoX = -100.0, lastBPM = -1.0, lastDivider = -1.0
        for point in model.chart.timings {
            let changed = point.bpm != lastBPM || point.subdivision != lastDivider
            lastBPM = point.bpm; lastDivider = point.subdivision
            let px = x(point.time)
            if changed && px >= 0 && px <= width && px - lastTempoX > 115 {
                label(String(format: "BPM %.3g · {%.3g}", point.bpm, point.subdivision), px + 3, 16, .systemTeal); lastTempoX = px
            }
        }
    }
}
