import Foundation

public enum SimaiParser {
    public static func parse(_ text: String, offset: Double = 0) -> ParsedChart {
        var parser = Parser(text: text, offset: offset)
        return parser.run()
    }
}

private struct Parser {
    let chars: [Character]
    let locations: [SourceLocation]
    var cursor = 0
    var bpm: Double = 0
    var subdivision: Double = 4
    var fixedStep: Double?
    var speed: Double = 1
    var time: Double
    var result = ParsedChart()
    var ended = false
    var cell: [Character] = []
    /// Source index of every character kept in `cell` (whitespace and inline commands are skipped).
    var cellIndices: [Int] = []
    var tokenLocation: SourceLocation?
    var cellStart = 0
    var cellEnd = 0
    var cellSourceStart = 0
    var flushingLocation = SourceLocation()

    init(text: String, offset: Double) {
        chars = Array(text)
        var line = 1, column = 1, utf16Offset = 0
        locations = text.map { character in
            let p = SourceLocation(offset: utf16Offset, length: character.utf16.count, line: line, column: column)
            utf16Offset += character.utf16.count
            if character == "\n" { line += 1; column = 1 } else { column += 1 }
            return p
        }
        time = offset.isFinite ? offset : 0
    }
    func location(_ i: Int) -> SourceLocation { locations.isEmpty ? .init() : locations[min(max(i, 0), locations.count - 1)] }
    mutating func error(_ text: String, _ i: Int? = nil) { result.diagnostics.append(Diagnostic(text, at: location(i ?? cursor))) }

