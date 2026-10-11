import Testing
import AppKit
import MajdataCore
@testable import MajdataMac

@Suite(.serialized) struct VerticalTrackTests {
    private func layout(start: Double = 0, span: Double = 4) -> VerticalTrackLayout {
        // 8 lanes of 40 pt: 34 + 320 + 46 + 46.
        VerticalTrackLayout(size: CGSize(width: 446, height: 400), viewport: TimelineViewport(lower: 0, upper: 16, zoom: 16 / span, start: start))
    }
    @Test func keyEightIsOnTheLeftAndTimeRunsUpward() {
        let layout = layout()
        #expect(layout.laneWidth == 40)
        #expect(layout.x(lane: 8) == 54 && layout.x(lane: 1) == 334)
        #expect(layout.lane(atX: 40) == 8 && layout.lane(atX: 350) == 1)
        #expect(layout.lane(atX: 10) == nil && layout.lane(atX: 380) == nil)
        #expect(layout.y(0) == 400 && layout.y(4) == 0 && layout.y(1) == 300)
        #expect(layout.time(atY: 300) == 1)
    }
    @Test func clickHitsHeadsAndTheWholeHoldBody() {
        let layout = layout()
        let tap = Note(id: 1, kind: .tap, lane: 3, time: 1), hold = Note(id: 2, kind: .hold, lane: 5, time: 1, duration: 2)
        let touch = Note(id: 3, kind: .touch, lane: 2, area: "B", time: 2)
        let notes = [tap, hold, touch]
        #expect(layout.note(at: CGPoint(x: layout.x(lane: 3), y: 300), in: notes)?.id == 1)
        #expect(layout.note(at: CGPoint(x: layout.x(lane: 3), y: 200), in: notes) == nil)
        #expect(layout.note(at: CGPoint(x: layout.x(lane: 5), y: 180), in: notes)?.id == 2)
        #expect(layout.note(at: CGPoint(x: layout.touchX, y: 200), in: notes)?.id == 3)
    }
    @Test @MainActor func clickingANoteSelectsItsSourceRange() throws {
        let model = StudioModel(audioOutputEnabled: false)
        model.source = "(120){4}1,3,5,7,E"; model.chart = SimaiParser.parse(model.source)
        model.trackSpan = 4; model.trackStart = model.rangeStart
        let canvas = VerticalTrackCanvas(model: model)
        canvas.frame = NSRect(x: 0, y: 0, width: 446, height: 400)
        let note = try #require(model.chart.notes.first { $0.lane == 5 })
        let point = canvas.layout.center(of: note)
        #expect(canvas.layout.note(at: point, in: model.chart.notes)?.id == note.id)
        #expect(model.source[Range(NSRange(location: note.location.offset, length: note.location.length), in: model.source)!] == "5")
    }
    @Test func touchesAtTheSameInstantSitSideBySide() throws {
        let chart = SimaiParser.parse("(120){4}B2/B6/C,E4,E")
        var layout = layout()
        layout.touchSlots = VerticalTrackLayout.touchSlots(for: chart.notes)
        let group = chart.notes.filter { $0.time == 0 }, alone = try #require(chart.notes.first { $0.area == "E" })
        #expect(group.count == 3 && layout.touchSlots[alone.id] == nil && layout.center(of: alone).x == layout.touchX)
        let centers = group.map { layout.center(of: $0).x }
        #expect(centers == centers.sorted() && Set(centers).count == 3 && centers[0] > layout.keysEnd)
        // Each one is hit at its own centre, not whichever was drawn first.
        for note in group { #expect(layout.note(at: layout.center(of: note), in: chart.notes)?.id == note.id) }
    }
    @MainActor private func model(_ source: String) -> StudioModel {
        let model = StudioModel(audioOutputEnabled: false)
        model.source = source; model.chart = SimaiParser.parse(source)
        return model
    }
    @Test @MainActor func toolsWriteSimaiTextAndUndoRestoresIt() {
        let model = model("(120){4}1,,5,,E")
        model.trackDivisor = 8
        model.trackTool = .tap; model.place(lane: 3, at: 0.5)
        #expect(model.source == "(120){4}1,3,5,,E")
        #expect(model.chart.notes.count == 3 && model.selectedNotes.map(\.lane) == [3])
        model.trackTool = .hold; model.place(lane: 7, at: 1.5, until: 2.0)
        #expect(model.source == "(120){4}1,3,5,7h[8:2],E")
        model.placementFlags = ["b"]; model.trackTool = .tap; model.place(lane: 2, at: 0.25)
        #expect(model.source == "(120){8}1,2b,{4}3,5,7h[8:2],E")
        model.undoVisualEdit()
        #expect(model.source == "(120){4}1,3,5,7h[8:2],E" && model.chart.notes.count == 4)
        model.redoVisualEdit()
        #expect(model.chart.notes.contains { $0.lane == 2 && $0.isBreak && abs($0.time - 0.25) < 1e-9 })
    }
    @Test @MainActor func stageInputPlacesTouchesAndStarTails() {
        let model = model("(120){4}1,,5,,E")
        model.trackTool = .touch; model.currentTime = 0.52; model.trackDivisor = 4
        model.placeTouch(zone: "B3")
        #expect(model.source == "(120){4}1,B3,5,,E")
        model.trackTool = .slide; model.place(lane: 1, at: 1.5)
        #expect(model.pendingSlide == PendingSlide(lane: 1, time: 1.5) && model.source == "(120){4}1,B3,5,,E")
        model.finishSlide(zones: SlideMatching.zones(shape: "-", start: 1, end: 5), end: 5)
        #expect(model.source == "(120){4}1,B3,5,1-5[4:1],E" && model.pendingSlide == nil)
        #expect(model.chart.diagnostics.isEmpty && model.chart.notes.contains { $0.kind == .slide })
    }
    @Test @MainActor func aSecondTailJoinsTheSameStarHead() throws {
        let model = model("(120){4}1-5[4:1],,3,,E")
        model.trackTool = .slide; model.place(lane: 1, at: 0)
        model.finishSlide(zones: SlideMatching.zones(shape: "^", start: 1, end: 3), end: 3)
        #expect(model.source == "(120){4}1-5[4:1]*^3[4:1],,3,,E")
        #expect(model.chart.diagnostics.isEmpty)
        // One head, two tails.
        #expect(model.chart.notes.filter { $0.kind == .slide && $0.time == 0 }.count == 2)
        #expect(model.chart.notes.filter { $0.kind == .tap && $0.isStar && $0.time == 0 }.count == 1)
        model.place(lane: 1, at: 0)
        model.finishSlide(zones: SlideMatching.zones(shape: "v", start: 1, end: 7), end: 7)
        #expect(model.source == "(120){4}1-5[4:1]*^3[4:1]*v7[4:1],,3,,E" && model.chart.diagnostics.isEmpty)
        model.undoVisualEdit()
        #expect(model.source == "(120){4}1-5[4:1]*^3[4:1],,3,,E")
    }
    @Test @MainActor func flagsAndDeleteActOnTheSelectedNotes() throws {
        let model = model("(120){4}1/5,3,E")
        model.select(try #require(model.chart.notes.first { $0.lane == 5 }))
        model.toggleFlag("b")
        #expect(model.source == "(120){4}1/5b,3,E" && model.selectedNotes.map(\.lane) == [5])
        model.deleteSelectedNotes()
        #expect(model.source == "(120){4}1,3,E")
        model.selectedRange = NSRange(location: 0, length: (model.source as NSString).length)
        model.deleteSelectedNotes()
        #expect(model.source == "(120){4},,E" && model.chart.notes.isEmpty)
    }
    @Test @MainActor func mouseOnTheTrackPlacesHoldsAndDeletes() throws {
        let model = model("(120){4}1,,5,,E")
        model.trackSpan = 4; model.trackStart = model.rangeStart; model.trackDivisor = 4; model.timelineFollow = false
        let canvas = VerticalTrackCanvas(model: model)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 446, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas; canvas.frame = NSRect(x: 0, y: 0, width: 446, height: 400)
        func event(_ type: NSEvent.EventType, lane: Int, time: Double) throws -> NSEvent {
            // Window coordinates start at the bottom; the canvas is flipped.
            let location = CGPoint(x: canvas.layout.x(lane: lane), y: 400 - canvas.layout.y(time))
            return try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        model.trackTool = .tap
        canvas.mouseDown(with: try event(.leftMouseDown, lane: 3, time: 0.55))
        #expect(model.source == "(120){4}1,3,5,,E")
        model.trackTool = .hold
        canvas.mouseDown(with: try event(.leftMouseDown, lane: 7, time: 1.5))
        canvas.mouseDragged(with: try event(.leftMouseDragged, lane: 7, time: 2.4))
        canvas.mouseUp(with: try event(.leftMouseUp, lane: 7, time: 2.4))
        #expect(model.source == "(120){4}1,3,5,7h[4:2],E")
        // A click on an existing note selects it instead of stacking a second one.
        model.trackTool = .tap
        canvas.mouseDown(with: try event(.leftMouseDown, lane: 5, time: 1.0))
        #expect(model.source == "(120){4}1,3,5,7h[4:2],E" && model.selectedNotes.map(\.lane) == [5])
        canvas.rightMouseDown(with: try event(.rightMouseDown, lane: 3, time: 0.5))
        #expect(model.source == "(120){4}1,,5,7h[4:2],E")
    }
    @Test @MainActor func aChartCanBeBuiltFromTheBlankDocumentWithTheMouse() throws {
        let model = StudioModel(audioOutputEnabled: false)
        model.source = ChartDocument.blank.chart(4); model.chart = SimaiParser.parse(model.source)
        model.trackSpan = 4; model.trackStart = 0; model.trackDivisor = 8; model.timelineFollow = false
        let canvas = VerticalTrackCanvas(model: model)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 446, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas; canvas.frame = NSRect(x: 0, y: 0, width: 446, height: 400)
        func click(lane: Int, time: Double) throws {
            let location = CGPoint(x: canvas.layout.x(lane: lane), y: 400 - canvas.layout.y(time))
            canvas.mouseDown(with: try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
        }
        model.trackTool = .tap
        // Well past the two seconds an empty chart lasts: the track has to reach there.
        for (lane, time) in [(1, 0.0), (5, 0.25), (3, 1.0), (7, 3.0), (2, 3.25)] { try click(lane: lane, time: time) }
        #expect(model.chart.diagnostics.isEmpty)
        #expect(model.chart.notes.map { [$0.time, Double($0.lane)] } == [[0, 1], [0.25, 5], [1, 3], [3, 7], [3.25, 2]])
        // Scrolled to a later page the clicks still land where the pointer is.
        model.trackStart = 4
        try click(lane: 8, time: 6.5)
        #expect(model.chart.notes.contains { $0.lane == 8 && abs($0.time - 6.5) < 1e-6 })
        for _ in 0..<6 { model.undoVisualEdit() }
        #expect(model.source == ChartDocument.blank.chart(4) && model.chart.notes.isEmpty)
    }
    @MainActor private func wait(_ seconds: Double, until done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !done() && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
    }
    @Test @MainActor func placingANoteKeepsPlaybackRunningAndSwapsTheMix() async throws {
        let model = StudioModel(audioOutputEnabled: false)
        model.source = "(120){4}1,,5,,3,,7,,1,,5,,3,,7,,E"; model.chart = SimaiParser.parse(model.source)
        model.prepareAudio(thenPlay: true)
        try await wait(20) { model.isPlaying }
        let first = try #require(model.prepared?.url)
        #expect(model.isPlaying && !model.audioStale)
        try await Task.sleep(for: .milliseconds(300))
        model.trackTool = .tap; model.place(lane: 8, at: 2.5)
        // The edit itself neither stops playback nor throws the playable mix away.
        #expect(model.isPlaying && model.prepared?.url == first && model.audioStale && !model.isPreparing)
        try await wait(20) { !model.audioStale }
        let position = model.playbackTime
        #expect(model.prepared?.url != first && model.isPlaying && !model.isPreparing)
        #expect(position > 0.3 && position < 6)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        model.pause()
        // Paused edits wait for the new mix when play is pressed straight away.
        model.place(lane: 2, at: 3.0); model.togglePlayback()
        #expect(model.isPreparing && !model.isPlaying)
        try await wait(20) { model.isPlaying }
        #expect(model.isPlaying && !model.audioStale)
        model.invalidateAudio()
    }
    @Test @MainActor func editingWhilePausedNeverStartsPlaybackOrMovesThePlayhead() async throws {
        let model = StudioModel(audioOutputEnabled: false)
        model.source = ChartDocument.blank.chart(4); model.chart = SimaiParser.parse(model.source)
        model.trackTool = .tap; model.place(lane: 3, at: 0.5); model.place(lane: 5, at: 1.25)
        model.trackTool = .hold; model.place(lane: 7, at: 1.75, until: 2.75)
        try await Task.sleep(for: .seconds(1.5)); model.tick()
        #expect(!model.isPlaying && !model.isPreparing && model.currentTime == 0 && model.prepared == nil)
        // With a mix already prepared and playback paused part-way through.
        model.prepareAudio(thenPlay: false)
        try await wait(20) { model.prepared != nil && !model.isPreparing }
        model.seek(1.0)
        model.trackTool = .tap; model.place(lane: 2, at: 2.0)
        try await wait(20) { !model.audioStale }
        try await Task.sleep(for: .milliseconds(500)); model.tick()
        #expect(!model.audioStale && !model.isPlaying && !model.isPreparing && model.currentTime == 1.0)
        model.invalidateAudio()
    }
}
