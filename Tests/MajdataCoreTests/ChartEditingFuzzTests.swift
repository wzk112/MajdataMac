import Testing
import Foundation
@testable import MajdataCore

@Suite struct ChartEditingFuzzTests {
    struct RNG: RandomNumberGenerator { var s: UInt64; mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s } }
    static let charts = [
        "(120){4}1,,5,,E",
        "(120){4}\n1,2,\n3,4,\nE\n",
        "(150){8}1,2,3,4,{16}5,6,7,8,1,2,3,4,{4}1h[4:2],,5-1[4:1],,E",
        "|| intro\n(180){4}1,|| c\n2,\n{8}3,4/5,6`7,\n(90){4}8,,1,E",
        "(120){4}<HS*2>1,2,<HS*1>3,4,E",
        "(120){4}1,2,3",
        "(120){4}1,2,3,",
        "(120)\n{4}\n1 , 2 ,\n 3/ 4 ,E",
        "(120){1}1,(240){2}2,3,{3}4,5,6,E",
        "(120){4},,,,E",
        "(200){4}1-5[4:1]*-3[4:1],,C1h[4:1]/B3,E",
    ]
    @Test func randomInsertRemoveKeepsEverythingElseInPlace() {
        var rng = RNG(s: 42), failures: [String] = [], refused = 0, done = 0
        for base in Self.charts {
            for offset in [0.0, 1.25] {
                var source = base
                for _ in 0..<60 {
                    let chart = SimaiParser.parse(source, offset: offset)
                    guard chart.diagnostics.isEmpty else { failures.append("DIAG before \(source) \(chart.diagnostics.map(\.message))"); break }
                    let line = MusicalTimeline(chart)
                    let divisor = [4, 8, 12, 16, 7, 32].randomElement(using: &rng)!
                    let raw = offset + Double.random(in: -0.5...(chart.endTime - offset + 3), using: &rng)
                    let time = line.snap(raw, divisor: divisor)
                    let lane = Int.random(in: 1...8, using: &rng)
                    if Int.random(in: 0..<4, using: &rng) == 0, let victim = chart.notes.randomElement(using: &rng) {
                        guard let edit = ChartEditing.remove(victim, from: source) else { failures.append("REMOVE nil \(source)"); continue }
                        let after = SimaiParser.parse(edit.text, offset: offset)
                        let gone = chart.notes.filter { $0.token == victim.token }.count
                        let expected = chart.notes.filter { $0.token != victim.token }
                        let unchanged = zip(after.notes, expected).allSatisfy { actual, original in
                            actual.lane == original.lane && actual.kind == original.kind && actual.time == original.time
                                && actual.endTime == original.endTime && actual.speed == original.speed
                        }
                        if !after.diagnostics.isEmpty || after.notes.count != chart.notes.count - gone || !unchanged { failures.append("REMOVE bad: \(source) -> \(edit.text) victim \(victim.lane)@\(victim.time) \(after.diagnostics.map(\.message))") }
                        else { source = edit.text; done += 1 }
                        continue
                    }
                    guard let edit = ChartEditing.insert("\(lane)", at: time, in: source, chart: chart) else { refused += 1; continue }
                    let after = SimaiParser.parse(edit.text, offset: offset)
                    var bad = !after.diagnostics.isEmpty || after.notes.count != chart.notes.count + 1
                    bad = bad || !after.notes.contains { abs($0.time - time) < 1e-6 && $0.lane == lane && $0.kind == .tap }
                    for note in chart.notes where !after.notes.contains(where: { abs($0.time - note.time) < 1e-6 && $0.lane == note.lane && $0.kind == note.kind && abs($0.endTime - note.endTime) < 1e-6 && $0.speed == note.speed }) { bad = true }
                    if (edit.text as NSString).substring(with: edit.selection) != "\(lane)" { bad = true }
                    if bad { failures.append("INSERT bad: [\(source)] + \(lane)@\(time) div \(divisor) -> [\(edit.text)] \(after.diagnostics.map(\.message))") } else { source = edit.text; done += 1 }
                }
            }
        }
        // A refusal is fine; a silently wrong chart is not.
        #expect(done > 1000 && refused < 100)
        #expect(failures.isEmpty, "\(failures.prefix(5))")
    }
}
