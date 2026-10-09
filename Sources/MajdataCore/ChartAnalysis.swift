import Foundation

public struct InputConflict: Identifiable, Sendable {
    public enum Kind: Sendable { case early, held, shared }
    public var target: Note
    public var causes: [Note]
    public var kind: Kind
    public var eventTime: Double
    public var grade: JudgeGrade
    public var id: Int { target.id }
    public var difference: Double { eventTime - target.time }
    public var region: String { target.area == "C" ? "C" : target.area + String(target.lane) }
    public var title: String {
        switch kind {
        case .early: return "\(region) 被提前触发 · \(grade.title)"
        case .held: return "\(region) 持续按住，缺少新的按下事件"
        case .shared: return "\(region) 同刻重叠，按下事件被另一音符使用"
        }
    }
    public var detail: String {
        switch kind {
        case .early: return String(format: "%.3f 秒进入区域，提前 %.1f ms。", eventTime, -difference * 1000)
        case .held: return String(format: "%.3f 秒已经处于按下状态；到点的自动点击未产生 OFF → ON。", target.time)
        case .shared: return "同一区域的一次按下只能供一个待判定头音符使用；Touch 组补判另行处理。"
        }
    }
}

/// Counts occupied outer areas; this is deliberately not a hand-count verdict.
public struct MultiPressHint: Identifiable, Sendable {
    public var time: Double
    public var notes: [Note]
    public var id: Double { time }
    public var lanes: [Int] { Set(notes.map(\.lane)).sorted() }
}

public struct ChartAnalysisReport: Sendable {
    public var recording: RegionRecording
    public var mixedRecording: RegionRecording
    public var buttonRecording: RegionRecording
    public var buttonResolved: Set<Int> {
        Set(recording.results.values.filter { $0.grade != .critical && buttonRecording.results[$0.noteID]?.grade == .critical }.map(\.noteID))
    }
    public var inputConflicts: [InputConflict]
    public func recording(for mode: AutomaticInputMode) -> RegionRecording {
        switch mode { case .touchscreen: recording; case .outerButtons: buttonRecording; case .mixed: mixedRecording }
    }
    public var multiPressHints: [MultiPressHint]
}

public enum ChartAnalysis {
    /// Uses the same timestamped OFF -> ON events and consumed results as playback.
    /// Geometric proximity alone, future slide starts and harmless CP contacts are
    /// not conflicts. This is a deterministic input model, not a real-hand solver.
    public static func inspect(_ chart: ParsedChart) throws -> ChartAnalysisReport {
        let recording = try RegionRecording.simulate(chart)
        let byID = Dictionary(uniqueKeysWithValues: chart.notes.map { ($0.id, $0) })
        var conflicts: [InputConflict] = []
        for note in chart.notes where note.kind != .slide {
            try Task.checkCancellation()
            let sensor = RegionJudgeEngine.sensor(note)
            if let head = recording.heads[note.id] {
                guard head.grade != .critical, head.difference < 0,
                      let press = recording.lastPress(sensor: sensor, at: head.time), abs(press.time - head.time) < 1e-8 else { continue }
                let causes = press.noteIDs.subtracting([note.id]).sorted().compactMap { byID[$0] }
                guard !causes.isEmpty else { continue }
                conflicts.append(InputConflict(target: note, causes: causes, kind: .early, eventTime: press.time, grade: head.grade))
            } else {
                // Diagnose a blocked automatic click only with a contact at its
                // scheduled time; a remote earlier edge is insufficient evidence.
                let causes = recording.contactOwners(sensor: sensor, at: note.time).subtracting([note.id]).sorted().compactMap { byID[$0] }
                guard !causes.isEmpty else { continue }
                let wasHeld = recording.sensors(at: note.time - 1e-7).contains(sensor)
                conflicts.append(InputConflict(target: note, causes: causes, kind: wasHeld ? .held : .shared,
                    eventTime: note.time, grade: .miss))
            }
        }
        let outer = chart.notes.filter { $0.kind == .tap || $0.kind == .hold }
        let holds = outer.filter { $0.kind == .hold }
        var hints: [MultiPressHint] = []
        let groups = Dictionary(grouping: outer, by: { Int64(($0.time * 1_000_000).rounded()) })
        for group in groups.values {
            try Task.checkCancellation()
            let time = group.map(\.time).min()!
            // The final 0.2 s of Hold is not required by this judgement profile.
            let held = holds.filter { $0.time < time - 1e-6 && $0.endTime - 0.2 > time + 1e-9 }
            let notes = (group + held).sorted { $0.id < $1.id }
            if Set(notes.map(\.lane)).count > 2 { hints.append(MultiPressHint(time: time, notes: notes)) }
        }
        conflicts.sort { $0.target.time == $1.target.time ? $0.id < $1.id : $0.target.time < $1.target.time }
        hints.sort { $0.time < $1.time }
        return ChartAnalysisReport(recording: recording, mixedRecording: try RegionRecording.simulate(chart, inputMode: .mixed), buttonRecording: try RegionRecording.simulate(chart, inputMode: .outerButtons), inputConflicts: conflicts, multiPressHints: hints)
    }
}
