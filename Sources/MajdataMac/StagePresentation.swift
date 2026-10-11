import SwiftUI
import MajdataCore

struct StageChartInfo {
    var title: String
    var artist: String
    var designer: String
    var difficulty: Int
    var level: String
    var notes: Int
    var breaks: Int
    var mode = "Classic"
    var showJudgementBreakdown = false
    var difficultyName: String { ChartDocument.difficultyNames[min(6, max(0, difficulty))] }
    var color: Color { [.gray, .green, .yellow, .red, .purple, .pink, .cyan][min(6, max(0, difficulty))] }
}

struct StageArrangement {
    let side: Double
    let infoWidth: Double
    let gap: Double
    let stageX: Double
    init(size: CGSize, showInfo: Bool) {
        side = max(0, min(size.width, size.height))
        stageX = (size.width - side) / 2
        gap = side * 0.035
        infoWidth = showInfo && stageX >= max(145, side * 0.27) ? stageX - gap * 2 : 0
    }
}

/// Symmetric gutters keep the playfield at the exact window/frame center.
struct StagePresentation<Stage: View>: View {
    var info: StageChartInfo?
    var cover: NSImage?
    var showInfo: Bool = true
    var statistics: StageStatisticsTimeline?
    var time = 0.0
    var liveModel: StudioModel?
    @ViewBuilder var stage: () -> Stage
    var body: some View {
        GeometryReader { geometry in
            let layout = StageArrangement(size: geometry.size, showInfo: showInfo && info != nil)
            ZStack {
                stage().frame(width: layout.side, height: layout.side).clipped()
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                if layout.infoWidth > 0, let info {
                    if let liveModel {
                        LiveStageSidePanels(model: liveModel, info: info, cover: cover, statistics: statistics, layout: layout, size: geometry.size)
                    } else {
                        StageSidePanels(info: info, cover: cover, statistics: statistics, time: time, layout: layout, size: geometry.size)
                    }
                }
            }.foregroundStyle(.white)
        }.background(Color(red: 0.035, green: 0.045, blue: 0.065))
    }
}

/// Only this small subtree observes the transport clock. The stage layout stays stable.
struct LiveStageSidePanels: View {
    var model: StudioModel
    var info: StageChartInfo
    var cover: NSImage?
    var statistics: StageStatisticsTimeline?
    var layout: StageArrangement
    var size: CGSize
    var body: some View {
        StageSidePanels(info: info, cover: cover, statistics: statistics, time: model.currentTime, layout: layout, size: size)
    }
}
private struct StageSidePanels: View {
    var info: StageChartInfo
    var cover: NSImage?
    var statistics: StageStatisticsTimeline?
    var time: Double
    var layout: StageArrangement
    var size: CGSize
    var body: some View {
        let score = statistics?.score(at: time) ?? StageStatistics()
        StageMetadataPanel(info: info, cover: cover, statistics: statistics, score: score, scale: layout.side / 900)
            .frame(width: layout.infoWidth, height: layout.side)
            .position(x: layout.stageX / 2, y: size.height / 2)
        StageResultsPanel(info: info, statistics: statistics, score: score, time: time, scale: layout.side / 900)
            .frame(width: layout.infoWidth, height: layout.side)
            .position(x: size.width - layout.stageX / 2, y: size.height / 2)
    }
}

