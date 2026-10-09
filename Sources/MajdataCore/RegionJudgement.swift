import Foundation

/// MajdataView-compatible grades. Separate perfect/great subdivisions retain DX/break scoring.
public enum JudgeGrade: Int, Codable, Sendable, CaseIterable {
    case critical, perfect1, perfect2, great1, great2, great3, good, miss
    public var title: String { switch self { case .critical: "CRITICAL PERFECT"; case .perfect1, .perfect2: "PERFECT"; case .great1, .great2, .great3: "GREAT"; case .good: "GOOD"; case .miss: "MISS" } }
    public var dx: Int { switch self { case .critical: 3; case .perfect1, .perfect2: 2; case .great1, .great2, .great3: 1; default: 0 } }
    public var factor: Double { switch self { case .critical, .perfect1, .perfect2: 1; case .great1, .great2, .great3: 0.8; case .good: 0.5; case .miss: 0 } }
}
public struct JudgeResult: Sendable, Equatable {
    public var noteID: Int
    public var time: Double
    public var grade: JudgeGrade
    /// Negative is FAST, positive is LATE.
    public var difference: Double
    public var coverage: Double = 1
}
public enum AutomaticInputMode: String, CaseIterable, Sendable {
    case touchscreen, outerButtons, mixed
    public var title: String { switch self { case .touchscreen: "全内屏"; case .outerButtons: "Tap/Hold 全外键"; case .mixed: "内外配合" } }
}
public struct SensorFrame: Sendable, Equatable {
    public var time: Double
    public var sensors: Set<Int>
    /// Outer buttons are independent from A sensors and cannot hit Touch notes.
    public var buttons: Set<Int>
    public init(time: Double, sensors: Set<Int> = [], buttons: Set<Int> = []) {
        self.time = time; self.sensors = sensors; self.buttons = buttons
    }
}
public struct SlideAreaStep: Sendable, Equatable {
    public var sensors: Set<Int>
    public var canSkip: Bool = true
    public var isLast: Bool = false
    public var hiddenBars: Int = 0
    public init(_ sensors: Set<Int>, canSkip: Bool = true, isLast: Bool = false, hiddenBars: Int = 0) {
        self.sensors = sensors; self.canSkip = canSkip; self.isLast = isLast; self.hiddenBars = hiddenBars
    }
}
/// Source JudgeArea keeps ON/OFF independently for each alternative; it does not
/// allow ON(A) + OFF(B) to complete an OR step.
public struct SlideAreaQueue: Sendable {
    public var steps: [SlideAreaStep]
    public private(set) var index = 0
    public private(set) var hiddenBars = 0
    private var on: [Set<Int>]
    private var off: [Set<Int>]
    public var finished: Bool { index >= steps.count }
    public var pendingLast: Bool { index >= steps.count - 1 }
    public init(_ steps: [SlideAreaStep]) { self.steps = steps; on = steps.map { _ in [] }; off = on }
    private mutating func observe(_ i: Int, _ sensors: Set<Int>) {
        on[i].formUnion(steps[i].sensors.intersection(sensors))
        off[i].formUnion(on[i].subtracting(sensors))
    }
    private func complete(_ i: Int) -> Bool { steps[i].isLast ? !on[i].isEmpty : !on[i].intersection(off[i]).isEmpty }
    public mutating func update(_ sensors: Set<Int>) {
        guard !finished else { return }
        observe(index, sensors)
        if index + 1 < steps.count, steps[index].canSkip || !on[index].isEmpty {
            observe(index + 1, sensors)
            if complete(index + 1) {
                hiddenBars = max(hiddenBars, steps[index + 1].hiddenBars); index += 2; return
            }
            if !on[index + 1].isEmpty { hiddenBars = max(hiddenBars, steps[index].hiddenBars); index += 1; return }
        }
        if complete(index) { hiddenBars = max(hiddenBars, steps[index].hiddenBars); index += 1 }
    }
    public mutating func forceFinish() { index = steps.count; hiddenBars = steps.last?.hiddenBars ?? 0 }
}

