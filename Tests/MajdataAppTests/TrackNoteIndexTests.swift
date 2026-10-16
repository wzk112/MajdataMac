import Testing
import Foundation
import MajdataCore
@testable import MajdataMac

struct TrackNoteIndexTests {
    private func notes(count: Int) -> [Note] {
        (0..<count).map { i in
            Note(id: i, kind: i % 13 == 0 ? .hold : .tap, lane: i % 8 + 1,
                 time: Double(i) * 0.05 - 2, duration: i % 13 == 0 ? Double(i % 71 + 1) : 0)
        }
    }
    @Test func queriesPreserveOrderBoundariesAndLongNotesAcrossSeeks() {
        let source = Array(notes(count: 3000).reversed())
        let index = TrackNoteIndex(source)
        // Reverse order, negative times, inclusive edges, and nonsequential seeks.
        for start in [12.0, -4, 130, 0, 38.5, 1, 145, -2] {
            for span in [0.0, 0.05, 8, 50] {
                let expected = source.filter { $0.time <= start + span && $0.endTime >= start }
                #expect(index.visible(from: start, through: start + span) == expected)
            }
        }
        #expect(TrackNoteIndex([]).visible(from: 0, through: 1).isEmpty)
        #expect(index.visible(from: 2, through: 1).isEmpty)
    }
    @Test func viewportQueryBenchmark() {
        let source = notes(count: 30_000), index = TrackNoteIndex(source)
        let ranges = (0..<500).map { Double(($0 * 7919) % 1400) }
        let clock = ContinuousClock()
        var linearCount = 0, indexedCount = 0
        let linear = clock.measure {
            for start in ranges { linearCount += source.filter { $0.time <= start + 8 && $0.endTime >= start }.count }
        }
        let indexed = clock.measure {
            for start in ranges { indexedCount += index.visible(from: start, through: start + 8).count }
        }
        #expect(linearCount == indexedCount && indexedCount > 0)
        print("TRACK QUERY BENCHMARK: 30000 notes, 500 seeks, linear=\(linear), indexed=\(indexed), matches=\(indexedCount)")
    }
}
