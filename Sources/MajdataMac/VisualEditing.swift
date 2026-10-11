import AppKit
import MajdataCore

/// A star head waiting for its tail to be drawn on the stage.
struct PendingSlide: Equatable { var lane: Int; var time: Double }
struct VisualSnapshot { var source: String; var selection: NSRange }

/// Mouse editing. Every action becomes a `ChartEdit` on the simai text; nothing else stores notes.
extension StudioModel {
    private static let cannotWrite = "这个位置没法直接写进文本（在第一个音符之前，或这一段用了 {#秒} 固定间隔）。请到代码编辑里改。"
    func range(of note: Note) -> NSRange {
        let span = note.token ?? note.location
        return NSRange(location: span.offset, length: max(1, span.length))
    }
    func isSelected(_ note: Note) -> Bool {
        let range = range(of: note), selection = selectedRange
        return selection.length > 0 ? NSIntersectionRange(range, selection).length > 0 : NSLocationInRange(selection.location, range)
    }
    var selectedNotes: [Note] { chart.notes.filter(isSelected) }
    func select(_ note: Note) { selectedRange = range(of: note) }
    func gridTime(_ time: Double) -> Double { MusicalTimeline(chart).snap(time, divisor: trackDivisor) }
    func gridStep(at time: Double) -> Double { MusicalTimeline(chart).step(at: time, divisor: trackDivisor) }
    /// `[分音:拍数]` used for new slides and touch holds; falls back when the field holds something else.
    var slideLengthToken: String {
        let parts = slideLength.split(separator: ":")
        return parts.count == 2 && parts.allSatisfy({ Int($0).map { $0 > 0 } ?? false }) ? "[\(slideLength)]" : "[4:1]"
    }
    private func flags(_ allowed: String) -> String { String(allowed.filter { placementFlags.contains($0) }) }

    @discardableResult private func commit(_ edit: ChartEdit?, failure: String = StudioModel.cannotWrite) -> Bool {
        guard let edit else { status = failure; NSSound.beep(); return false }
        visualUndo.append(VisualSnapshot(source: source, selection: selectedRange))
        if visualUndo.count > 200 { visualUndo.removeFirst() }
        visualRedo.removeAll()
        apply(edit.text, selection: edit.selection)
        return true
    }
    private func apply(_ text: String, selection: NSRange) {
        edited(text)
        // The next click needs fresh source offsets, so do not wait for the debounced background parse.
        chart = SimaiParser.parse(text, offset: document.offset)
        selectedRange = selection
    }
    /// For edits that go through the older text commands (mirror, rotate, subdivide) so ⌘Z covers them too.
    func undoable(_ change: () -> Void) {
        let before = VisualSnapshot(source: source, selection: selectedRange)
        change()
        guard source != before.source else { return }
        visualUndo.append(before); visualRedo.removeAll()
        chart = SimaiParser.parse(source, offset: document.offset)
    }
    func undoVisualEdit() {
        guard let last = visualUndo.popLast() else { NSSound.beep(); return }
        visualRedo.append(VisualSnapshot(source: source, selection: selectedRange)); apply(last.source, selection: last.selection)
    }
    func redoVisualEdit() {
        guard let next = visualRedo.popLast() else { NSSound.beep(); return }
        visualUndo.append(VisualSnapshot(source: source, selection: selectedRange)); apply(next.source, selection: next.selection)
    }

