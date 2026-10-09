import Testing
import AppKit
import MajdataCore
@testable import MajdataMac

@Suite(.serialized) struct TimelineInteractionTests {
    @Test @MainActor func edgeDragContinuesBeyondVisibleRange() {
        let model = StudioModel(audioOutputEnabled: false)
        model.source = "(120){1}1,2,3,4,5,6,7,8,E"; model.chart = SimaiParser.parse(model.source)
        model.timelineZoom = 4; model.timelineStart = 5
        let view = TimelineCanvas(model: model); view.frame = NSRect(x: 0, y: 0, width: 1000, height: 128)
        let end = view.viewport.start + view.viewport.span
        view.beginScrub(x: 1000)
        for _ in 0..<120 { view.advanceScrub(seconds: 1.0 / 60) }
        #expect(model.currentTime > end + 1)
        #expect(view.viewport.start > 5)
        view.scrub(x: 500); let fixed = view.viewport
        for _ in 0..<30 { view.advanceScrub(seconds: 1.0 / 60) }
        #expect(view.viewport == fixed)
        view.scrub(x: 0)
        for _ in 0..<600 { view.advanceScrub(seconds: 1.0 / 60) }
        #expect(abs(model.currentTime - model.rangeStart) < 1e-9)
        view.endScrub(x: 0)
        #expect(!model.isPlaying)
    }
    @Test @MainActor func dragDoesNotChasePlayheadAndBackgroundIsCached() throws {
        let model = StudioModel(audioOutputEnabled: false)
        model.source = "(120){1}1,2,3,4,5,6,7,8,E"; model.chart = SimaiParser.parse(model.source)
        model.timelineZoom = 4; model.timelineStart = 5
        let view = TimelineCanvas(model: model); view.frame = NSRect(x: 0, y: 0, width: 1000, height: 128)
        let original = view.viewport
        let selection = model.selectedRange
        view.beginScrub(x: 700)
        for _ in 0..<30 { view.update(model); view.scrub(x: 700) }
        #expect(abs(model.currentTime - original.time(at: 700, width: 1000)) < 1e-9)
        #expect(view.viewport == original)
        view.endScrub(x: 200)
        #expect(abs(model.currentTime - original.time(at: 200, width: 1000)) < 1e-9)
        #expect(model.selectedRange == selection && !model.isPlaying)
        func draw() throws {
            let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: image)
            if let path = ProcessInfo.processInfo.environment["MAJDATA_TIMELINE_PROOF"] {
                try #require(image.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
            }
        }
        try draw(); let count = view.backgroundRenderCount
        for i in 0..<30 { model.currentTime = 5 + Double(i) / 60; view.update(model); try draw() }
        #expect(view.backgroundRenderCount == count)
        model.timelineBeatsPerBar = 3; view.update(model); try draw()
        #expect(view.backgroundRenderCount == count + 1)
    }
}