public struct SlideJudgePlan: Sendable {
    private static let areaSteps: [String: [Int]] = {
        guard let url = Bundle.module.url(forResource: "slide-area-steps", withExtension: "json"), let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode([String: [Int]].self, from: data) else { return [:] }
        return value
    }()
    public var queues: [[SlideAreaStep]]
    public var targetTime: Double
    public var endTime: Double
    public init(segment: SlideSegment, connected: Bool = false, final: Bool = true) {
        let key = SlideGeometry.key(for: segment)?.name ?? ""
        endTime = segment.startTime + segment.duration
        if segment.shape == "w" {
            func id(_ group: Int, _ lane: Int) -> Int { group + (lane + segment.start - 2 + 8) % 8 }
            queues = [
                [[id(0, 1)], [id(8, 8)], [id(8, 7)], [id(0, 6), id(17, 6)]],
                [[id(0, 1)], [id(8, 1)], [16], [id(0, 5), id(8, 5)]],
                [[id(0, 1)], [id(8, 2)], [id(8, 3)], [id(0, 4), id(17, 5)]]]
                .map { branch in branch.enumerated().map { i, ids in SlideAreaStep(Set(ids), isLast: i == 3 && final, hiddenBars: [0, 1, 4, 6][i]) } }
        } else {
            // The original queue is derived from bar centres and A/B/C circles.
            // This legacy queue definition is separate from the new polygon input hit-test.
            let bars = SlideGeometry.points(for: segment).dropFirst().dropLast()
            var ids: [Int] = []
            for p in bars {
                if let sensor = SensorGeometry.regions.first(where: { $0.id <= 16 && $0.contains(Point(p.x * 4.8, p.y * 4.8)) }), ids.last != sensor.id { ids.append(sensor.id) }
            }
            let count = SlideGeometry.barCount(for: segment)
            let steps = Array((Self.areaSteps[key] ?? []).dropFirst())
            queues = [ids.enumerated().map { i, id in SlideAreaStep([id], isLast: i == ids.count - 1 && final,
                hiddenBars: steps.count == ids.count ? steps[i] : (count / max(1, ids.count)) * (i + 1)) }]
            if ["line3", "line7", "circle3"].contains(key) || key.hasPrefix("L"), queues[0].count > 1 {
                queues[0][1].canSkip = connected
                if key != "circle3", ids[1] < 8 { queues[0][1].sensors.insert(ids[1] + 8) }
            }
            if key == "L5", queues[0].count > 3 {
                queues[0][3].canSkip = connected
                if ids[3] < 8 { queues[0][3].sensors.insert(ids[3] + 8) }
            }
        }
        // Source-compatible 0.85...0.99 last-zone timing search, not the track endpoint.
        let path = SlideGeometry.points(for: segment)
        let last = queues.count > 1 ? queues[1].last?.sensors : queues.first?.last?.sensors
        var progress = 0.9
        if let last {
            for step in 85..<100 {
                let p = SlideGeometry.position(on: path, progress: Double(step) / 100)
                if SensorGeometry.regions.contains(where: { last.contains($0.id) && $0.contains(Point(p.x * 4.8, p.y * 4.8), contactRadius: SensorGeometry.starRadius) }) {
                    progress = Double(step) / 100; break
                }
            }
        }
        if segment.shape == "w" { progress = (11 - 2.1) / 11 }
        targetTime = segment.startTime + segment.duration * progress
    }
    public func grade(at time: Double) -> JudgeGrade {
        let extra = min(max(0, endTime - targetTime) / 4, 0.733333)
        let perfect = min(0.4666667 + extra, 1.2) / 2
        let great = max(0.4 - extra, 0) / 2
        let diff = abs(time - targetTime)
        return diff < perfect ? .critical : (diff < perfect + great && diff < 0.6 ? .great1 : .good)
    }
}
public struct SlideProgress: Sendable, Equatable {
    public var time: Double
    public var hiddenBars: [[Int]]
}

