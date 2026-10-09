import Foundation
import MajdataCore

/// Five original side-panel categories. Touch Hold contributes to HOLD; BREAK is exclusive.
enum StageNoteCategory: Int, CaseIterable {
    case tap, hold, slide, touch, `break`
    var title: String { ["TAP", "HOLD", "SLIDE", "TOUCH", "BREAK"][rawValue] }
    init(_ note: Note) {
        if note.isBreak { self = .break }
        else { self = switch note.kind { case .tap: .tap; case .hold, .touchHold: .hold; case .slide: .slide; case .touch: .touch } }
    }
}
struct StageStatistics {
    var counts = [Int](repeating: 0, count: 5)
    var grades = [Int](repeating: 0, count: 5)
    var combo = 0
    var fast = 0
    var late = 0
    var dx = 0
    var baseScore = 0
    var classicBonus = 0
    var deluxeBonus = 0
    var judged: Int { counts.reduce(0, +) }
    var classicScore: Int { baseScore + classicBonus }
    func finaleRate(totalWeight: Int) -> Double { totalWeight > 0 ? Double(classicScore) / Double(totalWeight) * 100 : 0 }
    func deluxeRate(totalWeight: Int, breaks: Int) -> Double {
        (totalWeight > 0 ? Double(baseScore) / Double(totalWeight) * 100 : 0) + (breaks > 0 ? Double(deluxeBonus) / Double(breaks * 100) : 0)
    }
    mutating func add(_ note: Note, grade: JudgeGrade, difference: Double) {
        counts[StageNoteCategory(note).rawValue] += 1
        let bucket = switch grade { case .critical: 0; case .perfect1, .perfect2: 1; case .great1, .great2, .great3: 2; case .good: 3; case .miss: 4 }
        grades[bucket] += 1
        combo = grade == .miss ? 0 : combo + 1
        if grade != .critical && grade != .miss { if difference < 0 { fast += 1 } else if difference > 0 { late += 1 } }
        dx += grade.dx
        if note.isBreak {
            baseScore += [2500, 2500, 2500, 2000, 1500, 1250, 1000, 0][grade.rawValue]
            classicBonus += [100, 50, 0, 0, 0, 0, 0, 0][grade.rawValue]
            deluxeBonus += [100, 75, 50, 40, 40, 40, 30, 0][grade.rawValue]
        } else { baseScore += Int(Double(note.weight) * grade.factor) }
    }
}

/// Prefix snapshots allow forward playback and backward seeking with one binary search.
@MainActor final class StageStatisticsTimeline {
    private struct Key: Equatable { let chart: UUID; let recording: UUID? }
    private static var cache: [(Key, StageStatisticsTimeline)] = []
    private let times: [Double]
    private let values: [StageStatistics]
    let totals: [Int]
    let totalWeight: Int
    var totalNotes: Int { totals.reduce(0, +) }
    static func prepared(_ chart: ParsedChart, recording: RegionRecording?) -> StageStatisticsTimeline {
        let key = Key(chart: chart.renderRevision, recording: recording?.revision)
        if let cached = cache.first(where: { $0.0 == key }) { return cached.1 }
        let value = StageStatisticsTimeline(chart: chart, recording: recording)
        cache.append((key, value)); if cache.count > 3 { cache.removeFirst() }
        return value
    }
    init(chart: ParsedChart, recording: RegionRecording?) {
        var total = [Int](repeating: 0, count: 5)
        for note in chart.notes { total[StageNoteCategory(note).rawValue] += 1 }
        totals = total; totalWeight = chart.totalWeight
        let events = chart.notes.compactMap { note -> (Note, Double, JudgeGrade, Double)? in
            if let recording {
                guard let result = recording.results[note.id] else { return nil }
                return (note, result.time, result.grade, result.difference)
            }
            return (note, note.judgeTime, .critical, 0)
        }.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 < $1.1 }
        times = events.map { $0.1 }
        var score = StageStatistics(), snapshots = [score]
        for (note, _, grade, difference) in events { score.add(note, grade: grade, difference: difference); snapshots.append(score) }
        values = snapshots
    }
    func score(at time: Double) -> StageStatistics {
        var lo = 0, hi = times.count
        while lo < hi { let mid = (lo + hi) / 2; if times[mid] <= time { lo = mid + 1 } else { hi = mid } }
        return values[lo]
    }
}