private struct StageMetadataPanel: View {
    var info: StageChartInfo
    var cover: NSImage?
    var statistics: StageStatisticsTimeline?
    var score: StageStatistics
    var scale: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 16 * scale) {
            Spacer(minLength: 0)
            if let cover {
                Image(nsImage: cover).resizable().scaledToFill()
                    .frame(width: 170 * scale, height: 170 * scale).clipped()
                    .clipShape(.rect(cornerRadius: 8 * scale))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(info.difficultyName).font(.system(size: 20 * scale, weight: .bold))
                Spacer(minLength: 4)
                Text(info.level.isEmpty ? "—" : info.level).font(.system(size: 30 * scale, weight: .bold, design: .rounded))
            }.foregroundStyle(info.color).lineLimit(1).minimumScaleFactor(0.6)
            Text(info.title).font(HarmonyOSFont.swiftUI(size: 28 * scale, bold: true)).lineLimit(3).minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            field("ARTIST / 作曲", info.artist)
            field("NOTE DESIGN / 谱师", info.designer)
            Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
            VStack(spacing: 9 * scale) {
                ForEach(StageNoteCategory.allCases, id: \.rawValue) { category in
                    row(category.title, "\(score.counts[category.rawValue]) / \(statistics?.totals[category.rawValue] ?? 0)", color: category == .break ? .orange : .white)
                }
                row("ALL", "\(score.judged) / \(info.notes)", color: .cyan)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 24 * scale)
    }
    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            Text(label).font(.system(size: 12 * scale)).foregroundStyle(.white.opacity(0.55))
            Text(value.isEmpty ? "—" : value).font(HarmonyOSFont.swiftUI(size: 18 * scale)).lineLimit(2).minimumScaleFactor(0.65)
        }
    }
    private func row(_ label: String, _ value: String, color: Color) -> some View {
        HStack { Text(label).foregroundStyle(color.opacity(0.8)); Spacer(minLength: 4); Text(value).monospacedDigit() }
            .font(.system(size: 17 * scale, weight: .medium)).lineLimit(1).minimumScaleFactor(0.65)
    }
}
private struct StageResultsPanel: View {
    var info: StageChartInfo
    var statistics: StageStatisticsTimeline?
    var score: StageStatistics
    var time: Double
    var scale: Double
    private let labels = ["CRITICAL PERFECT", "PERFECT", "GREAT", "GOOD", "MISS"]
    private let colors: [Color] = [.yellow, .yellow, .pink, .green, .gray]
    var body: some View {
        VStack(alignment: .leading, spacing: 22 * scale) {
            Spacer(minLength: 0)
            field("FiNALE RATE", String(format: "%.2f%%", truncated(score.finaleRate(totalWeight: statistics?.totalWeight ?? 0), digits: 100)))
            field("DELUXE RATE", String(format: "%.4f%%", truncated(score.deluxeRate(totalWeight: statistics?.totalWeight ?? 0, breaks: info.breaks), digits: 10000)))
            VStack(spacing: 9 * scale) {
                row("COMBO", String(score.combo), .white)
                row("SCORE", score.classicScore.formatted(), .white)
                row("DX SCORE", "\(score.dx) / \(info.notes * 3)", .cyan)
            }
            if info.showJudgementBreakdown {
                Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
                VStack(spacing: 11 * scale) {
                    ForEach(0..<labels.count, id: \.self) { index in row(labels[index], String(score.grades[index]), colors[index]) }
                    Divider().overlay(.white.opacity(0.18)).padding(.vertical, 4 * scale)
                    row("FAST", String(score.fast), .cyan)
                    row("LATE", String(score.late), .pink)
                }
            }
            VStack(alignment: .leading, spacing: 8 * scale) {
                Text("MODE · " + info.mode).font(.system(size: 16 * scale, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                Text(StudioModel.timeLabel(time)).font(.system(size: 24 * scale, weight: .medium, design: .monospaced))
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 24 * scale)
    }
    private func truncated(_ value: Double, digits: Double) -> Double { floor((value + 1e-10) * digits) / digits }
    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            Text(label).font(.system(size: 15 * scale, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            Text(value).font(.system(size: 32 * scale, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.yellow)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }
    private func row(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack { Text(label).foregroundStyle(color); Spacer(minLength: 4); Text(value).monospacedDigit() }
            .font(.system(size: 16 * scale, weight: .medium)).lineLimit(1).minimumScaleFactor(0.65)
    }
}

enum VideoResolution: String, CaseIterable {
    case square720, square1080, square1440, square2160, hd720, fullHD, qhd, uhd4K
    var dimensions: (width: Int, height: Int) {
        switch self {
        case .square720: (720, 720)
        case .square1080: (1080, 1080)
        case .square1440: (1440, 1440)
        case .square2160: (2160, 2160)
        case .hd720: (1280, 720)
        case .fullHD: (1920, 1080)
        case .qhd: (2560, 1440)
        case .uhd4K: (3840, 2160)
        }
    }
    var title: String { "\(dimensions.width) × \(dimensions.height) · " + (dimensions.width == dimensions.height ? "方形" : "16:9") }
}

@MainActor extension StudioModel {
    var stageInfo: StageChartInfo {
        StageChartInfo(title: title, artist: document.artist, designer: document.designer(difficulty),
                       difficulty: difficulty, level: document.level(difficulty), notes: chart.notes.count, breaks: chart.breakCount, mode: regionJudgement ? "区域模拟（实验）" : "Classic", showJudgementBreakdown: regionJudgement)
    }
}