/// Consumes timestamped sensor states. No result is produced merely because a note
/// reaches its scheduled hit time. Call once for every state change and at deadlines.
public struct RegionJudgeEngine: Sendable {
    public let notes: [Note]
    public private(set) var results: [Int: JudgeResult] = [:]
    public private(set) var headResults: [Int: JudgeResult] = [:]
    public private(set) var progress: [Int: [SlideProgress]] = [:]
    private var plans: [Int: [SlideJudgePlan]] = [:]
    private var queues: [Int: [[SlideAreaQueue]]] = [:]
    private var held: [Int: Double] = [:]
    private var groups: [[Int]] = []
    private var frame = SensorFrame(time: -.infinity)
    private var active: [Int] = []
    private var next = 0
    public init(chart: ParsedChart) {
        notes = chart.notes.sorted { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }
        for note in notes where note.kind == .slide {
            let items = note.segments.enumerated().map { SlideJudgePlan(segment: $0.element, connected: note.segments.count > 1, final: $0.offset == note.segments.count - 1) }
            plans[note.id] = items; queues[note.id] = items.map { $0.queues.map(SlideAreaQueue.init) }
        }
        for touches in Dictionary(grouping: notes.filter { $0.kind == .touch }, by: { Int64(($0.time * 1_000_000).rounded()) }).values {
            var remaining = touches
            while let first = remaining.popLast() {
                var component = [first], changed = true
                while changed {
                    changed = false
                    for i in remaining.indices.reversed() where component.contains(where: { Self.adjacent(Self.sensor($0), Self.sensor(remaining[i])) }) {
                        component.append(remaining.remove(at: i)); changed = true
                    }
                }
                if component.count > 1 { groups.append(component.map(\.id)) }
            }
        }
    }
    public static func sensor(_ note: Note) -> Int {
        switch note.area { case "B": 8 + note.lane - 1; case "C": 16; case "D": 17 + note.lane - 1; case "E": 25 + note.lane - 1; default: note.lane - 1 }
    }
    private static func adjacent(_ a: Int, _ b: Int) -> Bool {
        func neighbours(_ id: Int) -> Set<Int> {
            func wrap(_ n: Int) -> Int { (n + 8) % 8 }
            if id < 8 { return [17 + id, 17 + wrap(id + 1), 25 + id, 25 + wrap(id + 1)] }
            if id < 16 { let n = id - 8; return [25 + n, 25 + wrap(n + 1), 8 + wrap(n - 1), 8 + wrap(n + 1), n, 16] }
            if id == 16 { return Set(8..<16) }
            if id < 25 { let n = id - 17; return [n, wrap(n - 1), 25 + n] }
            let n = id - 25; return [17 + n, n, wrap(n - 1), 8 + n, 8 + wrap(n - 1)]
        }
        return neighbours(a).contains(b) || neighbours(b).contains(a)
    }
    public static func headGrade(_ note: Note, difference: Double) -> JudgeGrade? {
        let d = abs(difference), touch = note.kind == .touch || note.kind == .touchHold
        guard difference >= -0.15 - 1e-9 else { return nil }
        if touch {
            return d < 0.15 ? .critical : (d < 0.2 ? .perfect2 : (d < 0.25 ? .great1 : (d < 0.316667 ? .good : .miss)))
        }
        let grade: JudgeGrade = d < 1.0 / 60 ? .critical : (d < 2.0 / 60 ? .perfect1 : (d < 0.05 ? .perfect2 : (d < 4.0 / 60 ? .great1 : (d < 5.0 / 60 ? .great2 : (d < 0.1 ? .great3 : (d < 0.15 ? .good : .miss))))))
        return note.isEX && grade != .miss ? .critical : grade
    }
    private func pressed(_ note: Note, _ input: SensorFrame) -> Bool {
        input.sensors.contains(Self.sensor(note)) || ((note.kind == .tap || note.kind == .hold) && input.buttons.contains(note.lane))
    }
    public mutating func update(_ input: SensorFrame) {
        guard input.time.isFinite, input.time >= frame.time else { return }
        while next < notes.count, notes[next].time - 0.15 <= input.time + 1e-9 { active.append(next); next += 1 }
        // Integrate previous state over the interval: late rendering never loses hold coverage.
        for i in active where notes[i].kind == .hold || notes[i].kind == .touchHold {
            let note = notes[i], start = note.time + (note.kind == .hold ? 0.1 : 0.25) + max(0, headResults[note.id]?.difference ?? 0)
            let dt = max(0, min(input.time, note.endTime - 0.2) - max(frame.time, start))
            if pressed(note, frame) { held[note.id, default: 0] += dt }
        }
        // A click can be consumed by only the earliest eligible note on that input.
        // Upstream InputManager checks buttons before touch input in the same update.
        let downs = input.buttons.subtracting(frame.buttons).sorted().map { ($0 - 1, true) } + input.sensors.subtracting(frame.sensors).sorted().map { ($0, false) }
        for (sensor, button) in downs {
            for i in active {
                let note = notes[i]
                guard note.kind != .slide, results[note.id] == nil, headResults[note.id] == nil, Self.sensor(note) == sensor,
                      !button || note.kind == .tap || note.kind == .hold,
                      let grade = Self.headGrade(note, difference: input.time - note.time), grade != .miss else { continue }
                let result = JudgeResult(noteID: note.id, time: input.time, grade: grade, difference: input.time - note.time)
                headResults[note.id] = result
                if note.kind == .tap || note.kind == .touch { results[note.id] = result }
                break
            }
        }
        for group in groups {
            let done = group.compactMap { results[$0] }.filter { $0.grade != .miss }
            if done.count * 2 > group.count, let last = done.max(by: { $0.time < $1.time }) {
                for id in group where results[id] == nil {
                    results[id] = JudgeResult(noteID: id, time: input.time, grade: last.grade, difference: last.difference)
                    headResults[id] = results[id]
                }
            }
        }
        for i in active {
            let note = notes[i]
            guard results[note.id] == nil else { continue }
            switch note.kind {
            case .slide:
                guard input.time >= note.time - 0.05, var state = queues[note.id], let plan = plans[note.id] else { continue }
                for s in state.indices {
                    if s > 0 && !state[s - 1].allSatisfy({ $0.pendingLast }) { break }
                    for b in state[s].indices { state[s][b].update(input.sensors) }
                    if s > 0, state[s].contains(where: { $0.index > 0 }) {
                        for b in state[s - 1].indices { state[s - 1][b].forceFinish() }
                    }
                }
                let hidden = state.enumerated().map { s, branches in
                    if note.segments[s].shape == "w" { return branches.map { [1, 2, 5, 7, 11][min(4, $0.index)] } }
                    return branches.map(\.hiddenBars)
                }
                if progress[note.id]?.last?.hiddenBars != hidden { progress[note.id, default: []].append(SlideProgress(time: input.time, hiddenBars: hidden)) }
                queues[note.id] = state
                if state.allSatisfy({ $0.allSatisfy(\.finished) }), let last = plan.last {
                    results[note.id] = JudgeResult(noteID: note.id, time: input.time, grade: last.grade(at: input.time), difference: input.time - last.targetTime)
                } else if input.time >= note.endTime + 0.6 {
                    let almost = state.last?.allSatisfy(\.pendingLast) ?? false
                    results[note.id] = JudgeResult(noteID: note.id, time: note.endTime + 0.6, grade: almost ? .good : .miss, difference: 0.6)
                }
            case .hold, .touchHold:
                if input.time >= note.endTime { finishHold(note) }
            case .tap, .touch:
                let deadline = note.time + (note.kind == .touch ? 0.316667 : 0.15)
                if input.time >= deadline { results[note.id] = JudgeResult(noteID: note.id, time: deadline, grade: .miss, difference: deadline - note.time) }
            }
        }
        active.removeAll { results[notes[$0].id] != nil }; frame = input
    }
    private mutating func finishHold(_ note: Note) {
        let head = headResults[note.id] ?? JudgeResult(noteID: note.id, time: note.time, grade: .miss, difference: 0)
        let duration = note.duration - (note.kind == .hold ? 0.3 : 0.45) - max(0, head.difference)
        let coverage = duration > 1e-8 ? min(1, max(0, (held[note.id] ?? 0) / duration)) : 1
        var grade = head.grade
        if duration > 1e-8 {
            if coverage >= 0.67 {
                if grade == .miss { grade = .good }
                else if grade == .good { grade = .great1 }
                else if coverage < 1 - 1e-8 && grade == .critical { grade = .perfect1 }
            } else if coverage >= 0.33 { grade = grade.rawValue >= JudgeGrade.good.rawValue ? .good : .great1 }
            else { grade = grade == .miss && coverage < 0.05 ? .miss : .good }
        }
        results[note.id] = JudgeResult(noteID: note.id, time: note.endTime, grade: grade, difference: head.difference, coverage: coverage)
    }
}

