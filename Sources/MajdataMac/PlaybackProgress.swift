import SwiftUI
import AppKit
import MajdataCore

struct PlaybackProgress: View {
    @Bindable var model: StudioModel
    var body: some View {
        PlaybackProgressSurface(model: model, time: model.currentTime, lower: model.rangeStart, upper: model.rangeEnd)
    }
}
private struct PlaybackProgressSurface: NSViewRepresentable {
    var model: StudioModel
    var time: Double
    var lower: Double
    var upper: Double
    func makeNSView(context: Context) -> PlaybackSlider {
        let slider = PlaybackSlider(); slider.isContinuous = true
        slider.target = slider; slider.action = #selector(PlaybackSlider.seek)
        slider.setAccessibilityLabel("播放进度")
        slider.toolTip = "定位整首谱面的播放位置；拖动时暂停，松手恢复此前播放状态"
        return slider
    }
    func updateNSView(_ slider: PlaybackSlider, context: Context) {
        slider.model = model; slider.minValue = lower; slider.maxValue = upper
        if !slider.tracking { slider.doubleValue = time }
    }
}
@MainActor final class PlaybackSlider: NSSlider {
    weak var model: StudioModel?
    private(set) var tracking = false
    private var resumeAfterScrub = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        beginScrub(); scrub(x: convert(event.locationInWindow, from: nil).x)
    }
    override func mouseDragged(with event: NSEvent) { scrub(x: convert(event.locationInWindow, from: nil).x) }
    override func mouseUp(with event: NSEvent) { scrub(x: convert(event.locationInWindow, from: nil).x); endScrub() }
    func beginScrub() {
        guard let model else { return }
        resumeAfterScrub = model.isPlaying; tracking = true; model.pause()
    }
    func scrub(x: Double) {
        guard tracking else { return }
        let inset = max(8, knobThickness / 2)
        let fraction = min(1, max(0, (x - inset) / max(1, bounds.width - 2 * inset)))
        doubleValue = minValue + fraction * (maxValue - minValue)
        seek()
    }
    func endScrub() {
        tracking = false
        if resumeAfterScrub { model?.play() }
        resumeAfterScrub = false
    }
    @objc func seek() {
        guard let model else { return }
        model.seek(doubleValue)
        let view = TimelineViewport(lower: model.rangeStart, upper: model.rangeEnd, zoom: model.timelineZoom, start: model.timelineStart)
        if model.timelineFollow && (model.currentTime < view.start || model.currentTime > view.start + view.span) {
            model.timelineStart = model.currentTime - view.span * 0.35
        }
    }
}
