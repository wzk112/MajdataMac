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
    var sensorLabels = true
    var sensorOpacity = 0.45
    var recording: RegionRecording?
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