    mutating func run() -> ParsedChart {
        while cursor < chars.count && !ended {
            let c = chars[cursor]
            if c == "|", cursor + 1 < chars.count, chars[cursor + 1] == "|" {
                while cursor < chars.count && chars[cursor] != "\n" { cursor += 1 }; continue
            }
            if c.isWhitespace { cursor += 1; continue }
            if c == "(" || c == "{" {
                let start = cursor
                let value = bracket(open: c, close: c == "(" ? ")" : "}")
                if let value {
                    if c == "{" && value.hasPrefix("#") {
                        if let n = positive(String(value.dropFirst())) { fixedStep = n }
                        else { error("时间间隔必须是大于 0 的有限数值", start) }
                    } else if let n = positive(value) {
                        if c == "(" { bpm = n } else { subdivision = n; fixedStep = nil }
                    } else { error(c == "(" ? "BPM 必须大于 0" : "分音必须大于 0（不能使用 {0}）", start) }
                }
                continue
            }
            if c == "<", String(chars[cursor..<min(chars.count, cursor + 4)]) == "<HS*" {
                let start = cursor; cursor += 4
                var value = ""
                while cursor < chars.count && chars[cursor] != ">" && chars[cursor] != "," { value.append(chars[cursor]); cursor += 1 }
                if cursor < chars.count && chars[cursor] == ">" { cursor += 1 } else { error("HS 指令缺少 >", start) }
                if let n = positive(value) { speed = n } else { error("HS 速度必须大于 0", start) }
                continue
            }
            if c == "," {
                let span = cell.isEmpty ? location(cursor) : cellLocation()
                flush()
                if ended { break }
                result.timings.append(TimingPoint(time: time, bpm: bpm, subdivision: subdivision, location: span,
                    duration: fixedStep ?? (bpm > 0 ? 240 / bpm / subdivision : 0),
                    sourceStart: cellSourceStart, sourceEnd: location(cursor).offset + 1))
                if let fixedStep { time += fixedStep }
                else if bpm > 0 { time += 240 / bpm / subdivision }
                else { error("在音符之前设置 BPM，例如 (120)") }
                if !time.isFinite || abs(time) > 86400 { error("谱面时长超出 24 小时限制"); break }
                cellSourceStart = location(cursor).offset + 1
                cursor += 1; cellStart = cursor; continue
            }
            if cell.isEmpty { cellStart = cursor }
            cell.append(c); cellIndices.append(cursor); cellEnd = cursor; cursor += 1
        }
        if !cell.isEmpty && !ended {
            let span = cellLocation()
            flush()
            if !ended { result.timings.append(TimingPoint(time: time, bpm: bpm, subdivision: subdivision, location: span,
                duration: fixedStep ?? (bpm > 0 ? 240 / bpm / subdivision : 0),
                sourceStart: cellSourceStart, sourceEnd: locations.last.map { $0.offset + $0.length })) }
        }
        result.endTime = time
        result.notes.sort { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }
        // Group by musical instant, never by shared mutable sensor state.
        let groups = Dictionary(grouping: result.notes.filter { $0.kind != .slide }, by: { Int64(($0.time * 1_000_000).rounded()) })
        let slides = Dictionary(grouping: result.notes.filter { $0.kind == .slide }, by: { Int64(($0.time * 1_000_000).rounded()) })
        for i in result.notes.indices {
            let key = Int64((result.notes[i].time * 1_000_000).rounded())
            result.notes[i].isEach = result.notes[i].kind == .slide ? (slides[key]?.count ?? 0) > 1 : (groups[key]?.count ?? 0) > 1
        }
        return result
    }
    mutating func bracket(open: Character, close: Character) -> String? {
        let start = cursor; cursor += 1
        var value = ""
        while cursor < chars.count && chars[cursor] != close {
            if chars[cursor] == "," || chars[cursor] == "\n" { error("\(open) 缺少配对的 \(close)", start); return nil }
            value.append(chars[cursor]); cursor += 1
        }
        guard cursor < chars.count else { error("\(open) 缺少配对的 \(close)", start); return nil }
        cursor += 1; return value
    }
    func cellLocation() -> SourceLocation {
        var span = location(cellStart)
        span.length = max(1, location(cellEnd).offset + location(cellEnd).length - span.offset)
        return span
    }
    mutating func flush() {
        flushingLocation = cellLocation()
        let raw = String(cell), indices = cellIndices
        cell.removeAll(keepingCapacity: true); cellIndices.removeAll(keepingCapacity: true)
        defer { tokenLocation = nil }
        if raw.isEmpty { return }
        if raw == "E" { ended = true; return }
        guard bpm > 0 else { error("缺少 BPM：请先输入 (120) 等速度指令", cellStart); return }
        func span(_ a: Int, _ b: Int) -> SourceLocation {
            var span = location(indices[a]); let last = location(indices[b - 1])
            span.length = max(1, last.offset + last.length - span.offset); return span
        }
        let characters = Array(raw)
        var pseudo = 0, start = 0
        for i in 0...characters.count {
            guard i == characters.count || characters[i] == "/" || characters[i] == "`" else { continue }
            let t = time + Double(pseudo) * 0.001 // Official simai: 1 ms, independent of BPM.
            if i > start {
                let token = String(characters[start..<i])
                if token.count >= 2 && token.allSatisfy({ "12345678".contains($0) }) {
                    for (k, c) in token.enumerated() { tokenLocation = span(start + k, start + k + 1); parseNote(String(c), time: t) }
                } else { tokenLocation = span(start, i); parseNote(token, time: t) }
            }
            if i < characters.count && characters[i] == "`" { pseudo += 1 }
            start = i + 1
        }
    }
    mutating func parseNote(_ token: String, time t: Double) {
        let loc = flushingLocation
        let a = Array(token)
        guard let first = a.first else { return }
        var index = 0, area = "A", lane = 1
        let touch = "ABCDE".contains(first)
        if touch {
            area = String(first); index = 1
            if first == "C" { lane = 1; if index < a.count && a[index] == "1" { index += 1 } }
            else if index < a.count, let n = a[index].wholeNumberValue, (1...8).contains(n) { lane = n; index += 1 }
            else { error("Touch 区域需要 1–8 的位置：\(token)", cellStart); return }
        } else if let n = first.wholeNumberValue, (1...8).contains(n) { lane = n; index = 1 }
        else { error("无法识别音符：\(token)", cellStart); return }
        let tail = String(a.dropFirst(index))
        let shapes = "-^v<>Vpqszw"
        let isSlide = tail.contains(where: { shapes.contains($0) })
        func make(_ kind: NoteKind, duration: Double = 0, flags: String = "") -> Note {
            var note = Note(kind: kind, lane: lane, area: area, time: t, duration: duration, bpm: bpm, speed: speed,
                 isBreak: flags.contains("b"), isEX: flags.contains("x"), isStar: flags.contains("$"),
                 isFirework: flags.contains("f"), location: loc)
            note.starSpin = flags.contains("$$") ? 2 : 0
            note.token = tokenLocation
            return note
        }
        if !isSlide {
            let durationStrings = token.matches(#"\[([^\]]*)\]"#).map { $0[1] }
            var flags = tail.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            let hold = flags.contains("h"); flags = flags.replacingOccurrences(of: "h", with: "")
            guard flags.allSatisfy({ "bxf$@!?".contains($0) }), durationStrings.count <= 1 else {
                error("音符后存在无法识别的字符或重复时长：\(token)", cellStart); return
            }
            var length = 0.0
            if hold, let rawDuration = durationStrings.first {
                guard let d = duration(rawDuration) else { return }; length = d.length
            } else if !hold && !durationStrings.isEmpty { error("只有 Hold 或 Slide 可以指定时长", cellStart); return }
            append(make(touch ? (hold ? .touchHold : .touch) : (hold ? .hold : .tap), duration: length, flags: flags))
            return
        }
        if touch { error("Touch 不能作为 Slide 起点", cellStart); return }
        let branches = tail.components(separatedBy: "*")
        guard let firstShape = tail.firstIndex(where: { shapes.contains($0) }) else { return }
        let headFlags = String(tail[..<firstShape])
        guard headFlags.allSatisfy({ "bxf$@!?".contains($0) }) else { error("Slide 头部标记错误：\(token)", cellStart); return }
        let headless = headFlags.contains("!") || headFlags.contains("?")
        var parsedSlides: [Note] = []
        for (branchIndex, branch) in branches.enumerated() {
            var part = Array(branchIndex == 0 ? String(branch.dropFirst(headFlags.count)) : branch)
            // A branch may optionally repeat its starting lane.
            if part.first?.wholeNumberValue == lane { part.removeFirst() }
            var p = 0, start = lane
            var segments: [SlideSegment] = []
            var times: [(wait: Double, length: Double)?] = []
            var slideBreak = false
            while p < part.count {
                if "bx!?@".contains(part[p]) { if part[p] == "b" { slideBreak = true }; p += 1; continue }
                guard shapes.contains(part[p]) else { error("Slide 轨迹无法识别：\(token)", cellStart); return }
                var shape = String(part[p]); p += 1
                if p < part.count && (shape == "p" || shape == "q") && String(part[p]) == shape { shape += shape; p += 1 }
                var turn: Int?
                if shape == "V" {
                    guard p < part.count, let n = part[p].wholeNumberValue, (1...8).contains(n) else { error("V 缺少拐点", cellStart); return }
                    turn = n; p += 1
                }
                guard p < part.count, let end = part[p].wholeNumberValue, (1...8).contains(end) else { error("Slide 缺少合法终点：\(token)", cellStart); return }
                p += 1
                while p < part.count && "bx".contains(part[p]) { if part[p] == "b" { slideBreak = true }; p += 1 }
                var d: (wait: Double, length: Double)?
                if p < part.count && part[p] == "[" {
                    p += 1; var content = ""
                    while p < part.count && part[p] != "]" { content.append(part[p]); p += 1 }
                    guard p < part.count else { error("Slide 时长缺少 ]", cellStart); return }; p += 1
                    guard let parsed = duration(content) else { return }; d = parsed
                }
                let segment = SlideSegment(shape: shape, start: start, end: end, turn: turn)
                guard SlideGeometry.key(for: segment) != nil else { error("不合法的 Slide 路径：\(start)\(shape)\(turn.map(String.init) ?? "")\(end)", cellStart); return }
                segments.append(segment); times.append(d); start = end
            }
            guard !segments.isEmpty, let last = times.last, let finalDuration = last else { error("Slide 需要 [分音:拍数] 时长", cellStart); return }
            if segments.count > 1 && segments.contains(where: { $0.shape == "w" }) { error("Wifi 不能用于组合 Slide", cellStart); return }
            let allTimed = times.allSatisfy { $0 != nil }
            let onlyFinal = times.dropLast().allSatisfy { $0 == nil }
            guard allTimed || onlyFinal else { error("组合 Slide 必须统一使用总时长或逐段时长", cellStart); return }
            let wait = allTimed ? times[0]!.wait : finalDuration.wait
            var segmentTime = t + wait
            let lengths = segments.map { Double(SlideGeometry.barCount(for: $0) + 1) }
            let total = lengths.reduce(0, +)
            for i in segments.indices {
                let length = allTimed ? times[i]!.length : finalDuration.length * lengths[i] / total
                segments[i].startTime = segmentTime; segments[i].duration = length; segmentTime += length
            }
            var note = make(.slide, flags: slideBreak ? "b" : "")
            note.segments = segments; note.duration = segmentTime - t
            parsedSlides.append(note)
        }
        if !headless { var head = make(.tap, flags: headFlags); head.isStar = !headFlags.contains("@"); head.starSpin = 1; append(head) }
        for note in parsedSlides { append(note) }
    }
    mutating func append(_ note: Note) {
        guard note.time.isFinite && note.endTime.isFinite && abs(note.endTime) <= 86400 else { error("音符时长超出限制", cellStart); return }
        var note = note; note.id = result.notes.count; result.notes.append(note)
    }
    func positive(_ text: String) -> Double? {
        guard let n = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), n.isFinite, n > 0, n <= 1_000_000 else { return nil }
        return n
    }
    mutating func duration(_ text: String) -> (wait: Double, length: Double)? {
        var value = text, wait = 60 / bpm, durationBPM = bpm
        if let split = value.range(of: "##") {
            guard let w = Double(value[..<split.lowerBound]), w.isFinite, w >= 0 else { error("Slide 等待时间无效", cellStart); return nil }
            wait = w; value = String(value[split.upperBound...])
        }
        if value.contains("#") {
            let pieces = value.components(separatedBy: "#")
            guard pieces.count == 2 else { error("时长中的 # 格式错误", cellStart); return nil }
            if !pieces[0].isEmpty {
                guard let n = positive(pieces[0]) else { error("时长 BPM 必须大于 0", cellStart); return nil }
                durationBPM = n
                if !text.contains("##") { wait = 60 / n }
            }
            value = pieces[1]
        }
        let length: Double
        if value.contains(":") {
            let pieces = value.components(separatedBy: ":")
            guard pieces.count == 2, let denominator = positive(pieces[0]), let count = Double(pieces[1]), count.isFinite, count >= 0 else { error("时长应为 [正分音:非负拍数]", cellStart); return nil }
            length = 240 / durationBPM / denominator * count
        } else if let seconds = Double(value), seconds.isFinite, seconds >= 0, text.contains("#") { length = seconds }
        else { error("无法识别时长 [\(text)]", cellStart); return nil }
        guard length.isFinite && length <= 86400 && wait <= 86400 else { error("时长超出限制", cellStart); return nil }
        return (wait, length)
    }
}

extension String {
    public func matches(_ pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = self as NSString
        return regex.matches(in: self, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { i in match.range(at: i).location == NSNotFound ? "" : ns.substring(with: match.range(at: i)) }
        }
    }
}
