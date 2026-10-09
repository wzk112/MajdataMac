import SwiftUI

/// Keep playback observation below App/Scene so a clock tick cannot invalidate every window.
struct StandaloneStageWindow: View {
    @Bindable var model: StudioModel
    var body: some View {
        VStack(spacing: 0) {
            LiveStagePresentation(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
            TransportBar(model: model).padding(16).background(.bar)
        }
        .background(Color.black).frame(minWidth: 660, minHeight: 700)
        .toolbar {
            ToolbarItem { Text(model.title).font(.headline) }
            ToolbarItem { Toggle("谱面信息", systemImage: "info.circle", isOn: $model.showStageInfo).help("横向拉宽窗口后，在舞台旁显示谱面信息") }
            ToolbarItem {
                Menu("视频导出", systemImage: "square.and.arrow.up") {
                    Picker("分辨率", selection: $model.videoResolution) {
                        ForEach(VideoResolution.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle("宽屏导出谱面信息", isOn: $model.exportChartInfo)
                    Divider()
                    Button("导出视频…") { model.exportVideo() }
                }.help("选择导出像素尺寸；不改变实时预览分辨率")
            }
            ToolbarItem { Menu("画面特效", systemImage: "sparkles") { StageEffectsControls(model: model) } }
            ToolbarItem { Toggle("判定区", systemImage: "circle.hexagongrid", isOn: $model.showSensors).help("显示 34 块物理区域，C1/C2 合并为 C ⇧⌘J") }
            ToolbarItem { Button("上一帧", systemImage: "backward.frame") { model.stepFrame(-1) } }
            ToolbarItem { Button("下一帧", systemImage: "forward.frame") { model.stepFrame(1) } }
        }
    }
}

struct LiveStagePresentation: View {
    var model: StudioModel
    var body: some View {
        StagePresentation(info: model.stageInfo, cover: model.background, showInfo: model.showStageInfo,
                          statistics: StageStatisticsTimeline.prepared(model.chart, recording: model.regionJudgement ? model.recording : nil), liveModel: model) {
            LiveStageView(model: model, standalone: true)
        }
    }
}
