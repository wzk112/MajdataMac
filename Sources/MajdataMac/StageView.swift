import SwiftUI
import AVKit
import MajdataCore

struct StageStyle {
    var noteSpeed: Double = 7.5
    var touchSpeed: Double = 7.5
    var dim: Double = 0.65
    var center = "COMBO"
    var skin: [String: NSImage] = [:]
    var background: NSImage?
    var showSensors = false
    /// Thin neutral outline of the judgement zones, drawn as the stage's base when the coloured overlay is off.
    var sensorPattern = false
    var sensorLabels = true
    var sensorOpacity = 0.45
    var recording: RegionRecording?
    var showFireworks = true
    var showHitEffects = true
    var showHoldParticles = true
    var showSensorPresses = true
}
struct StageView: View {
    var chart: ParsedChart
    var time: Double
    var style: StageStyle
    var videoPlayer: AVPlayer?
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.055, blue: 0.095)
            if let background = style.background { Image(nsImage: background).resizable().scaledToFill().opacity(1 - style.dim).clipped() }
            if let videoPlayer { VideoSurface(player: videoPlayer).opacity(1 - style.dim).allowsHitTesting(false) }
            Canvas { context, size in StageDrawing.draw(context: &context, size: size, chart: chart, time: time, style: style) }
        }
        .clipped()
        .accessibilityLabel("谱面预览，\(StudioModel.timeLabel(time))，\(chart.notes.count) 个音符")
    }
}
struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(); view.controlsStyle = .none; view.videoGravity = .resizeAspectFill; view.player = player; return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { if view.player !== player { view.player = player } }
}

/// Shared preferences apply to both live stages and the next video export.
struct StageEffectsControls: View {
    @Bindable var model: StudioModel
    var body: some View {
        Toggle("烟花特效", isOn: $model.showFireworks)
        Toggle("击打光效", isOn: $model.showHitEffects)
        Toggle("长押粒子", isOn: $model.showHoldParticles)
        Divider()
        Toggle("判定区按压高亮", isOn: $model.showSensorPresses)
    }
}
