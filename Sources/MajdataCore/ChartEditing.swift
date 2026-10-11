import Foundation

/// A text change produced by a mouse action, plus the range to select afterwards.
public struct ChartEdit: Equatable, Sendable {
    public var text: String
    public var selection: NSRange
    public init(text: String, selection: NSRange) { self.text = text; self.selection = selection }
}

/// Mouse edits are translations into simai text: the text stays the only source of truth.
/// Every function returns nil when it cannot express the edit without guessing.
public enum ChartEditing {
    /// Smallest n/q equal to `value`, or nil when it needs a denominator above `limit`.
    static func fraction(_ value: Double, limit: Int) -> (n: Int, q: Int)? {
        guard value.isFinite, value >= -1e-9 else { return nil }
        for q in 1...limit {
            let n = (value * Double(q)).rounded()
            if abs(value * Double(q) - n) < 1e-6 { return (Int(n), q) }
        }
        return nil
    }
    static func format(_ number: Double) -> String {
        number == number.rounded() ? String(Int(number)) : String(format: "%g", number)
    }

    /// Puts `token` at `time`: into the cell that already sits there, into a cell split finer, or after the last cell.
    public static func insert(_ token: String, at time: Double, in source: String, chart: ParsedChart) -> ChartEdit? {
        let text = NSMutableString(string: source), length = text.length, tokenLength = (token as NSString).length
        guard !token.isEmpty, let index = chart.timings.lastIndex(where: { $0.time <= time + 1e-6 }) else { return nil }
        let cell = chart.timings[index]
        guard cell.bpm > 0, let step = cell.duration, step > 0, let end = cell.sourceEnd, end <= length, end > 0 else { return nil }
        let terminated = text.character(at: end - 1) == 0x2C // ","
        let contentStart = cell.location.offset
        let empty = contentStart < length && text.character(at: contentStart) == 0x2C && contentStart == end - 1
        if abs(cell.time - time) < 1e-6 {
            if empty { text.insert(token, at: contentStart); return ChartEdit(text: text as String, selection: NSRange(location: contentStart, length: tokenLength)) }
            let at = contentStart + cell.location.length
            text.insert("/" + token, at: at)
            return ChartEdit(text: text as String, selection: NSRange(location: at + 1, length: tokenLength))
        }
        if terminated && time < cell.time + step - 1e-6 {
            // Inside this cell: rewrite it at a finer subdivision, then restore the old one.
            // `{#seconds}` cells have no musical subdivision to refine.
            guard abs(step - 240 / cell.bpm / cell.subdivision) < 1e-9,
                  let part = fraction((time - cell.time) / step, limit: 64), part.n > 0, part.n < part.q else { return nil }
            // Keep the text tidy: no restore when the next cell sets its own subdivision, and the finer
            // subdivision replaces a `{n}` that sits directly in front of this cell instead of stacking on it.
            let nextSets = end < length && text.character(at: end) == 0x7B // "{"
            let tail = String(repeating: ",", count: part.n) + token + String(repeating: ",", count: part.q - part.n)
                + (nextSets ? "" : "{\(format(cell.subdivision))}")
            text.replaceCharacters(in: NSRange(location: end - 1, length: 1), with: tail)
            let finer = "{\(format(cell.subdivision * Double(part.q)))}"
            var replaced = NSRange(location: contentStart, length: 0)
            if contentStart > 0, text.character(at: contentStart - 1) == 0x7D, // "}"
               let open = ((cell.sourceStart ?? 0)..<contentStart).last(where: { text.character(at: $0) == 0x7B }),
               text.substring(with: NSRange(location: open, length: contentStart - open)).range(of: "#") == nil {
                replaced = NSRange(location: open, length: contentStart - open)
            }
            text.replaceCharacters(in: replaced, with: finer)
            let shift = (finer as NSString).length - replaced.length
            return ChartEdit(text: text as String, selection: NSRange(location: end - 1 + shift + part.n, length: tokenLength))
        }
        guard index == chart.timings.count - 1 else { return nil }
        // Past the last cell: pad with empty cells. An unterminated last cell gets its comma first.
        let from = cell.time + step
        guard time >= from - 1e-6 else { return nil }
        var inserted = terminated ? "" : ","
        if let same = fraction((time - from) / step, limit: 1) {
            inserted += String(repeating: ",", count: same.n)
        } else if let whole = fraction((time - from) * cell.bpm / 240, limit: 192) {
            inserted += "{\(whole.q)}" + String(repeating: ",", count: whole.n)
        } else { return nil }
        inserted += token + ","
        text.insert(inserted, at: end)
        return ChartEdit(text: text as String, selection: NSRange(location: end + (inserted as NSString).length - tokenLength - 1, length: tokenLength))
    }

