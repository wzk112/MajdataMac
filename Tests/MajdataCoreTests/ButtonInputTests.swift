import Testing
import Foundation
@testable import MajdataCore

struct ButtonInputTests {
    @Test func independentButtonAndTouchAtSameInstant() throws {
        let chart = SimaiParser.parse("(120){4}1/A1,E")
        let inner = try RegionRecording.simulate(chart)
        #expect(inner.results.values.contains { $0.grade == .miss })
        let outer = try RegionRecording.simulate(chart, inputMode: .outerButtons)
        #expect(outer.results.count == 2 && outer.results.values.allSatisfy { $0.grade == .critical })
        #expect(outer.highlightedButtons(at: 0.04) == [1])
        #expect(outer.highlightedSensors(at: 0.04) == [0])
    }
    @Test func buttonDoesNotLightOrCompleteTouchPanel() throws {
        let chart = SimaiParser.parse("(120){4}1,E")
        let recording = try RegionRecording.simulate(chart, inputMode: .outerButtons)
        #expect(recording.highlightedSensors(at: 0.04).isEmpty)
        #expect(recording.highlightedButtons(at: 0.04) == [1])
        #expect(recording.highlightedButtons(at: 1).isEmpty)
        let touch = SimaiParser.parse("(120){4}A1,E")
        var engine = RegionJudgeEngine(chart: touch)
        engine.update(SensorFrame(time: 0, buttons: [1])); engine.update(SensorFrame(time: 1))
        #expect(engine.results.values.allSatisfy { $0.grade == .miss })
    }
    @Test func buttonModeStillAllowsEarlyTouchToJudgeTap() throws {
        var chart = ParsedChart()
        chart.notes = [Note(kind: .tap, lane: 1, time: 1)]
        var engine = RegionJudgeEngine(chart: chart)
        engine.update(SensorFrame(time: 0.9, sensors: [0]))
        engine.update(SensorFrame(time: 1, buttons: [1]))
        #expect(engine.results[chart.notes[0].id]?.grade != .critical)
    }
    @Test func mixedRoutingReleasesATouchDuringHold() throws {
        let chart = SimaiParser.parse("(120){4}1h[1:1],A1,2,E")
        let report = try ChartAnalysis.inspect(chart)
        #expect(report.recording.results.values.contains { $0.grade == .miss })
        #expect(report.mixedRecording.results.values.allSatisfy { $0.grade == .critical })
        #expect(report.mixedRecording.highlightedButtons(at: 0.6) == [1])
        #expect(report.mixedRecording.highlightedSensors(at: 0.54) == [0])
    }
    @Test func compareUserProvidedChart() throws {
        guard let path = ProcessInfo.processInfo.environment["MAJDATA_COMPARISON_CHART"] else { return }
        let document = ChartDocument(text: try String(contentsOfFile: path, encoding: .utf8))
        for difficulty in 0..<7 where !document.chart(difficulty).isEmpty {
            let chart = SimaiParser.parse(document.chart(difficulty), offset: document.offset)
            #expect(!chart.hasErrors)
            let report = try ChartAnalysis.inspect(chart)
            let inner = report.recording.results.values.filter { $0.grade != .critical }
            let outer = report.buttonRecording.results.values.filter { $0.grade != .critical }
            print("INPUT COMPARISON diff=\(difficulty + 1) notes=\(chart.notes.count) inner=\(inner.count) outer=\(outer.count) buttonResolved=\(report.buttonResolved.count) mixed=\(report.mixedRecording.results.values.filter { $0.grade != .critical }.count)")
            for result in outer where report.recording.results[result.noteID]?.grade == .critical {
                let note = try #require(chart.notes.first { $0.id == result.noteID })
                print("OUTER NEW time=\(note.time) kind=\(note.kind) lane=\(note.lane) grade=\(result.grade) delta=\(result.difference)")
            }
            for result in inner.sorted(by: { $0.noteID < $1.noteID }) {
                let note = try #require(chart.notes.first { $0.id == result.noteID })
                let causes = report.inputConflicts.first { $0.id == result.noteID }
                print("INPUT DETAIL time=\(note.time) area=\(note.area)\(note.lane) kind=\(note.kind) line=\(note.location.line) inner=\(result.grade) outer=\(String(describing: report.buttonRecording.results[note.id]?.grade)) delta=\(result.difference) cause=\(causes?.detail ?? "no head conflict") origins=\(causes?.causes.map { "\($0.kind)@\($0.time)" } ?? [])")
            }
        }
    }
}
