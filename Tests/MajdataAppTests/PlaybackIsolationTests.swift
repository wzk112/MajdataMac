import Testing
import SwiftUI
import Observation
import Synchronization
import MajdataCore
@testable import MajdataMac

@Suite(.serialized) struct PlaybackIsolationTests {
    @Test @MainActor func stageAnimationPreservesSizeAndIdentityAcrossClockUpdates() async throws {
        let model = StudioModel(audioOutputEnabled: false)
        model.chart = SimaiParser.parse("(120){4},,1/Ch[4:4],E")
        let stage = StageAnimationHost(model: model, standalone: false)
        let content = try #require(stage.subviews.first)
        for side in [480.0, 720.0, 360.0] {
            stage.frame = NSRect(x: 0, y: 0, width: side, height: side)
            stage.layoutSubtreeIfNeeded()
            for time in [0.0, 1.25, 0.75] {
                model.currentTime = time
                stage.update(model: model, standalone: false)
                try await Task.sleep(for: .milliseconds(20))
                stage.layoutSubtreeIfNeeded()
                #expect(stage.subviews.first === content)
                #expect(content.frame.size == stage.bounds.size)
                #expect(content.intrinsicContentSize.width == NSView.noIntrinsicMetric)
                #expect(content.intrinsicContentSize.height == NSView.noIntrinsicMetric)
            }
        }
    }
    @Test @MainActor func transportClockOnlyInvalidatesLiveStatistics() {
        let model = StudioModel(audioOutputEnabled: false)
        let outerChanged = Mutex(false)
        withObservationTracking {
            _ = LiveStagePresentation(model: model).body
        } onChange: { outerChanged.withLock { $0 = true } }
        let statsChanged = Mutex(false)
        withObservationTracking {
            _ = LiveStageSidePanels(model: model, info: model.stageInfo, statistics: nil,
                                    layout: StageArrangement(size: CGSize(width: 1920, height: 1080), showInfo: true),
                                    size: CGSize(width: 1920, height: 1080)).body
        } onChange: { statsChanged.withLock { $0 = true } }
        model.currentTime = 1.25
        #expect(!outerChanged.withLock { $0 })
        #expect(statsChanged.withLock { $0 })
    }
    @Test @MainActor func disablingPressHighlightRetainsZonesAndNotes() throws {
        func pixels(_ chart: ParsedChart, style: StageStyle) throws -> Data {
            let renderer = ImageRenderer(content: StageView(chart: chart, time: 1.25, style: style).frame(width: 480, height: 480))
            renderer.scale = 1; renderer.isOpaque = true
            return try #require(renderer.cgImage?.dataProvider?.data) as Data
        }
        func expectSameImage(_ lhs: Data, _ rhs: Data) {
            // Canvas may round a few antialiased edge channels by one level between GPU passes.
            let differences = zip(lhs, rhs).filter { $0 != $1 }.count
            let maximumDifference = zip(lhs, rhs).map { abs(Int($0) - Int($1)) }.max() ?? 0
            #expect(lhs.count == rhs.count && differences <= 64 && maximumDifference <= 1,
                    "Equivalent frame: \(differences) differing channels, maximum delta \(maximumDifference)")
        }
        let active = SimaiParser.parse("(120){4},,Ch[4:4],E")
        var style = StageStyle(center: "NONE", showSensors: true)
        let highlighted = try pixels(active, style: style)
        style.showSensorPresses = false
        let outlines = try pixels(active, style: style)
        #expect(highlighted != outlines)
        style.showSensors = false
        #expect(try outlines != pixels(active, style: style))
        let noZones = try pixels(active, style: style)
        style.showSensorPresses = true
        try expectSameImage(noZones, pixels(active, style: style))
        // Quiet regions remain identical: only pressed-state drawing is suppressed.
        let empty = ParsedChart()
        style.showSensors = true
        let quiet = try pixels(empty, style: style)
        style.showSensorPresses = false
        try expectSameImage(quiet, pixels(empty, style: style))
    }
}
