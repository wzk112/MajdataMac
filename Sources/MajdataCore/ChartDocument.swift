import Foundation

public struct ChartField: Codable, Equatable, Sendable {
    public var name: String
    public var value: String
}

/// Ordered fields retain extension parameters and all seven charts on save.
public struct ChartDocument: Codable, Equatable, Sendable {
    public var fields: [ChartField] = []
    public var preamble = ""
    public static let difficultyNames = ["EASY", "BASIC", "ADVANCED", "EXPERT", "MASTER", "Re:MASTER", "ORIGINAL"]

    public init(text: String) {
        let clean = text.replacingOccurrences(of: "\u{FEFF}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for line in clean.components(separatedBy: "\n") {
            if line.hasPrefix("&"), let eq = line.firstIndex(of: "=") {
                let name = String(line[line.index(after: line.startIndex)..<eq])
                fields.append(ChartField(name: name, value: String(line[line.index(after: eq)...])))
            } else if !fields.isEmpty {
                fields[fields.count - 1].value += "\n" + line
            } else {
                preamble += line + "\n"
            }
        }
    }

    public subscript(_ key: String) -> String {
        get { fields.last(where: { $0.name == key })?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        set {
            if let i = fields.lastIndex(where: { $0.name == key }) { fields[i].value = newValue }
            else { fields.append(ChartField(name: key, value: newValue)) }
        }
    }
    public var title: String { get { self["title"] } set { self["title"] = newValue.replacingOccurrences(of: "\n", with: " ") } }
    public var artist: String { get { self["artist"] } set { self["artist"] = newValue.replacingOccurrences(of: "\n", with: " ") } }
    public var designer: String { get { self["des"] } set { self["des"] = newValue.replacingOccurrences(of: "\n", with: " ") } }
    public var offset: Double { Double(self["first"]) ?? 0 }
    public func chart(_ difficulty: Int) -> String { self["inote_\(difficulty + 1)"] }
    public mutating func setChart(_ text: String, difficulty: Int) { self["inote_\(difficulty + 1)"] = text }
    public func designer(_ difficulty: Int) -> String { self["des_\(difficulty + 1)"].isEmpty ? designer : self["des_\(difficulty + 1)"] }
    public mutating func setDesigner(_ value: String, difficulty: Int) { self["des_\(difficulty + 1)"] = value }
    public func level(_ difficulty: Int) -> String { self["lv_\(difficulty + 1)"] }
    public var serialized: String {
        let prefix = preamble.trimmingCharacters(in: .newlines)
        return (prefix.isEmpty ? "" : prefix + "\n") + fields.map { "&\($0.name)=\($0.value.trimmingCharacters(in: .newlines))" }.joined(separator: "\n") + "\n"
    }
    public static var blank: ChartDocument { ChartDocument(text: "&title=未命名谱面\n&artist=\n&des=\n&first=0\n&lv_5=\n&inote_5=(120){4}\n,\nE\n") }
}

public struct SourceLocation: Codable, Hashable, Sendable {
    public var offset: Int
    public var length: Int
    public var line: Int
    public var column: Int
    public init(offset: Int = 0, length: Int = 1, line: Int = 1, column: Int = 1) {
        self.offset = offset; self.length = length; self.line = line; self.column = column
    }
}
public struct Diagnostic: Codable, Identifiable, Hashable, Sendable {
    public enum Severity: String, Codable, Sendable { case error, warning }
    public var severity: Severity
    public var message: String
    public var location: SourceLocation
    public var id: String { "\(location.offset)-\(message)" }
    public init(_ message: String, at location: SourceLocation, severity: Severity = .error) {
        self.message = message; self.location = location; self.severity = severity
    }
}
public enum NoteKind: String, Codable, CaseIterable, Sendable { case tap, hold, slide, touch, touchHold }
public struct SlideSegment: Codable, Hashable, Sendable {
    public var shape: String
    public var start: Int
    public var end: Int
    public var turn: Int?
    public var startTime: Double
    public var duration: Double
    public init(shape: String, start: Int, end: Int, turn: Int? = nil, startTime: Double = 0, duration: Double = 0) {
        self.shape = shape; self.start = start; self.end = end; self.turn = turn; self.startTime = startTime; self.duration = duration
    }
}
public struct Note: Codable, Identifiable, Hashable, Sendable {
    public var id: Int
    public var kind: NoteKind
    public var lane: Int
    public var area: String
    public var time: Double
    public var duration: Double
    public var bpm: Double
    public var speed: Double
    public var isBreak: Bool
    public var isEX: Bool
    public var isStar: Bool
    /// 0 = static fake star, 1 = slide head, 2 = rotating $$ fake star.
    public var starSpin: Int = 0
    public var isFirework: Bool
    public var isEach: Bool
    public var segments: [SlideSegment]
    public var location: SourceLocation
    /// Source span of this note's own token inside its cell; `location` covers the whole cell.
    public var token: SourceLocation? = nil
    public var endTime: Double { segments.last.map { $0.startTime + $0.duration } ?? (time + duration) }
    public var judgeTime: Double { kind == .slide || kind == .hold || kind == .touchHold ? endTime : time }
    public var weight: Int { isBreak ? 2500 : (kind == .slide ? 1500 : ((kind == .hold || kind == .touchHold) ? 1000 : 500)) }
    public init(id: Int = 0, kind: NoteKind, lane: Int, area: String = "A", time: Double, duration: Double = 0,
                bpm: Double = 120, speed: Double = 1, isBreak: Bool = false, isEX: Bool = false,
                isStar: Bool = false, isFirework: Bool = false, isEach: Bool = false,
                segments: [SlideSegment] = [], location: SourceLocation = .init()) {
        self.id = id; self.kind = kind; self.lane = lane; self.area = area; self.time = time; self.duration = duration
        self.bpm = bpm; self.speed = speed; self.isBreak = isBreak; self.isEX = isEX; self.isStar = isStar
        self.isFirework = isFirework; self.isEach = isEach; self.segments = segments; self.location = location
    }
}
public struct TimingPoint: Codable, Hashable, Sendable {
    public var time: Double
    public var bpm: Double
    public var subdivision: Double
    public var location: SourceLocation
    public var duration: Double? = nil
    public var sourceStart: Int? = nil
    public var sourceEnd: Int? = nil
}
public struct ParsedChart: Codable, Sendable {
    public private(set) var renderRevision = UUID()
    public var notes: [Note] = [] { didSet { renderRevision = UUID() } }
    public var timings: [TimingPoint] = []
    public var diagnostics: [Diagnostic] = []
    public var endTime: Double = 0
    public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }
    public var duration: Double { max(0, endTime, notes.map(\.endTime).max() ?? 0) }
    public var totalWeight: Int { notes.reduce(0) { $0 + $1.weight } }
    public var breakCount: Int { notes.filter(\.isBreak).count }
    public func count(_ kind: NoteKind) -> Int { notes.filter { $0.kind == kind }.count }
    public init() {}
}
