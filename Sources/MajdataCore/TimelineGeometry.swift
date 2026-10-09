import Foundation

/// A fixed coordinate system for a gesture. Never derive its origin from a seek result.
public struct TimelineViewport: Equatable, Sendable {
    public let lower: Double
    public let upper: Double
    public let span: Double
    public let start: Double
    public init(lower: Double, upper: Double, zoom: Double, start: Double) {
        self.lower = lower; self.upper = max(lower + 0.001, upper)
        span = (self.upper - lower) / min(128, max(1, zoom))
        self.start = min(max(lower, start), self.upper - span)
    }
    public func time(at x: Double, width: Double) -> Double {
        start + min(1, max(0, x / max(1, width))) * span
    }
    public func x(at time: Double, width: Double) -> Double { (time - start) / span * width }
    public func zoomed(to zoom: Double, anchor: Double, fraction: Double) -> Self {
        let newSpan = (upper - lower) / min(128, max(1, zoom))
        return Self(lower: lower, upper: upper, zoom: zoom, start: anchor - newSpan * fraction)
    }
    public func autoscrolled(pointerX: Double, width: Double, seconds: Double) -> Self {
        let edge = min(40, max(12, width * 0.04))
        let left = min(1, max(0, (edge - pointerX) / edge))
        let right = min(1, max(0, (pointerX - (width - edge)) / edge))
        let delta = (right * right - left * left) * span * 0.8 * min(0.1, max(0, seconds))
        return Self(lower: lower, upper: upper, zoom: (upper - lower) / span, start: start + delta)
    }
}

public struct TimelineGridLine: Sendable {
    public enum Kind: Sendable { case bar, beat, subdivision }
    public let time: Double
    public let kind: Kind
    public let bar: Int
}

public struct MusicalTimeline: Sendable {
    private struct Tempo: Sendable { var time: Double; var bpm: Double; var beat: Double }
    private var tempos: [Tempo] = []
    private let timings: [TimingPoint]
    private let end: Double
    public init(_ chart: ParsedChart) {
        timings = chart.timings; end = chart.endTime
        // Extreme but syntactically valid BPMs have no useful visible beat grid.
        // Bound display arithmetic independently of the parser's numeric range.
        for point in timings where point.bpm > 0 && point.bpm <= 1_000_000 {
            if let last = tempos.last {
                if last.bpm == point.bpm { continue }
                tempos.append(Tempo(time: point.time, bpm: point.bpm,
                    beat: last.beat + (point.time - last.time) * last.bpm / 60))
            } else { tempos.append(Tempo(time: point.time, bpm: point.bpm, beat: 0)) }
        }
    }
    public func sourceTime(at offset: Int) -> Double? {
        guard !timings.isEmpty else { return nil }
        var lo = 0, hi = timings.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if (timings[mid].sourceStart ?? timings[mid].location.offset) <= offset { lo = mid + 1 } else { hi = mid }
        }
        let point = timings[max(0, lo - 1)]
        if lo == timings.count, offset >= (point.sourceEnd ?? point.location.offset + point.location.length) { return end }
        return point.time
    }
    public func nearestCell(to time: Double) -> Double {
        var lo = 0, hi = timings.count
        while lo < hi { let mid = (lo + hi) / 2; if timings[mid].time < time { lo = mid + 1 } else { hi = mid } }
        let candidates = [lo > 0 ? timings[lo - 1].time : nil, lo < timings.count ? timings[lo].time : nil, end].compactMap { $0 }
        return candidates.min(by: { abs($0 - time) < abs($1 - time) }) ?? time
    }
    /// Quarter-note phase is continuous across tempo/divider changes. Meter is a display setting.
    public func grid(in viewport: TimelineViewport, width: Double, beatsPerBar: Int) -> [TimelineGridLine] {
        let meter = max(1, beatsPerBar), endTime = viewport.start + viewport.span
        var result: [TimelineGridLine] = []
        for (i, tempo) in tempos.enumerated() {
            let a = max(tempo.time, viewport.start)
            let b = min(i + 1 < tempos.count ? tempos[i + 1].time : max(end, endTime), endTime)
            guard a < b else { continue }
            let pixelsPerBeat = 60 / tempo.bpm / viewport.span * width
            // Hide dense minor lines; retain labeled bars across the entire viewport.
            let step = pixelsPerBeat >= 14 ? 1 : meter * max(1, Int(ceil(65 / max(0.000001, pixelsPerBeat * Double(meter)))))
            let firstBeat = tempo.beat + (a - tempo.time) * tempo.bpm / 60
            let lastBeat = tempo.beat + (b - tempo.time) * tempo.bpm / 60
            var beat = ceil((firstBeat - 1e-8) / Double(step)) * Double(step)
            while beat < lastBeat - 1e-8 && result.count < 10000 {
                let number = Int(beat.rounded()), bar = number / meter + 1
                result.append(TimelineGridLine(time: tempo.time + (beat - tempo.beat) * 60 / tempo.bpm,
                    kind: number % meter == 0 ? .bar : .beat, bar: bar))
                beat += Double(step)
            }
        }
        var previous = -Double.infinity
        for point in timings where point.time >= viewport.start && point.time <= endTime {
            let px = viewport.x(at: point.time, width: width)
            guard px - previous >= 7 else { continue }
            result.append(TimelineGridLine(time: point.time, kind: .subdivision, bar: 0)); previous = px
        }
        return result.sorted { $0.time < $1.time }
    }
}
