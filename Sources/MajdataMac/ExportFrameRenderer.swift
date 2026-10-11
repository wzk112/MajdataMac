import SwiftUI
import MajdataCore

private struct ExportFrame: View {
    let chart: ParsedChart
    let info: StageChartInfo?
    let statistics: StageStatisticsTimeline?
    let cover: NSImage?
    let intro: RecordingIntro?
    let introText: RecordingIntroText?
    let width: Int
    let height: Int
    var time: Double
    var style: StageStyle

    var body: some View {
        StagePresentation(info: info, cover: cover, statistics: statistics, time: time) {
            StageView(chart: chart, time: time, style: style)
                .overlay {
                    if let intro, let introText, time >= intro.opening.startTime, time < intro.opening.endTime {
                        RecordingIntroView(intro: intro, text: introText, cover: cover, time: time)
                    }
                }
        }.frame(width: Double(width), height: Double(height))
    }
}

/// Keep the SwiftUI render graph alive. cgImage preserves Canvas GPU rasterization;
/// Rendering this graph into a CGContext with render(rasterizationScale:renderer:) measured slower.
@MainActor final class ExportFrameRenderer {
    private let renderer: ImageRenderer<ExportFrame>
    init(chart: ParsedChart, style: StageStyle, info: StageChartInfo?, statistics: StageStatisticsTimeline?, width: Int, height: Int, intro: RecordingIntro? = nil) throws {
        renderer = ImageRenderer(content: ExportFrame(chart: chart, info: info, statistics: statistics, cover: style.background, intro: intro,
                                                     introText: try intro.map { try RecordingIntroText(info: $0.info, height: height) },
                                                     width: width, height: height, time: 0, style: style))
        renderer.scale = 1
        renderer.isOpaque = true
    }
    func draw(time: Double, style: StageStyle, into context: CGContext) throws {
        let image = try image(time: time, style: style)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    func image(time: Double, style: StageStyle) throws -> CGImage {
        var content = renderer.content
        content.time = time
        content.style = style
        renderer.content = content
        guard let image = renderer.cgImage else { throw ExportFailure.failure("无法渲染谱面帧") }
        return image
    }
}
