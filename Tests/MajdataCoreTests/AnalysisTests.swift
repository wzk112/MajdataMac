import Testing
import Foundation
@testable import MajdataCore

struct AnalysisTests {
    private func slideChart() -> ParsedChart {
        var chart = ParsedChart()
        chart.notes = [Note(id: 0, kind: .slide, lane: 1, time: 0,
                            segments: [.init(shape: "-", start: 1, end: 5, startTime: 1, duration: 1)])]
        return chart
    }
    @Test func slideEntryMustActuallyTriggerAnEarlyJudgement() throws {
        let base = slideChart()
        let recording = try RegionRecording.simulate(base)
        let entry = try #require(recording.presses.first { $0.sensor == 4 }).time
        for (delta, ex, count) in [(0.08, false, 1), (0.005, false, 0), (-0.08, false, 0), (0.08, true, 0)] {
            var chart = base
            chart.notes.append(Note(id: 1, kind: .tap, lane: 5, time: entry + delta, isEX: ex))
            let report = try ChartAnalysis.inspect(chart)
            #expect(report.inputConflicts.count == count)
            if count > 0 {
                let issue = try #require(report.inputConflicts.first)
                #expect(issue.kind == .early && issue.causes.map(\.id) == [0])
                #expect(abs(issue.difference + delta) < 1e-8)
                #expect(issue.grade == .great2)
            }
        }
    }
    @Test func launchOverlapFutureSlideAndReleasedEndpointAreNotConflicts() throws {
        for time in [0.875, 1.0, 2.08] {
            var chart = slideChart()
            chart.notes.append(Note(id: 1, kind: .hold, lane: time > 2 ? 5 : 1, time: time, duration: 0.05))
            let report = try ChartAnalysis.inspect(chart)
            #expect(report.inputConflicts.isEmpty)
            #expect(report.recording.heads[1]?.grade == .critical)
        }
    }
    @Test func heldInputAndCompetingHeadsHaveConcreteCauses() throws {
        var chart = ParsedChart()
        chart.notes = [Note(id: 0, kind: .hold, lane: 1, time: 1, duration: 1), Note(id: 1, kind: .tap, lane: 1, time: 1.5)]
        let held = try ChartAnalysis.inspect(chart)
        #expect(held.inputConflicts.count == 1)
        #expect(held.inputConflicts.first?.kind == .held)
        #expect(held.inputConflicts.first?.causes.map(\.id) == [0])
        chart.notes = [Note(id: 0, kind: .tap, lane: 1, time: 1), Note(id: 1, kind: .tap, lane: 1, time: 1)]
        let shared = try ChartAnalysis.inspect(chart)
        #expect(shared.inputConflicts.count == 1)
        #expect(shared.inputConflicts.first?.kind == .shared)
    }
    @Test func multiPressUsesRegionsAndSustainedHoldsNotTouchCount() throws {
        let touches = SimaiParser.parse("(120){4},,A1/E1/B1/E2/B2/C,E")
        #expect(try ChartAnalysis.inspect(touches).multiPressHints.isEmpty)
        var chart = ParsedChart()
        chart.notes = [Note(id: 0, kind: .hold, lane: 1, time: 1, duration: 2), Note(id: 1, kind: .tap, lane: 3, time: 2), Note(id: 2, kind: .tap, lane: 5, time: 2)]
        let report = try ChartAnalysis.inspect(chart)
        #expect(report.multiPressHints.count == 1)
        #expect(report.multiPressHints.first?.lanes == [1, 3, 5])
        chart.notes[1].time = 2.9; chart.notes[2].time = 2.9
        #expect(try ChartAnalysis.inspect(chart).multiPressHints.isEmpty)
        chart.notes[1].lane = 1; chart.notes[1].time = 2; chart.notes[2].time = 2
        #expect(try ChartAnalysis.inspect(chart).multiPressHints.isEmpty)
    }
    @Test func realChartAnalysis() throws {
        guard let folder = ProcessInfo.processInfo.environment["MAJDATA_REAL_CHART"] else { return }
        let document = ChartDocument(text: try String(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent("maidata.txt"), encoding: .utf8))
        let chart = SimaiParser.parse(document.chart(5), offset: document.offset)
        let report = try ChartAnalysis.inspect(chart)
        print("ANALYSIS REAL inputConflicts=\(report.inputConflicts.count) multiPressHints=\(report.multiPressHints.count) results=\(report.recording.results.count)")
        for issue in report.inputConflicts { print("ANALYSIS REAL \(issue.target.time) \(issue.title) \(issue.detail)") }
        for time in [16.0, 18.0, 21.5] {
            for note in chart.notes where abs(note.time - time) < 1e-8 && note.kind != .slide {
                #expect(report.recording.heads[note.id]?.grade == .critical)
                #expect(!report.inputConflicts.contains { $0.id == note.id })
                print("ANALYSIS VERIFIED time=\(time) note=\(note.id) head=\(String(describing: report.recording.heads[note.id]?.grade))")
            }
        }
        if let path = ProcessInfo.processInfo.environment["MAJDATA_ANALYSIS_DUMP"] {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(chart).write(to: URL(fileURLWithPath: path))
        }
    }
}