    static let slideShapes = "-^v<>Vpqszw"
    /// Whether the note's token is a slide (its star head shares the token).
    public static func isSlide(_ note: Note, in source: String) -> Bool {
        let text = source as NSString
        guard let token = note.token, token.offset + token.length <= text.length else { return false }
        return text.substring(with: NSRange(location: token.offset, length: token.length)).contains(where: { slideShapes.contains($0) })
    }
    /// Extends a star that already has a tail. `tail` is shape, end key and duration without a start key, e.g. `-3[4:1]`.
    /// Joined with `*` it is a second tail on the same head (`1-5[4:1]*-3[4:1]`); joined with nothing it
    /// continues the last tail as one connected slide (`1-5[4:1]-3[4:1]`).
    public static func addTail(_ tail: String, to slide: Note, in source: String, joiner: String = "*") -> ChartEdit? {
        let text = NSMutableString(string: source)
        guard let token = slide.token, token.offset + token.length <= text.length, !tail.isEmpty,
              text.substring(with: NSRange(location: token.offset, length: token.length)).contains(where: { "-^v<>Vpqszw".contains($0) }) else { return nil }
        let at = token.offset + token.length
        text.insert(joiner + tail, at: at)
        return ChartEdit(text: text as String, selection: NSRange(location: token.offset, length: token.length + ((joiner + tail) as NSString).length))
    }

    /// Break slide: a `b` between each segment's end key and its `[duration]`. All tails of the token change together.
    public static func toggleSlideBreak(on note: Note, in source: String) -> ChartEdit? {
        let text = NSMutableString(string: source)
        guard isSlide(note, in: source), let token = note.token else { return nil }
        let range = NSRange(location: token.offset, length: token.length)
        var body = text.substring(with: range)
        let marked = body.range(of: #"\db\["#, options: .regularExpression) != nil
        body = body.replacingOccurrences(of: marked ? #"(\d)b\["# : #"(\d)\["#, with: marked ? "$1[" : "$1b[", options: .regularExpression)
        text.replaceCharacters(in: range, with: body)
        return ChartEdit(text: text as String, selection: NSRange(location: token.offset, length: (body as NSString).length))
    }

    /// Removes the note's token and the separator that joined it to its neighbour.
    public static func remove(_ note: Note, from source: String) -> ChartEdit? {
        let text = NSMutableString(string: source)
        guard let token = note.token, NSMaxRange(NSRange(location: token.offset, length: token.length)) <= text.length else { return nil }
        var range = NSRange(location: token.offset, length: token.length)
        func separator(_ index: Int) -> Bool { index >= 0 && index < text.length && (text.character(at: index) == 0x2F || text.character(at: index) == 0x60) }
        if separator(NSMaxRange(range)) { range.length += 1 } else if separator(range.location - 1) { range.location -= 1; range.length += 1 }
        text.deleteCharacters(in: range)
        return ChartEdit(text: text as String, selection: NSRange(location: min(range.location, text.length), length: 0))
    }

    /// Adds or removes a head flag such as `b` (break), `x` (EX) or `f` (firework) right after the note's position.
    public static func toggle(_ flag: Character, on note: Note, in source: String) -> ChartEdit? {
        let text = NSMutableString(string: source)
        guard let token = note.token, token.offset + token.length <= text.length else { return nil }
        let characters = Array(text.substring(with: NSRange(location: token.offset, length: token.length)))
        guard let first = characters.first else { return nil }
        var position = 1
        if "ABDE".contains(first) { position = 2 } else if first == "C", characters.count > 1, characters[1] == "1" || characters[1] == "2" { position = 2 }
        guard position <= characters.count else { return nil }
        var end = position
        while end < characters.count, "bxf$@!?".contains(characters[end]) { end += 1 }
        var result = characters
        if let found = characters[position..<end].firstIndex(of: flag) { result.remove(at: found) } else { result.insert(flag, at: position) }
        let replacement = String(result)
        text.replaceCharacters(in: NSRange(location: token.offset, length: token.length), with: replacement)
        return ChartEdit(text: text as String, selection: NSRange(location: token.offset, length: (replacement as NSString).length))
    }
}

/// Turns a stroke drawn across the judgement zones into the simai slide shape that covers the same zones.
public enum SlideMatching {
    static let shapes = ["-", "^", "v", "<", ">", "p", "q", "s", "z", "pp", "qq"]
    /// Zones a slide passes, sampled along its real path.
    public static func zones(shape: String, start: Int, end: Int) -> Set<String> {
        let segment = SlideSegment(shape: shape, start: start, end: end)
        let points = SlideGeometry.points(for: segment)
        guard points.count > 1 else { return [] }
        var ids: Set<Int> = []
        for i in 0...60 {
            let p = SlideGeometry.position(on: points, progress: Double(i) / 60)
            ids.formUnion(SensorGeometry.contacts(at: Point(p.x * 4.8, p.y * 4.8), slide: true, radius: 0.15))
        }
        return Set(SensorGeometry.polygons.filter { ids.contains($0.id) }.map { $0.name.hasPrefix("C") ? "C" : $0.name })
    }
    /// The legal shape from `start` to `end` whose zones overlap the drawn ones best; earlier shapes win ties.
    public static func shape(start: Int, end: Int, drawn: Set<String>) -> String? {
        var best: (shape: String, score: Double)?
        for shape in shapes where SlideGeometry.key(for: SlideSegment(shape: shape, start: start, end: end)) != nil {
            let zones = zones(shape: shape, start: start, end: end)
            guard !zones.isEmpty else { continue }
            let score = Double(zones.intersection(drawn).count) / Double(max(1, zones.union(drawn).count))
            if best == nil || score > best!.score + 1e-9 { best = (shape, score) }
        }
        return best?.shape
    }
}
