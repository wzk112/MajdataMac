import Foundation

public struct PlaybackSourceHighlights: Equatable, Sendable {
    public var current: NSRange?
    public var sustained: [NSRange]
    public var line: Int?
}

/// Independent of the editor's selection/caret; safe for reverse seeks and loops.
public struct PlaybackSourceIndex: Sendable {
    private var timings: [TimingPoint]
    private var sustained: [Note]
    private var end: Double
    public init(chart: ParsedChart) {
        timings = chart.timings
        sustained = chart.notes.filter { $0.kind == .hold || $0.kind == .touchHold || $0.kind == .slide }
        let last = chart.timings.last
        end = max(chart.endTime, (last?.time ?? 0) + (last.map { $0.duration ?? ($0.bpm > 0 ? 240 / $0.bpm / $0.subdivision : 0) } ?? 0))
    }
    public func highlights(at time: Double) -> PlaybackSourceHighlights {
        var lo = 0, hi = timings.count
        while lo < hi { let mid = (lo + hi) / 2; if timings[mid].time <= time + 1e-9 { lo = mid + 1 } else { hi = mid } }
        let cell = lo > 0 && time < end ? timings[lo - 1].location : nil
        let current = cell.map { NSRange(location: $0.offset, length: $0.length) }
        let held = Set(sustained.lazy.filter { $0.time <= time && time < $0.endTime }
            .map { NSRange(location: $0.location.offset, length: $0.location.length) })
            .filter { $0 != current }.sorted { $0.location < $1.location }
        return PlaybackSourceHighlights(current: current, sustained: held, line: cell?.line)
    }
}
