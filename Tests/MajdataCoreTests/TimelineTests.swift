import Testing
import Foundation
@testable import MajdataCore

struct TimelineTests {
    @Test func frozenDragAndZoomAnchor() {
        let v = TimelineViewport(lower: -2, upper: 98, zoom: 10, start: 30)
        #expect(v.time(at: 700, width: 1000) == 37)
        // Repeated pointer events do not feed the last seek back into the viewport.
        for _ in 0..<100 { #expect(v.time(at: 700, width: 1000) == 37) }
        let zoom = v.zoomed(to: 20, anchor: 37, fraction: 0.7)
        #expect(abs(zoom.time(at: 700, width: 1000) - 37) < 1e-9)
        #expect(v.time(at: -100, width: 1000) == 30)
        #expect(v.time(at: 2000, width: 1000) == 40)
    }
    @Test func gridSpansAllBarsAndRespondsToMeter() {
        let chart = SimaiParser.parse("(120){1}1,2,3,4,E")
        let v = TimelineViewport(lower: 0, upper: 8, zoom: 1, start: 0)
        let grid = MusicalTimeline(chart)
        #expect(grid.grid(in: v, width: 1600, beatsPerBar: 4).filter { $0.kind == .bar }.map(\.time) == [0, 2, 4, 6])
        #expect(grid.grid(in: v, width: 1600, beatsPerBar: 3).filter { $0.kind == .bar }.map(\.time) == [0, 1.5, 3, 4.5, 6, 7.5])
    }
    @Test func tempoAndDividerDoNotResetMusicalPhase() {
        let chart = SimaiParser.parse("(120){4}1,2,(240){8}3,4,5,6,7,8,1,2,E")
        let grid = MusicalTimeline(chart).grid(in: TimelineViewport(lower: 0, upper: 2, zoom: 1, start: 0), width: 1600, beatsPerBar: 4)
        #expect(grid.filter { $0.kind == .bar }.map(\.time) == [0, 1.5])
        #expect(grid.contains { $0.kind == .subdivision && abs($0.time - 1.125) < 1e-9 })
    }
    @Test func caretMapsDirectivesCommentsCommasAndEnd() throws {
        let text = "|| 🎵\n(120){4}1,\n{8}2,3,E"
        let index = MusicalTimeline(SimaiParser.parse(text))
        let ns = text as NSString
        #expect(index.sourceTime(at: 0) == 0)
        #expect(index.sourceTime(at: ns.range(of: "{8}").location) == 0.5)
        #expect(index.sourceTime(at: ns.range(of: "2,").location + 1) == 0.5)
        #expect(index.sourceTime(at: ns.range(of: "3,").location) == 0.75)
        #expect(index.sourceTime(at: ns.length) == 1)
        #expect(index.nearestCell(to: 0.72) == 0.75)
    }
}