public struct RegionScore: Sendable {
    public var time: Double = -.infinity
    public var combo = 0
    public var dx = 0
    public var achievement = 0.0
    public var judged = 0
}
public struct SensorPress: Sendable {
    public var time: Double
    public var sensor: Int
    /// Automatic contacts contributing to this OFF -> ON edge.
    public var noteIDs: Set<Int>
    public var isButton: Bool = false
}
struct AutomaticContact: Sendable {
    var noteID: Int
    var start: Double
    var end: Double
    var sensor: Int?
    var paths: [[Point]]
    var button: Int? = nil
    func sensors(at time: Double) -> Set<Int> {
        guard time >= start - 1e-9, time < end - 1e-9 else { return [] }
        if button != nil { return [] }
        if let sensor { return [sensor] }
        return paths.reduce(into: Set<Int>()) { sensors, path in
            let p = SlideGeometry.position(on: path, progress: (time - start) / max(0.001, end - start))
            sensors.formUnion(SensorGeometry.contacts(at: Point(p.x * 4.8, p.y * 4.8)))
        }
    }
}
public struct RegionRecording: Sendable {
    public let revision = UUID()
    public let scores: [RegionScore]
    public func score(at time: Double) -> RegionScore { Self.last(scores, at: time, key: \.time) ?? RegionScore() }
    private init(chart: ParsedChart, engine: RegionJudgeEngine, frames: [SensorFrame], presses: [SensorPress], contacts: [AutomaticContact]) {
        results = engine.results; heads = engine.headResults; progress = engine.progress; self.frames = frames
        self.presses = presses; self.contacts = contacts
        pressesBySensor = Dictionary(grouping: presses.filter { !$0.isButton }, by: \.sensor)
        pressesByButton = Dictionary(grouping: presses.filter(\.isButton), by: \.sensor)
        let notes = Dictionary(uniqueKeysWithValues: chart.notes.map { ($0.id, $0) })
        let total = Double(max(1, chart.totalWeight)), breaks = Double(max(1, chart.breakCount))
        var score = RegionScore(), list: [RegionScore] = []
        for result in engine.results.values.sorted(by: { $0.time == $1.time ? $0.noteID < $1.noteID : $0.time < $1.time }) {
            guard let note = notes[result.noteID] else { continue }
            score.time = result.time; score.combo = result.grade == .miss ? 0 : score.combo + 1
            score.dx += result.grade.dx; score.judged += 1
            let weights: [Double] = [2500, 2500, 2500, 2000, 1500, 1250, 1000, 0]
            let extras: [Double] = [1, 0.75, 0.5, 0.4, 0.4, 0.4, 0.3, 0]
            score.achievement += (note.isBreak ? weights[result.grade.rawValue] : Double(note.weight) * result.grade.factor) / total * 100
            if note.isBreak { score.achievement += extras[result.grade.rawValue] / breaks }
            list.append(score)
        }
        scores = list
    }
    public let results: [Int: JudgeResult]
    public let heads: [Int: JudgeResult]
    public let progress: [Int: [SlideProgress]]
    public let frames: [SensorFrame]
    public let presses: [SensorPress]
    private let pressesBySensor: [Int: [SensorPress]]
    private let contacts: [AutomaticContact]
    private let pressesByButton: [Int: [SensorPress]]
    public func highlightedButtons(at time: Double) -> Set<Int> {
        var active = Self.last(frames, at: time, key: \.time)?.buttons ?? []
        for (button, events) in pressesByButton {
            if let press = Self.last(events, at: time, key: \.time), time - press.time < 0.08 { active.insert(button) }
        }
        return active
    }
    public func sensors(at time: Double) -> Set<Int> { Self.last(frames, at: time, key: \.time)?.sensors ?? [] }
    /// Presentation only: never feed this state into judging, scoring or analysis.
    public func highlightedSensors(at time: Double, persistence: Double = 0.08) -> Set<Int> {
        var active = sensors(at: time)
        for (sensor, events) in pressesBySensor {
            if let press = Self.last(events, at: time, key: \.time), time - press.time < max(0, persistence) { active.insert(sensor) }
        }
        return active
    }
    public func lastPress(sensor: Int, at time: Double) -> SensorPress? {
        Self.last(pressesBySensor[sensor] ?? [], at: time, key: \.time)
    }
    func contactOwners(sensor: Int, at time: Double) -> Set<Int> {
        Set(contacts.lazy.filter { $0.start <= time && $0.end > time && $0.sensors(at: time).contains(sensor) }.map(\.noteID))
    }
    public func hiddenBars(note: Int, segment: Int, at time: Double) -> Int {
        guard let item = Self.last(progress[note] ?? [], at: time, key: \.time), segment < item.hiddenBars.count else { return 0 }
        return item.hiddenBars[segment].min() ?? 0
    }
    private static func last<T>(_ values: [T], at time: Double, key: KeyPath<T, Double>) -> T? {
        var lo = 0, hi = values.count
        while lo < hi { let mid = (lo + hi) / 2; if values[mid][keyPath: key] <= time { lo = mid + 1 } else { hi = mid } }
        return lo > 0 ? values[lo - 1] : nil
    }
    /// Deterministic DJ simulation. Inputs are sampled at 240 Hz plus exact head/release
    /// timestamps; display rate, export frame rate and seeking cannot change the result.
    public static func simulate(_ chart: ParsedChart, inputMode: AutomaticInputMode = .touchscreen) throws -> RegionRecording {
        let start = min(-1, (chart.notes.first?.time ?? 0) - 0.2), end = chart.duration + 0.7
        guard end - start <= 1800 else { throw CocoaError(.fileReadTooLarge) }
        // A local routing alternative, not a hand-count or playability solver.
        // Move a conflicting Tap/Hold to its independent button to leave A Touch free.
        let touches = chart.notes.filter { ($0.kind == .touch || $0.kind == .touchHold) && $0.area == "A" }
        let mixedButtons = Set(chart.notes.filter { note in
            (note.kind == .tap || note.kind == .hold) && touches.contains { touch in
                touch.lane == note.lane && touch.time >= note.time - 1e-8 && touch.time < max(note.time + 0.0001, note.endTime) - 1e-9
            }
        }.map(\.id))
        var contacts: [AutomaticContact] = []
        var exact: [Double] = [start, end]
        for note in chart.notes {
            if note.kind == .slide {
                for segment in note.segments {
                    let paths = (segment.shape == "w" ? [-1, 0, 1] : [0]).map { SlideGeometry.points(for: segment, branch: $0) }
                    contacts.append(AutomaticContact(noteID: note.id, start: segment.startTime, end: segment.startTime + segment.duration, paths: paths))
                }
            } else {
                contacts.append(AutomaticContact(noteID: note.id, start: note.time, end: max(note.time + 0.0001, note.endTime), sensor: RegionJudgeEngine.sensor(note), paths: [],
                    button: (inputMode == .outerButtons && (note.kind == .tap || note.kind == .hold)) || (inputMode == .mixed && mixedButtons.contains(note.id)) ? note.lane : nil))
            }
        }
        contacts.sort { $0.start < $1.start }
        for c in contacts { exact.append(c.start); exact.append(c.end) }
        exact += stride(from: start, through: end, by: 1.0 / 240)
        exact.sort()
        var engine = RegionJudgeEngine(chart: chart), frames: [SensorFrame] = [], active: [Int] = [], next = 0
        var presses: [SensorPress] = []
        var previous = -Double.infinity
        for (step, time) in exact.enumerated() {
            if step % 1024 == 0 { try Task.checkCancellation() }
            if time - previous < 1e-8 { continue }; previous = time
            while next < contacts.count, contacts[next].start <= time + 1e-9 { active.append(next); next += 1 }
            active.removeAll { contacts[$0].end <= time + 1e-9 }
            var sensors: Set<Int> = [], owners: [Int: Set<Int>] = [:]
            var buttons: Set<Int> = [], buttonOwners: [Int: Set<Int>] = [:]
            for i in active {
                let c = contacts[i]
                if let button = c.button { buttons.insert(button); buttonOwners[button, default: []].insert(c.noteID) }
                let touched = c.sensors(at: time)
                sensors.formUnion(touched)
                for sensor in touched { owners[sensor, default: []].insert(c.noteID) }
            }
            for sensor in sensors.subtracting(frames.last?.sensors ?? []).sorted() {
                presses.append(SensorPress(time: time, sensor: sensor, noteIDs: owners[sensor] ?? []))
            }
            for button in buttons.subtracting(frames.last?.buttons ?? []).sorted() {
                presses.append(SensorPress(time: time, sensor: button, noteIDs: buttonOwners[button] ?? [], isButton: true))
            }
            let frame = SensorFrame(time: time, sensors: sensors, buttons: buttons)
            if frames.last?.sensors != sensors || frames.last?.buttons != buttons { frames.append(frame) }
            engine.update(frame)
        }
        return RegionRecording(chart: chart, engine: engine, frames: frames, presses: presses, contacts: contacts)
    }
}
