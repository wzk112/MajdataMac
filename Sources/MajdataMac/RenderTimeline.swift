import Foundation
import MajdataCore

/// An interval tree keeps per-frame work proportional to visible notes, including long holds.
/// Seeking queries absolute chart time; no incremental animation state can get stuck after a seek.
@MainActor final class RenderTimeline {
    private struct Key: Hashable { var revision: UUID; var speed: Double; var touch: Double }
    private struct Entry { var note: Note; var start: Double; var end: Double }
    private static var cache: [(Key, RenderTimeline)] = []
    private let entries: [Entry]
    private var maxEnd: [Double]
    private let judgeTimes: [Double]
    private let weights: [Int]
    private let breaks: [Int]
    let totalWeight: Int
    let totalBreaks: Int

    static func prepared(_ chart: ParsedChart, speed: Double, touch: Double) -> RenderTimeline {
        let key = Key(revision: chart.renderRevision, speed: speed, touch: touch)
        if let value = cache.first(where: { $0.0 == key })?.1 { return value }
        let value = RenderTimeline(chart, speed: speed, touch: touch)
        cache.append((key, value)); if cache.count > 3 { cache.removeFirst() }
        return value
    }
    private init(_ chart: ParsedChart, speed: Double, touch: Double) {
        let velocity = NoteMotion.velocity(setting: speed)
        entries = chart.notes.map { note in
            let lead: Double
            if note.kind == .touch || note.kind == .touchHold { lead = NoteMotion.touchDuration(speed: touch * note.speed) }
            else { lead = (note.kind == .slide ? 3.926913 : 6.075) / max(0.01, velocity * note.speed) }
            return Entry(note: note, start: note.time - lead, end: note.endTime + 1.4)
        }.sorted { $0.start < $1.start }
        maxEnd = Array(repeating: -.infinity, count: max(1, entries.count * 4))
        let judged = chart.notes.sorted { $0.judgeTime < $1.judgeTime }
        judgeTimes = judged.map(\.judgeTime)
        var weightPrefix = [0], breakPrefix = [0]
        for n in judged { weightPrefix.append(weightPrefix.last! + n.weight); breakPrefix.append(breakPrefix.last! + (n.isBreak ? 1 : 0)) }
        weights = weightPrefix; breaks = breakPrefix
        totalWeight = weightPrefix.last!; totalBreaks = breakPrefix.last!
        if !entries.isEmpty { build(1, 0, entries.count) }
    }
    private func build(_ node: Int, _ lo: Int, _ hi: Int) {
        if hi - lo == 1 { maxEnd[node] = entries[lo].end; return }
        let mid = (lo + hi) / 2
        build(node * 2, lo, mid); build(node * 2 + 1, mid, hi)
        maxEnd[node] = max(maxEnd[node * 2], maxEnd[node * 2 + 1])
    }
    func visible(at time: Double) -> [Note] {
        guard !entries.isEmpty else { return [] }
        var result: [Note] = []
        func visit(_ node: Int, _ lo: Int, _ hi: Int) {
            guard entries[lo].start <= time, maxEnd[node] >= time else { return }
            if hi - lo == 1 { result.append(entries[lo].note); return }
            let mid = (lo + hi) / 2
            visit(node * 2, lo, mid); visit(node * 2 + 1, mid, hi)
        }
        visit(1, 0, entries.count)
        return result.sorted { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }
    }
    func score(at time: Double) -> (combo: Int, weight: Int, breaks: Int) {
        var lo = 0, hi = judgeTimes.count
        while lo < hi { let mid = (lo + hi) / 2; if judgeTimes[mid] <= time { lo = mid + 1 } else { hi = mid } }
        return (lo, weights[lo], breaks[lo])
    }
}
