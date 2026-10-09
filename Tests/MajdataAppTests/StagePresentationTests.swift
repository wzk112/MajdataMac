import Testing
import SwiftUI
import AVFoundation
import MajdataCore
@testable import MajdataMac

@Suite(.serialized) struct StagePresentationTests {
    @Test func squareStageAndAdaptiveInformation() {
        for size in [CGSize(width: 900, height: 900), CGSize(width: 660, height: 700)] {
            let layout = StageArrangement(size: size, showInfo: true)
            #expect(layout.side == min(size.width, size.height) && layout.infoWidth == 0)
        }
        for size in [CGSize(width: 1280, height: 720), CGSize(width: 3840, height: 2160)] {
            let layout = StageArrangement(size: size, showInfo: true)
            #expect(layout.side == size.height && layout.infoWidth > 0)
            #expect(layout.side + 2 * (layout.infoWidth + layout.gap) <= size.width)
            #expect(abs(layout.stageX + layout.side / 2 - Double(size.width) / 2) < 0.000001)
            #expect(StageArrangement(size: size, showInfo: false).infoWidth == 0)
        }
    }
    @Test @MainActor func metadataProofAndDifficultySnapshot() throws {
        let model = StudioModel(audioOutputEnabled: false)
        model.document = ChartDocument(text: "&title=Test chart · 谱面标题\n&artist=Composer\n&des=Default\n&des_6=Re:MASTER designer\n&lv_6=15.0\n")
        model.difficulty = 5
        model.chart = SimaiParser.parse("(120){4},,1b/3h[4:4]/5-1[2:1]/Ch[4:2],E")
        let info = model.stageInfo
        #expect(info.designer == "Re:MASTER designer" && info.difficultyName == "Re:MASTER" && info.level == "15.0")
        guard let folder = ProcessInfo.processInfo.environment["MAJDATA_STAGE_PROOF"] else { return }
        let root = URL(fileURLWithPath: folder)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let chart = model.chart
        let cover = NSImage(contentsOf: URL(fileURLWithPath: "Assets/AppIcon.png"))
        for (name, size) in [("wide", CGSize(width: 1920, height: 1080)), ("square", CGSize(width: 900, height: 900))] {
            let view = StagePresentation(info: info, cover: cover, statistics: StageStatisticsTimeline.prepared(chart, recording: nil), time: 1.1) { StageView(chart: chart, time: 1.1, style: StageStyle()) }
                .frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: view); renderer.scale = 1
            let image = try #require(renderer.cgImage)
            #expect(image.width == Int(size.width) && image.height == Int(size.height))
            try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: root.appendingPathComponent(name + ".png"))
        }
    }
    @Test @MainActor func statisticsCategoriesScoresAndReverseSeek() throws {
        var chart = ParsedChart()
        chart.notes = [Note(id: 0, kind: .tap, lane: 1, time: 1),
                       Note(id: 1, kind: .tap, lane: 2, time: 2, isBreak: true),
                       Note(id: 2, kind: .touchHold, lane: 1, area: "C", time: 3, duration: 2),
                       Note(id: 3, kind: .touch, lane: 4, area: "B", time: 6)]
        let timeline = StageStatisticsTimeline.prepared(chart, recording: nil)
        #expect(timeline.totals == [1, 1, 0, 1, 1])
        #expect(timeline.totalWeight == 4500)
        for time in [0.0, 2.0, 6.0, 1.0, 4.0, 5.0] {
            let score = timeline.score(at: time)
            let judged = chart.notes.filter { $0.judgeTime <= time }.count
            #expect(score.judged == judged && score.combo == judged && score.grades == [judged, 0, 0, 0, 0])
        }
        let finished = timeline.score(at: 10)
        #expect(finished.classicScore == 4600 && finished.dx == 12)
        #expect(abs(finished.finaleRate(totalWeight: 4500) - 102.222222) < 0.00001)
        #expect(finished.deluxeRate(totalWeight: 4500, breaks: 1) == 101)
        var low = StageStatistics()
        low.add(chart.notes[1], grade: .perfect1, difference: -0.03)
        low.add(chart.notes[0], grade: .good, difference: 0.1)
        low.add(chart.notes[2], grade: .miss, difference: 0.3)
        #expect(low.grades == [0, 1, 0, 1, 1] && low.fast == 1 && low.late == 1 && low.combo == 0)
        #expect(low.classicScore == 2800 && low.deluxeBonus == 75 && low.dx == 2)
        let recording = try RegionRecording.simulate(chart, inputMode: .mixed)
        let simulated = StageStatisticsTimeline.prepared(chart, recording: recording).score(at: 10)
        #expect(simulated.dx == recording.score(at: 10).dx)
        #expect(abs(simulated.deluxeRate(totalWeight: timeline.totalWeight, breaks: 1) - recording.score(at: 10).achievement) < 0.00001)
        #expect(StageStatistics().deluxeRate(totalWeight: 0, breaks: 0).isFinite)
    }
    @Test @MainActor func effectSwitchesChangePixelsAndPreserveNoteRendering() throws {
        func pixels(_ source: String, _ time: Double, _ style: StageStyle) throws -> Data {
            let renderer = ImageRenderer(content: StageView(chart: SimaiParser.parse(source), time: time, style: style).frame(width: 480, height: 480))
            renderer.scale = 1; renderer.isOpaque = true
            let cg = try #require(renderer.cgImage)
            return try #require(cg.dataProvider?.data) as Data
        }
        let full = StageStyle(center: "NONE")
        var noFire = full; noFire.showFireworks = false
        let fireOn = try pixels("(120){4},,Cf,E", 1.22, full)
        let fireOff = try pixels("(120){4},,Cf,E", 1.22, noFire)
        #expect(fireOn != fireOff)
        #expect(fireOff == (try pixels("(120){4},,C,E", 1.22, full)))
        var noHit = noFire; noHit.showHitEffects = false
        #expect(try pixels("(120){4},,1,E", 1.1, full) != pixels("(120){4},,1,E", 1.1, noHit))
        var noHold = full; noHold.showHoldParticles = false
        #expect(try pixels("(120){4},,Ch[4:4],E", 1.7, full) != pixels("(120){4},,Ch[4:4],E", 1.7, noHold))
        #expect(try pixels("(120){4},,1,E", 0.8, full) == pixels("(120){4},,1,E", 0.8, noHit))
    }
    @Test(arguments: VideoResolution.allCases) @MainActor func exportWritesSelectedPixelDimensions(_ resolution: VideoResolution) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audio = PreparedAudio(url: root.appendingPathComponent("unused.wav"), waveform: [], startTime: 0, duration: 2.0 / 60)
        let output = root.appendingPathComponent("proof.mp4")
        let info = StageChartInfo(title: "Export resolution", artist: "Artist", designer: "Designer", difficulty: 4, level: "14+", notes: 1, breaks: 0)
        let dimensions = resolution.dimensions
        try await VideoExporter.render(chart: SimaiParser.parse("(120){4}1,E"), audio: audio, video: nil, style: StageStyle(), width: dimensions.width, height: dimensions.height, destination: output, info: info) { _ in }
        let asset = AVURLAsset(url: output)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(size.width == Double(dimensions.width) && size.height == Double(dimensions.height))
        #expect(abs(try await asset.load(.duration).seconds - 2.0 / 60) < 0.001)
    }
}
