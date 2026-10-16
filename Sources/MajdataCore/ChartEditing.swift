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

    /// Rewrites the `[分音:拍数]` of a hold, touch hold or slide; `duration` comes without brackets, e.g. `8:3`.
    /// A slide keeps its wait prefix (`0##`), and only the first tail segment changes.
    public static func setDuration(_ duration: String, of note: Note, in source: String) -> ChartEdit? {
        let text = NSMutableString(string: source)
        guard let token = note.token, token.offset + token.length <= text.length, !duration.isEmpty else { return nil }
        let range = NSRange(location: token.offset, length: token.length)
        var body = text.substring(with: range)
        if let found = body.range(of: #"\[[^\]]*\]"#, options: .regularExpression) {
            let old = body[found].dropFirst().dropLast()
            let wait = old.range(of: "##").map { String(old[..<$0.upperBound]) } ?? ""
            body.replaceSubrange(found, with: "[" + wait + duration + "]")
        } else if body.contains("h") { body += "[" + duration + "]" } else { return nil }
        text.replaceCharacters(in: range, with: body)
        return ChartEdit(text: text as String, selection: NSRange(location: token.offset, length: (body as NSString).length))
    }

    /// Bare chord digits share a lexical token even when comments or commands sit between them.
    /// Editing one digit must not join its new flags to the neighbouring digit.
    private static func compactNeighbours(of note: Note, in source: String) -> (before: Bool, after: Bool) {
        guard let token = note.token, token.length == 1, note.kind == .tap else { return (false, false) }
        let text = source as NSString
        let notes = SimaiParser.parse(source).notes.filter { $0.kind == .tap && $0.token?.length == 1 }
        func joined(_ other: Note?, before: Bool) -> Bool {
            guard let span = other?.token else { return false }
            let lower = before ? span.offset + span.length : token.offset + token.length
            let upper = before ? token.offset : span.offset
            guard lower <= upper else { return false }
            let gap = text.substring(with: NSRange(location: lower, length: upper - lower))
                .replacingOccurrences(of: #"\|\|[^\n]*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\([^)]*\)|\{[^}]*\}|<HS\*[^>]*>"#, with: "", options: .regularExpression)
            return gap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let previous = notes.filter { $0.token!.offset < token.offset }.max { $0.token!.offset < $1.token!.offset }
        let next = notes.filter { $0.token!.offset > token.offset }.min { $0.token!.offset < $1.token!.offset }
        return (joined(previous, before: true), joined(next, before: false))
    }

    /// Removes a token without changing the millisecond offsets carried by backticks.
    public static func remove(_ note: Note, from source: String) -> ChartEdit? {
        let text = NSMutableString(string: source)
        guard let token = note.token, NSMaxRange(NSRange(location: token.offset, length: token.length)) <= text.length else { return nil }
        var range = NSRange(location: token.offset, length: token.length)
        let neighbours = compactNeighbours(of: note, in: source)
        func separator(_ index: Int) -> Bool { index >= 0 && index < text.length && text.character(at: index) == 0x2F }
        if !neighbours.before && separator(NSMaxRange(range)) { range.length += 1 }
        else if !neighbours.after && separator(range.location - 1) { range.location -= 1; range.length += 1 }
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
        let neighbours = compactNeighbours(of: note, in: source)
        let prefix = neighbours.before ? "/" : "", suffix = neighbours.after ? "/" : ""
        text.replaceCharacters(in: NSRange(location: token.offset, length: token.length), with: prefix + replacement + suffix)
        return ChartEdit(text: text as String, selection: NSRange(location: token.offset + prefix.utf16.count, length: replacement.utf16.count))
    }
}

/// Turns a stroke drawn across the judgement zones into the simai slide shape that covers the same zones.
public enum SlideMatching {
    static let shapes = ["-", "^", "v", "<", ">", "p", "q", "s", "z", "pp", "qq"]
    /// Compare ordered strokes in judgement-ring coordinates (radius 1). Equal arc-length
    /// samples make the result independent of mouse-event frequency while retaining direction
    /// and repeated visits to a region, which a set of sensor names cannot represent.
    public static func shape(start: Int, end: Int, stroke: [Point]) -> String? {
        guard (1...8).contains(start), (1...8).contains(end), let drawn = resample(stroke) else { return nil }
        var best: (shape: String, error: Double)?
        for shape in shapes {
            let segment = SlideSegment(shape: shape, start: start, end: end)
            guard SlideGeometry.key(for: segment) != nil,
                  let path = resample(SlideGeometry.points(for: segment)) else { continue }
            let error = zip(drawn, path).reduce(0.0) { sum, pair in
                let distance = pair.0.distance(to: pair.1)
                return sum + distance * distance
            } / Double(drawn.count)
            if best == nil || error < best!.error - 1e-9 { best = (shape, error) }
        }
        return best?.shape
    }
    private static func resample(_ points: [Point], count: Int = 65) -> [Point]? {
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }), let first = points.first else { return nil }
        var path = [first], lengths = [0.0]
        for point in points.dropFirst() {
            let distance = path.last!.distance(to: point)
            guard distance > 1e-8 else { continue }
            path.append(point); lengths.append(lengths.last! + distance)
        }
        guard path.count > 1, let total = lengths.last, total.isFinite, total > 0.05 else { return nil }
        var index = 1
        return (0..<count).map { sample in
            let distance = total * Double(sample) / Double(count - 1)
            while index < path.count - 1 && lengths[index] < distance { index += 1 }
            let fraction = (distance - lengths[index - 1]) / (lengths[index] - lengths[index - 1])
            return path[index - 1].interpolated(to: path[index], at: fraction)
        }
    }
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
