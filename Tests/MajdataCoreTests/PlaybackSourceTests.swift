import Testing
import Foundation
@testable import MajdataCore

struct PlaybackSourceTests {
    @Test func fullCellsRestsUnicodeAndReverseSeek() throws {
        let source = "|| 🎵 中文\n(120){4}1h[4:4]/5, \n, 2, E"
        let chart = SimaiParser.parse(source), index = PlaybackSourceIndex(chart: chart), ns = source as NSString
        #expect(!chart.hasErrors)
        #expect(chart.timings.count == 3)
        #expect(index.highlights(at: -0.1).current == nil)
        for (time, content) in [(0.0, "1h[4:4]/5"), (0.6, ","), (1.0, "2"), (0.25, "1h[4:4]/5")] {
            let highlight = index.highlights(at: time)
            let range = try #require(highlight.current)
            #expect(ns.substring(with: range) == content)
            #expect(highlight.sustained.count == (time >= 0.5 ? 1 : 0))
        }
        #expect(index.highlights(at: 1.6).current == nil)
        #expect(index.highlights(at: 1.6).sustained.count == 1)
        #expect(index.highlights(at: 2).sustained.isEmpty)
        let note = try #require(chart.notes.first)
        #expect(ns.substring(with: NSRange(location: note.location.offset, length: note.location.length)) == "1h[4:4]/5")
    }
    @Test func finalCellWithoutCommaAndConnectedSlides() throws {
        let source = "(120){4}1-3-5[2:1],,2"
        let chart = SimaiParser.parse(source), index = PlaybackSourceIndex(chart: chart)
        #expect(chart.timings.count == 3)
        let range = try #require(index.highlights(at: 1.1).current)
        #expect((source as NSString).substring(with: range) == "2")
        #expect(index.highlights(at: 1.1).sustained.count == 1)
        #expect(index.highlights(at: 10).current == nil && index.highlights(at: 10).sustained.isEmpty)
    }
    @Test func fixedStepDoesNotHighlightPastEndMarker() {
        let index = PlaybackSourceIndex(chart: SimaiParser.parse("(120){#0.01}1,2,E"))
        #expect(index.highlights(at: 0.015).current != nil)
        #expect(index.highlights(at: 0.021).current == nil)
        let final = PlaybackSourceIndex(chart: SimaiParser.parse("(120){#0.01}1,2"))
        #expect(final.highlights(at: 0.015).current != nil)
        #expect(final.highlights(at: 0.021).current == nil)
    }
}
