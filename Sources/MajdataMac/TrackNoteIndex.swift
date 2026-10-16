import MajdataCore

/// Rebuilt only when the chart changes. Queries include notes spanning the viewport,
/// and restore source order so overlapping heads keep the same drawing/hit priority.
struct TrackNoteIndex {
    private struct Entry { var note: Note; var order: Int }
    private let entries: [Entry]
    private var maxEnd: [Double]

    init(_ notes: [Note]) {
        entries = notes.enumerated().map { Entry(note: $0.element, order: $0.offset) }
            .sorted { $0.note.time == $1.note.time ? $0.order < $1.order : $0.note.time < $1.note.time }
        maxEnd = Array(repeating: -.infinity, count: max(1, notes.count * 4))
        if !entries.isEmpty { build(1, 0, entries.count) }
    }
    private mutating func build(_ node: Int, _ lo: Int, _ hi: Int) {
        if hi - lo == 1 { maxEnd[node] = entries[lo].note.endTime; return }
        let mid = (lo + hi) / 2
        build(node * 2, lo, mid); build(node * 2 + 1, mid, hi)
        maxEnd[node] = max(maxEnd[node * 2], maxEnd[node * 2 + 1])
    }
    func visible(from start: Double, through end: Double) -> [Note] {
        guard !entries.isEmpty, start <= end else { return [] }
        var found: [Entry] = []
        func visit(_ node: Int, _ lo: Int, _ hi: Int) {
            guard entries[lo].note.time <= end, maxEnd[node] >= start else { return }
            if hi - lo == 1 { found.append(entries[lo]); return }
            let mid = (lo + hi) / 2
            visit(node * 2, lo, mid); visit(node * 2 + 1, mid, hi)
        }
        visit(1, 0, entries.count)
        return found.sorted { $0.order < $1.order }.map(\.note)
    }
}
