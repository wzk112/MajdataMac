import Testing
import AppKit
import MajdataCore
@testable import MajdataMac

@Suite struct VerticalTrackTests {
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
        #expect(model.source == "(120){4}{8}1,2b,{4}3,5,7h[8:2],E")
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
}
