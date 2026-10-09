import SwiftUI
import MajdataCore

private struct ExportFrame: View {
    let chart: ParsedChart
    let info: StageChartInfo?
    let statistics: StageStatisticsTimeline?
    let cover: NSImage?
    let width: Int
    let height: Int
    var time: Double
    var style: StageStyle

    var body: some View {
        StagePresentation(info: info, cover: cover, statistics: statistics, time: time) {
            StageView(chart: chart, time: time, style: style)
        }.frame(width: Double(width), height: Double(height))
    }
}

/// Keep the SwiftUI render graph alive. cgImage preserves Canvas GPU rasterization;
/// Rendering this graph into a CGContext with render(rasterizationScale:renderer:) measured slower.
@MainActor final class ExportFrameRenderer {
    private let renderer: ImageRenderer<ExportFrame>
    init(chart: ParsedChart, style: StageStyle, info: StageChartInfo?, statistics: StageStatisticsTimeline?, width: Int, height: Int) {
        renderer = ImageRenderer(content: ExportFrame(chart: chart, info: info, statistics: statistics, cover: style.background,
                                                     width: width, height: height, time: 0, style: style))
        renderer.scale = 1
        renderer.isOpaque = true
    }
    func draw(time: Double, style: StageStyle, into context: CGContext) throws {
        var content = renderer.content
        content.time = time
        content.style = style
        renderer.content = content
        guard let image = renderer.cgImage else { throw ExportFailure.failure("无法渲染谱面帧") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: content.width, height: content.height))
    }
}
