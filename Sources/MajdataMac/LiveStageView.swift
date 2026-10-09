import SwiftUI
import QuartzCore

enum DisplayRefreshPolicy {
    static func range(requested: Int, screenMaximum: Int) -> CAFrameRateRange {
        let maximum = Float(max(1, screenMaximum))
        let rate = requested == 0 ? maximum : min(maximum, Float(max(1, requested)))
        return CAFrameRateRange(minimum: requested == 0 ? min(30, rate) : rate, maximum: rate, preferred: rate)
    }
}

@MainActor @Observable final class StageFrameClock {
    var time = 0.0
    var fps = 0.0
    var lateFrames = 0
    @ObservationIgnored private var first = 0.0
    @ObservationIgnored private var last = 0.0
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var late = 0
    func update(time: Double, timestamp: Double, interval: Double) {
        self.time = time
        if last > 0 && timestamp - last > max(0.001, interval) * 1.6 { late += 1 }
        last = timestamp
        if first == 0 { first = timestamp }
        frames += 1
        if timestamp - first >= 1 {
            fps = Double(frames - 1) / (timestamp - first); lateFrames = late
            frames = 1; late = 0; first = timestamp
        }
    }
    func reset() { first = 0; last = 0; frames = 0; late = 0; fps = 0; lateFrames = 0 }
}

struct LiveStageView: View {
    var model: StudioModel
    var standalone = false
    var body: some View { StageAnimationSurface(model: model, standalone: standalone) }
}

/// A separate hosting root contains frame-rate invalidation. The surrounding editor window
/// supplies the size; animation must not request a new intrinsic size/layout for that window.
private struct StageAnimationSurface: NSViewRepresentable {
    var model: StudioModel
    var standalone: Bool
    func makeNSView(context: Context) -> StageAnimationHost {
        StageAnimationHost(model: model, standalone: standalone)
    }
    func updateNSView(_ view: StageAnimationHost, context: Context) {
        view.update(model: model, standalone: standalone)
    }
}

@MainActor final class StageAnimationHost: NSView {
    private let host: NSHostingView<StageAnimationContent>
    private var model: StudioModel
    private var standalone: Bool
    init(model: StudioModel, standalone: Bool) {
        self.model = model; self.standalone = standalone
        host = NSHostingView(rootView: StageAnimationContent(model: model, standalone: standalone))
        super.init(frame: .zero)
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(model: StudioModel, standalone: Bool) {
        guard self.model !== model || self.standalone != standalone else { return }
        self.model = model; self.standalone = standalone
        host.rootView = StageAnimationContent(model: model, standalone: standalone)
    }
    override func layout() {
        super.layout()
        if host.frame != bounds { host.frame = bounds }
    }
}

private struct StageAnimationContent: View {
    var model: StudioModel
    var standalone: Bool
    @State private var clock = StageFrameClock()
    var body: some View {
        StageView(chart: model.chart, time: model.isPlaying ? clock.time : model.currentTime,
                  style: model.stageStyle, videoPlayer: model.videoPlayer)
            .background(DisplayLinkSurface(running: model.isPlaying, frameRate: standalone ? model.frameRate : model.previewFrameRate) { timestamp, interval in
                clock.update(time: model.playbackTime, timestamp: timestamp, interval: interval)
            })
            .overlay(alignment: .topLeading) {
                if model.showFrameStats {
                    Text(model.isPlaying ? String(format: "刷新 %.0f Hz · 超时 %d / 秒", clock.fps, clock.lateFrames) : "刷新已暂停")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white).padding(8).background(.black.opacity(0.7), in: .rect(cornerRadius: 6)).padding(8)
                        .help("舞台显示回调频率；超时为超过目标间隔 1.6 倍的回调。此读数不代表 GPU 完成帧率。")
                }
            }
            .onChange(of: model.isPlaying) { _, _ in clock.reset(); clock.time = model.currentTime }
    }
}

private struct DisplayLinkSurface: NSViewRepresentable {
    var running: Bool
    var frameRate: Int
    var frame: @MainActor (Double, Double) -> Void
    func makeNSView(context: Context) -> DisplayLinkView { DisplayLinkView() }
    func updateNSView(_ view: DisplayLinkView, context: Context) {
        view.frameCallback = frame; view.running = running; view.requestedRate = frameRate; view.configure()
    }
    static func dismantleNSView(_ view: DisplayLinkView, coordinator: ()) { view.stop() }
}

@MainActor private final class DisplayLinkView: NSView {
    var frameCallback: (@MainActor (Double, Double) -> Void)?
    var running = false
    var requestedRate = 0
    private var link: CADisplayLink?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); stop()
        if window != nil { link = displayLink(target: self, selector: #selector(refresh(_:))); link?.add(to: .main, forMode: .common) }
        configure()
    }
    func configure() {
        guard let link else { return }
        let range = DisplayRefreshPolicy.range(requested: requestedRate, screenMaximum: window?.screen?.maximumFramesPerSecond ?? 60)
        let current = link.preferredFrameRateRange
        if current.minimum != range.minimum || current.maximum != range.maximum || current.preferred != range.preferred {
            link.preferredFrameRateRange = range
        }
        let paused = !running || window == nil
        if link.isPaused != paused { link.isPaused = paused }
    }
    @objc private func refresh(_ link: CADisplayLink) {
        guard window?.isVisible == true, window?.occlusionState.contains(.visible) == true, !isHiddenOrHasHiddenAncestor else { return }
        frameCallback?(link.timestamp, link.targetTimestamp - link.timestamp)
    }
    func stop() { link?.invalidate(); link = nil }
}