    /// Track click with a placement tool. `until` is where a Hold drag was released.
    func place(lane: Int, at time: Double, until: Double? = nil) {
        switch trackTool {
        case .tap: commit(ChartEditing.insert("\(lane)\(flags("bx"))", at: time, in: source, chart: chart))
        case .hold:
            let step = gridStep(at: time), count = step > 0 ? max(1, Int((((until ?? time) - time) / step).rounded())) : 1
            commit(ChartEditing.insert("\(lane)\(flags("bx"))h[\(trackDivisor):\(count)]", at: time, in: source, chart: chart))
        case .slide:
            pendingSlide = PendingSlide(lane: lane, time: time)
            status = slideHead(lane: lane, at: time) == nil ? "星星头在键 \(lane)：到右边舞台上按住左键画星星尾，松手确认，Esc 取消"
                : "给键 \(lane) 这颗星星再加一条尾巴：到右边舞台上按住左键画，松手确认，Esc 取消"
        case .touch, .touchHold: status = "Touch 请在右边舞台上点判定区放置（时间取当前播放位置）"
        case .select: break
        }
    }
    /// Stage click with a Touch tool: the zone comes from the stage, the time from the playhead.
    func placeTouch(zone: String) {
        let time = gridTime(isPlaying ? playbackTime : currentTime), firework = flags("f")
        let token = trackTool == .touchHold ? zone + "h" + firework + slideLengthToken : zone + firework
        commit(ChartEditing.insert(token, at: time, in: source, chart: chart))
    }
    /// Stage stroke for the pending star: the zones it crossed choose the shape.
    func finishSlide(zones: Set<String>, end: Int) {
        guard let pending = pendingSlide else { return }
        let fan = placementFlags.contains("w") && (end - pending.lane + 8) % 8 == 4
        guard let shape = fan ? "w" : SlideMatching.shape(start: pending.lane, end: end, drawn: zones) else {
            status = "键 \(pending.lane) 到键 \(end) 没有合法的星星形状"; NSSound.beep(); return
        }
        // A star that is already there gets a second tail on the same head (`*`), which is how overlapping stars are written.
        let edit: ChartEdit?
        if let existing = slideHead(lane: pending.lane, at: pending.time) {
            edit = ChartEditing.addTail("\(shape)\(end)\(slideLengthToken)", to: existing, in: source)
        } else {
            edit = ChartEditing.insert("\(pending.lane)\(flags("bx"))\(shape)\(end)\(slideLengthToken)", at: pending.time, in: source, chart: chart)
        }
        if commit(edit) { pendingSlide = nil }
    }
    /// The slide starting on this key at this instant, if any.
    func slideHead(lane: Int, at time: Double) -> Note? {
        chart.notes.first { $0.kind == .slide && $0.lane == lane && abs($0.time - time) < 1e-6 && $0.token != nil }
    }
    func delete(_ note: Note) { commit(ChartEditing.remove(note, from: source), failure: "这个音符没有独立的源码位置，请到代码编辑里删。") }
    func deleteSelectedNotes() {
        // Back to front, so earlier offsets stay valid; a slide and its star head share one token.
        var text = source, seen: Set<Int> = [], changed = false
        for note in selectedNotes.sorted(by: { range(of: $0).location > range(of: $1).location }) where seen.insert(range(of: note).location).inserted {
            if let edit = ChartEditing.remove(note, from: text) { text = edit.text; changed = true }
        }
        guard changed else { NSSound.beep(); return }
        commit(ChartEdit(text: text, selection: NSRange(location: min(selectedRange.location, (text as NSString).length), length: 0)))
    }
    /// B / X / F: with notes selected the flag is toggled on them, otherwise it arms the next placements.
    func toggleFlag(_ flag: Character) {
        let notes = selectedNotes
        guard !notes.isEmpty else {
            if placementFlags.contains(flag) { placementFlags.remove(flag) } else { placementFlags.insert(flag) }
            return
        }
        var text = source, seen: Set<Int> = [], selection = selectedRange
        for note in notes.sorted(by: { range(of: $0).location > range(of: $1).location }) where seen.insert(range(of: note).location).inserted {
            if flag == "f" && !(note.kind == .touch || note.kind == .touchHold) { continue }
            if let edit = ChartEditing.toggle(flag, on: note, in: text) { selection.length += (edit.text as NSString).length - (text as NSString).length; text = edit.text }
        }
        guard text != source else { NSSound.beep(); return }
        commit(ChartEdit(text: text, selection: NSRange(location: selection.location, length: max(0, selection.length))))
    }
}
