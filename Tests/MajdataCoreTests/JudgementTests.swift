import Testing
import Foundation
@testable import MajdataCore

struct JudgementTests {
    @Test func shortPressRemainsVisibleWithoutExtendingLogicalInput() throws {
        var chart = ParsedChart()
        chart.notes = (0..<20).map { Note(id: $0, kind: .tap, lane: 1, time: 1.013 + Double($0) * 0.001) }
        let recording = try RegionRecording.simulate(chart)
        #expect(recording.results.count == 20 && recording.results.values.allSatisfy { $0.grade == .critical })
        #expect(!recording.sensors(at: 1.0135).contains(0))
        #expect(recording.highlightedSensors(at: 1.0135).contains(0))
        for fps in [20.0, 30, 60, 120] {
            let nextFrame = ceil(1.013 * fps) / fps
            #expect(recording.highlightedSensors(at: nextFrame).contains(0))
        }
        for time in [10.0, 0, 1.012, -1, 1.113, 1.1, 1.013, 0] {
            #expect(recording.highlightedSensors(at: time).contains(0) == (time >= 1.013 && time < 1.112))
        }
        #expect(recording.highlightedSensors(at: 1.0135, persistence: 0) == recording.sensors(at: 1.0135))
    }
    @Test func polygonsAndBoundaryContacts() throws {
        #expect(SensorGeometry.polygons.count == 34)
        #expect(Set(SensorGeometry.polygons.map(\.id)).count == 33)
        for polygon in SensorGeometry.polygons {
            #expect(polygon.contains(polygon.center), "\(polygon.name) centre")
            #expect(polygon.contains(polygon.vertices[0]))
            #expect(SensorGeometry.contacts(at: polygon.center, radius: 0).contains(polygon.id))
        }
        #expect(SensorGeometry.contacts(at: Point(0, 0)).contains(16))
        #expect(SensorGeometry.contacts(at: Point(7, 7)).isEmpty)
        for lane in 1...8 {
            let p = SlideGeometry.lane(lane, radius: 4.8)
            #expect(SensorGeometry.contacts(at: p, radius: 0).contains(lane - 1))
            for group in ["A", "B", "D", "E"] {
                let p = SlideGeometry.touch(group, lane: lane)
                #expect(SensorGeometry.contacts(at: Point(p.x * 4.8, p.y * 4.8)).contains(RegionJudgeEngine.sensor(Note(kind: .touch, lane: lane, area: group, time: 0))))
            }
        }
    }
    @Test func heldRegionCannotHitAgainAndButtonsCannotHitTouch() {
        let chart = SimaiParser.parse("(120){4},,1,1,A1,E")
        var engine = RegionJudgeEngine(chart: chart)
        engine.update(.init(time: 1, sensors: [0]))
        engine.update(.init(time: 1.7, sensors: [0]))
        #expect(engine.results[chart.notes[0].id]?.grade == .critical)
        #expect(engine.results[chart.notes[1].id]?.grade == .miss)
        engine.update(.init(time: 2, sensors: [0], buttons: [1]))
        engine.update(.init(time: 2.4, sensors: [0], buttons: [1]))
        #expect(engine.results[chart.notes[2].id]?.grade == .miss)
        var replay = RegionJudgeEngine(chart: chart)
        replay.update(.init(time: 1, sensors: [0])); replay.update(.init(time: 1.4))
        replay.update(.init(time: 1.5, sensors: [0]))
        #expect(replay.results[chart.notes[1].id]?.grade == .critical)
    }
    @Test func headTimingWindowsAndEX() {
        let tap = Note(kind: .tap, lane: 1, time: 0)
        #expect(RegionJudgeEngine.headGrade(tap, difference: -0.151) == nil)
        for (t, grade) in [(0.016, JudgeGrade.critical), (0.02, .perfect1), (0.04, .perfect2), (0.06, .great1), (0.08, .great2), (0.09, .great3), (0.14, .good), (0.151, .miss)] {
            #expect(RegionJudgeEngine.headGrade(tap, difference: t) == grade)
        }
        let ex = Note(kind: .tap, lane: 1, time: 0, isEX: true)
        #expect(RegionJudgeEngine.headGrade(ex, difference: 0.14) == .critical)
        let touch = Note(kind: .touch, lane: 1, time: 0)
        #expect(RegionJudgeEngine.headGrade(touch, difference: -0.14) == .critical)
        #expect(RegionJudgeEngine.headGrade(touch, difference: 0.31) == .good)
    }
    @Test func areaQueueRequiresOrderReleaseAndAlternatives() {
        var queue = SlideAreaQueue([.init([0]), .init([1, 9], canSkip: false), .init([2], isLast: true)])
        queue.update([2]); #expect(queue.index == 0)
        queue.update([0]); #expect(queue.index == 0)
        queue.update([]); #expect(queue.index == 1)
        queue.update([2]); #expect(!queue.finished)
        queue.update([9]); #expect(!queue.finished)
        queue.update([2]); #expect(queue.finished)
        var release = SlideAreaQueue([.init([0, 8], canSkip: false), .init([1], canSkip: false, isLast: true)])
        release.update([0]); release.update([0]); #expect(release.index == 0)
        release.update([8]); #expect(release.index == 1)
    }
    @Test func wifiNeedsAllThreePaths() throws {
        var chart = ParsedChart()
        let segment = SlideSegment(shape: "w", start: 1, end: 5, startTime: 1, duration: 1)
        chart.notes = [Note(id: 0, kind: .slide, lane: 1, time: 0, segments: [segment])]
        var engine = RegionJudgeEngine(chart: chart)
        for (time, sensors) in [(0.0, Set([0])), (1.1, [8]), (1.5, [16]), (1.9, [4])] { engine.update(.init(time: time, sensors: sensors)) }
        #expect(engine.results[0] == nil)
        engine.update(.init(time: 2.7)); #expect(engine.results[0]?.grade == .miss)
        var all = RegionJudgeEngine(chart: chart)
        for (time, sensors) in [(0.0, Set([0])), (1.1, [15, 8, 9]), (1.5, [14, 16, 10]), (1.9, [5, 4, 3])] { all.update(.init(time: time, sensors: sensors)) }
        #expect(all.results[0]?.grade == .critical)
    }
    @Test func holdReleaseAndTouchGroupMajority() {
        let chart = SimaiParser.parse("(120){4},,1hx[4:4],E")
        var full = RegionJudgeEngine(chart: chart)
        full.update(.init(time: 1, sensors: [0])); full.update(.init(time: 3, sensors: [0]))
        #expect(full.results[0]?.grade == .critical)
        var released = RegionJudgeEngine(chart: chart)
        released.update(.init(time: 1, sensors: [0])); released.update(.init(time: 1.2)); released.update(.init(time: 3))
        #expect(released.results[0]?.grade == .good)
        let touch = SimaiParser.parse("(120){4},,A1/E1/B1,E")
        var group = RegionJudgeEngine(chart: touch)
        group.update(.init(time: 1, sensors: [0])); #expect(group.results.count == 1)
        group.update(.init(time: 1.01, sensors: [0, 25])); #expect(group.results.count == 3)
    }
    @Test func shortHoldRoundingAndDenseAutomaticClicks() throws {
        let chart = SimaiParser.parse("(200){4},,1h[4:1],{64}2,2,2,2,E")
        let replay = try RegionRecording.simulate(chart)
        #expect(replay.results.count == chart.notes.count)
        #expect(replay.results.values.allSatisfy { $0.grade == .critical })
    }
    @Test func deterministicSimulationAndAllSlideShapes() throws {
        let chart = SimaiParser.parse("(120){4},,1h[4:4]/Ch[4:2],,2w6[2:1],,3p7[2:1],E")
        let a = try RegionRecording.simulate(chart), b = try RegionRecording.simulate(chart)
        #expect(a.results == b.results)
        #expect(a.results.count == chart.notes.count)
        #expect(a.sensors(at: -10).isEmpty && a.sensors(at: 100).isEmpty)
        print("REGION fixture", a.results)
        for shape in ["-", "^", ">", "<", "v", "p", "q", "pp", "qq", "s", "z", "V", "w"] {
            for start in 1...8 { for end in 1...8 {
                let s = SlideSegment(shape: shape, start: start, end: end, turn: (start + 5) % 8 + 1, startTime: 1, duration: 1)
                guard SlideGeometry.key(for: s) != nil else { continue }
                let plan = SlideJudgePlan(segment: s)
                #expect(!plan.queues.isEmpty && plan.queues.allSatisfy { !$0.isEmpty })
                #expect(plan.targetTime >= (shape == "w" ? 1.80 : 1.85) && plan.targetTime < 2)
            } }
        }
    }
}
