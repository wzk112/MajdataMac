import Testing
import Foundation
@testable import MajdataCore

@Suite struct SimaiTests {
    @Test func metadataRoundtrip() {
        let text = "\u{feff}&title=Title=With=Equals\r\n&artist=作者\r\n&first=-0.25\r\n&custom=value\r\n&inote_1=(120){4}1,E\r\n&inote_7=(150){8}2,E\r\n&des_7=特別\r\n"
        let d = ChartDocument(text: text)
        #expect(d.title == "Title=With=Equals")
        #expect(d.offset == -0.25)
        #expect(d.chart(6) == "(150){8}2,E")
        #expect(d["custom"] == "value")
        let saved = ChartDocument(text: d.serialized)
        #expect(saved["des_7"] == "特別")
        #expect(saved.serialized == d.serialized)
        #expect(!d.serialized.hasPrefix("\u{feff}"))
    }
    @Test func zeroDivisionRegression138() {
        let chart = SimaiParser.parse("(120){0},1,E")
        #expect(chart.hasErrors)
        #expect(chart.notes.allSatisfy { $0.time.isFinite })
        #expect(chart.duration.isFinite)
    }
    @Test(arguments: ["(120", "(0){4}1,", "(-120){4}1,", "{4}1,", "(NaN){4}1,", "(120){4}1-5[4:0", "(120){4}1h[0:1],", "(120){4}1-2[4:1],", "(120){4}1w4[4:1],"])
    func malformedInputIsDiagnostic(_ input: String) {
        let chart = SimaiParser.parse(input)
        #expect(chart.hasErrors)
        #expect(chart.duration.isFinite)
    }
    @Test func timingsAndEndMarker() {
        let chart = SimaiParser.parse("(120){4}1,2,(240){8}3,E,,,,4,", offset: -0.5)
        #expect(!chart.hasErrors)
        #expect(chart.notes.map(\.time) == [-0.5, 0, 0.5])
        #expect(abs(chart.endTime - 0.625) < 0.000001)
    }
    @Test func pseudoEachRegressionEdit80() {
        for bpm in [60, 150, 240] {
            let chart = SimaiParser.parse("(\(bpm)){4}1`2`3,E")
            #expect(chart.notes.map(\.time) == [0, 0.001, 0.002])
        }
    }
    @Test func allKindsAndFlags() {
        let chart = SimaiParser.parse("(120){4}12,1bx,2h[4:2],A1f,Ch[4:1],3-7[4:1],E")
        #expect(!chart.hasErrors)
        #expect(chart.count(.tap) == 4)
        #expect(chart.count(.hold) == 1)
        #expect(chart.count(.touch) == 1)
        #expect(chart.count(.touchHold) == 1)
        #expect(chart.count(.slide) == 1)
        #expect(chart.notes[2].isBreak && chart.notes[2].isEX)
        #expect(chart.notes.first?.isEach == true)
    }
    @Test func newDurationIssue103() {
        let a = SimaiParser.parse("(120){4}1-5[3##8:3],E").notes.first { $0.kind == .slide }!
        #expect(a.segments[0].startTime == 3)
        #expect(a.segments[0].duration == 0.75)
        let b = SimaiParser.parse("(120){4}1-5[3##160#8:3],E").notes.first { $0.kind == .slide }!
        #expect(b.segments[0].startTime == 3)
        #expect(b.segments[0].duration == 0.5625)
    }
    @Test func connectedSlidesAndIndependentWifi() {
        let chart = SimaiParser.parse("(120){8}1-3-5-7[4:1],3,5,1w5[4:1]*w5[4:1]*w5[4:1],E")
        #expect(!chart.hasErrors)
        let slides = chart.notes.filter { $0.kind == .slide }
        #expect(slides.count == 4)
        #expect(slides[0].segments.count == 3)
        #expect(abs(slides[0].endTime - 1.0) < 0.000001)
        #expect(Set(slides.map(\.id)).count == 4)
        #expect(chart.count(.tap) == 4)
    }
    @Test func longSlideSurvivesEndMarker() {
        let chart = SimaiParser.parse("(120){4}1-5[1:4],E,")
        #expect(chart.endTime == 0.5)
        #expect(chart.duration == 8.5)
    }
    @Test func allSlideShapesUseOriginalCoordinates() {
        for text in ["1-3", "1-4", "1-5", "1-6", "1-7", "1^3", "1^7", "1>1", "1<1", "1v3", "1p5", "1q5", "1pp5", "1qq5", "1s5", "1z5", "1V35", "1V75", "1w5"] {
            let chart = SimaiParser.parse("(120){4}\(text)[4:1],E")
            #expect(!chart.hasErrors, "\(text): \(chart.diagnostics)")
            if let segment = chart.notes.first(where: { $0.kind == .slide })?.segments.first {
                let points = SlideGeometry.points(for: segment)
                #expect(points.count > 3)
                #expect(points.first!.distance(to: SlideGeometry.lane(segment.start)) < 0.001)
                #expect(points.last!.distance(to: SlideGeometry.lane(segment.end)) < 0.001)
            }
        }
    }
    @Test func transformPreservesTimingAndComments() {
        let text = "(180){16}<HS*2>1-5[4:1],D2/E8,|| 123 p q\n3<7[4:1],E"
        for transform in [ChartTransform.mirrorHorizontal, .mirrorVertical] {
            let result = transform.apply(to: transform.apply(to: text))
            #expect(result == text)
        }
        var rotated = text
        for _ in 0..<8 { rotated = ChartTransform.rotateClockwise.apply(to: rotated) }
        #expect(rotated == text)
        #expect(ChartTransform.rotateClockwise.apply(to: text).contains("(180){16}<HS*2>2-6[4:1]"))
    }
    @Test func subdivisionPreservesRhythm() {
        let text = "(120){8}1,,2,,,3,,,E"
        let a = SimaiParser.parse(text)
        let b = SimaiParser.parse(ChartTransform.subdivide(text, factor: 2))
        #expect(a.notes.map(\.time) == b.notes.map(\.time))
        #expect(a.endTime == b.endTime)
    }
    @Test func unicodeLocationsAreUTF16() {
        let chart = SimaiParser.parse("|| 🎵 中文\n(120){4}9,")
        #expect(chart.hasErrors)
        #expect(chart.diagnostics.first?.location.line == 2)
        #expect(chart.diagnostics.first?.location.offset == 17)
    }
    @Test func partialNotesNeverLeakAfterMalformedChain() {
        let chart = SimaiParser.parse("(120){4}1-3[4:1]-5,2,E")
        #expect(chart.hasErrors)
        #expect(chart.notes.count == 1)
        #expect(chart.notes[0].lane == 2)
    }
    @Test func deterministicFuzzNoCrashesOrInfinities() {
        var seed: UInt64 = 1964
        let alphabet = Array("12345678ABCDE(),{}[]<>HS*#:/hbxpqwV` E\n")
        for _ in 0..<1000 {
            var text = "(120){4}"
            for _ in 0..<80 { seed = seed &* 6364136223846793005 &+ 1; text.append(alphabet[Int(seed % UInt64(alphabet.count))]) }
            let chart = SimaiParser.parse(text)
            #expect(chart.duration.isFinite)
            #expect(chart.notes.allSatisfy { $0.time.isFinite && $0.endTime.isFinite })
        }
    }
}
