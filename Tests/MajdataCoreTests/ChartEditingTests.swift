import Testing
import Foundation
@testable import MajdataCore

@Suite struct ChartEditingTests {
    private func insert(_ token: String, at time: Double, in source: String) -> String? {
        ChartEditing.insert(token, at: time, in: source, chart: SimaiParser.parse(source))?.text
    }
    /// The edit must put a note exactly at the requested time and leave every other note where it was.
    private func check(_ source: String, _ token: String, at time: Double, sourceLocation: Testing.SourceLocation = #_sourceLocation) throws {
        let before = SimaiParser.parse(source)
        let edit = try #require(ChartEditing.insert(token, at: time, in: source, chart: before), sourceLocation: sourceLocation)
        let after = SimaiParser.parse(edit.text)
        #expect(after.diagnostics.isEmpty, sourceLocation: sourceLocation)
        #expect(after.notes.count == before.notes.count + 1, sourceLocation: sourceLocation)
        #expect(after.notes.contains { abs($0.time - time) < 1e-6 && $0.lane == 7 }, sourceLocation: sourceLocation)
        for note in before.notes {
            #expect(after.notes.contains { abs($0.time - note.time) < 1e-6 && $0.lane == note.lane && $0.kind == note.kind }, sourceLocation: sourceLocation)
        }
        #expect((edit.text as NSString).substring(with: edit.selection) == token, sourceLocation: sourceLocation)
    }
    @Test func fillsAnEmptyCellAndJoinsAnOccupiedOne() {
        // 120 BPM, {4}: one cell every 0.5 s.
        #expect(insert("3", at: 0.5, in: "(120){4}1,,5,E") == "(120){4}1,3,5,E")
        #expect(insert("3", at: 0, in: "(120){4}1,,5,E") == "(120){4}1/3,,5,E")
    }
    @Test func splitsACellWhenTheGridIsFiner() throws {
        #expect(insert("7", at: 0.25, in: "(120){4}1,5,E") == "(120){8}1,7,{4}5,E")
        #expect(insert("7", at: 0.25, in: "(120){4}1,{8}5,E") == "(120){8}1,7,{8}5,E")
        #expect(insert("7", at: 0.75, in: "(120){4}1,5,3,E") == "(120){4}1,{8}5,7,{4}3,E")
        try check("(120){4}1,5,E", "7", at: 0.125)
        try check("(120){8}1,2,3,4,{4}5,6,E", "7", at: 1.0 + 1.0 / 3)
        try check("(120){4}\n1h[4:2],,\n3-7[4:1],,E", "7", at: 0.75)
    }
    @Test func appendsAfterTheLastCell() throws {
        #expect(insert("7", at: 1.0, in: "(120){4}1,5,E") == "(120){4}1,5,7,E")
        #expect(insert("7", at: 2.0, in: "(120){4}1,5,E") == "(120){4}1,5,,,7,E")
        try check("(120){4}1,5,E", "7", at: 1.25)
        try check("(120){4}1,5", "7", at: 1.5)
    }
    @Test func refusesWhatItCannotExpress() {
        #expect(insert("7", at: -1, in: "(120){4}1,5,E") == nil)
        #expect(insert("7", at: 0.25, in: "(120){#0.3}1,5,E") == nil)
        #expect(insert("7", at: 0.5, in: "") == nil)
    }
    @Test func removesOnlyTheChosenToken() throws {
        let source = "(120){4}1/5b,3-7[4:1],E", chart = SimaiParser.parse(source)
        let five = try #require(chart.notes.first { $0.lane == 5 })
        #expect(ChartEditing.remove(five, from: source)?.text == "(120){4}1,3-7[4:1],E")
        let one = try #require(chart.notes.first { $0.lane == 1 })
        #expect(ChartEditing.remove(one, from: source)?.text == "(120){4}5b,3-7[4:1],E")
        let slide = try #require(chart.notes.first { $0.kind == .slide })
        #expect(ChartEditing.remove(slide, from: source)?.text == "(120){4}1/5b,,E")
    }
    @Test func togglesHeadFlags() throws {
        let source = "(120){4}1/5b,3-7[4:1],B2,C,E", chart = SimaiParser.parse(source)
        func note(_ test: (Note) -> Bool) throws -> Note { let found = chart.notes.first(where: test); return try #require(found) }
        #expect(ChartEditing.toggle("b", on: try note { $0.lane == 1 }, in: source)?.text == "(120){4}1b/5b,3-7[4:1],B2,C,E")
        #expect(ChartEditing.toggle("b", on: try note { $0.lane == 5 }, in: source)?.text == "(120){4}1/5,3-7[4:1],B2,C,E")
        #expect(ChartEditing.toggle("x", on: try note { $0.kind == .slide }, in: source)?.text == "(120){4}1/5b,3x-7[4:1],B2,C,E")
        #expect(ChartEditing.toggle("f", on: try note { $0.area == "B" }, in: source)?.text == "(120){4}1/5b,3-7[4:1],B2f,C,E")
        #expect(ChartEditing.toggle("f", on: try note { $0.area == "C" }, in: source)?.text == "(120){4}1/5b,3-7[4:1],B2,Cf,E")
    }
    @Test func deletingPseudoChordsPreservesEveryRemainingTimestamp() throws {
        for source in ["(120){4}1`3`5,7,E", "(120){4}12/4`35/6`7,8,E",
                       "|| 中文 🎵\n(150){8}1 / 2`3 / 4`5,6h[4:1],E"] {
            let chart = SimaiParser.parse(source, offset: 1.25)
            for victim in chart.notes {
                let edit = try #require(ChartEditing.remove(victim, from: source))
                let remaining = SimaiParser.parse(edit.text, offset: 1.25)
                #expect(!remaining.hasErrors)
                let expected = chart.notes.filter { $0.token != victim.token }
                #expect(remaining.notes.count == expected.count)
                for (actual, original) in zip(remaining.notes, expected) {
                    #expect(actual.lane == original.lane && actual.kind == original.kind)
                    #expect(actual.time == original.time && actual.endTime == original.endTime)
                }
            }
        }
    }
    @Test func compactChordFlagsKeepOtherNotesAndSelectOnlyTheEditedToken() throws {
        for source in ["(120){4}135,7,E", "|| 中文 🎵\n(120){4}1 3 5,7,E",
                       "(120){4}1|| comment\n35`7,8,E"] {
            let chart = SimaiParser.parse(source)
            for lane in [1, 3, 5] {
                for flag: Character in ["b", "x"] {
                    let note = try #require(chart.notes.first { $0.lane == lane })
                    let edit = try #require(ChartEditing.toggle(flag, on: note, in: source))
                    let after = SimaiParser.parse(edit.text)
                    #expect(!after.hasErrors)
                    #expect(after.notes.count == chart.notes.count)
                    #expect((edit.text as NSString).substring(with: edit.selection) == "\(lane)\(flag)")
                    for (actual, original) in zip(after.notes, chart.notes) {
                        #expect(actual.lane == original.lane && actual.time == original.time)
                        #expect(actual.isBreak == (original.lane == lane && flag == "b"))
                        #expect(actual.isEX == (original.lane == lane && flag == "x"))
                    }
                }
            }
        }
    }
    @Test func snapsToTheChosenDivisorFromTheTempoStart() {
        let line = MusicalTimeline(SimaiParser.parse("(120){4}1,,,,(60)1,,E"))
        #expect(abs(line.snap(0.26, divisor: 8) - 0.25) < 1e-9)
        #expect(abs(line.snap(0.26, divisor: 4) - 0.5) < 1e-9)
        // After the BPM change at 2 s a 1/4 step is one second long.
        #expect(abs(line.snap(2.6, divisor: 4) - 3) < 1e-9)
        #expect(abs(line.step(at: 2.6, divisor: 4) - 1) < 1e-9)
    }
    @Test func drawnZonesPickTheMatchingSlideShape() {
        for (shape, end) in [("-", 5), ("^", 3), ("v", 4), ("pp", 5), ("s", 5)] {
            let drawn = SlideMatching.zones(shape: shape, start: 1, end: end)
            #expect(!drawn.isEmpty)
            #expect(SlideMatching.shape(start: 1, end: end, drawn: drawn) == shape)
        }
        #expect(SlideMatching.shape(start: 1, end: 1, drawn: ["A1"]) != nil)
    }
    @Test func orderedStrokesPreserveEveryLegalPathIncludingFullCircleDirection() throws {
        var checked = 0
        for start in 1...8 {
            for end in 1...8 {
                for shape in ["-", "^", "v", "<", ">", "p", "q", "s", "z", "pp", "qq"] {
                    let segment = SlideSegment(shape: shape, start: start, end: end)
                    guard let expected = SlideGeometry.key(for: segment) else { continue }
                    let path = SlideGeometry.points(for: segment)
                    // Uneven sampling and stationary events must not change the result.
                    var stroke: [Point] = []
                    for (i, point) in path.enumerated() {
                        if i > 0 { stroke.append(path[i - 1].interpolated(to: point, at: 0.2)) }
                        stroke.append(point); stroke.append(point)
                    }
                    let picked = try #require(SlideMatching.shape(start: start, end: end, stroke: stroke))
                    let actual = try #require(SlideGeometry.key(for: SlideSegment(shape: picked, start: start, end: end)))
                    #expect(actual.name == expected.name && actual.mirror == expected.mirror,
                            "\(start)\(shape)\(end) became \(picked)")
                    checked += 1
                }
            }
        }
        #expect(checked == 544)
        #expect(SlideMatching.shape(start: 1, end: 1, stroke: []) == nil)
        #expect(SlideMatching.shape(start: 1, end: 1, stroke: [Point(1, 0), Point(1, 0)]) == nil)
        #expect(SlideMatching.shape(start: 1, end: 1, stroke: [Point(.nan, 0), Point(1, 0)]) == nil)
    }
}
