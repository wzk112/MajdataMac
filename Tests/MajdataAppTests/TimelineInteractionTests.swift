import Testing
import AppKit
import SwiftUI
import MajdataCore
@testable import MajdataMac

@Suite(.serialized) struct TimelineInteractionTests {
    @Test @MainActor func progressSeeksWholeChartRegardlessOfZoom() async throws {
        let model = StudioModel(audioOutputEnabled: false)
        model.source = "(120){1}1,2,3,4,5,6,7,8,E"; model.chart = SimaiParser.parse(model.source)
        model.timelineZoom = 16; model.timelineStart = 2
        let host = NSHostingView(rootView: PlaybackProgress(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 22); host.layoutSubtreeIfNeeded()
        func find(_ view: NSView) -> PlaybackSlider? {
            if let slider = view as? PlaybackSlider { return slider }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        let slider = try #require(find(host))
        #expect(slider.minValue == model.rangeStart && slider.maxValue == model.rangeEnd)
        model.seek(3)
        try await Task.sleep(for: .milliseconds(70)); host.layoutSubtreeIfNeeded()
        #expect(slider.doubleValue == 3)
        model.source += "\n"; model.chart = SimaiParser.parse("(120){1}1,2,E")
        try await Task.sleep(for: .milliseconds(70)); host.layoutSubtreeIfNeeded()
        #expect(slider.maxValue == model.rangeEnd)
        slider.doubleValue = model.rangeEnd - 1; slider.seek()
        #expect(model.currentTime == model.rangeEnd - 1)
        slider.doubleValue = model.rangeStart; slider.seek()
        #expect(model.currentTime == model.rangeStart && !model.isPlaying)
        slider.beginScrub()
        slider.scrub(x: slider.bounds.width * 0.8)
        #expect(model.currentTime > model.rangeStart + model.duration * 0.75)
        slider.scrub(x: -50)
        #expect(model.currentTime == model.rangeStart)
        slider.scrub(x: slider.bounds.width + 50); slider.endScrub()
        #expect(model.currentTime == model.rangeEnd && !slider.tracking && !model.isPlaying)
    }
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
