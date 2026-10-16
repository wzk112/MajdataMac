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
        // Three or more become a small map of the stage: every zone at its own spot, C in the middle.
        let centre = try #require(group.first { $0.area == "C" })
        #expect(layout.inCluster(centre) && layout.center(of: centre) == CGPoint(x: layout.clusterX, y: layout.y(0)))
        #expect(Set(group.map { "\(layout.center(of: $0))" }).count == 3)
        // Each one is hit at its own centre, not whichever was drawn first.
        for note in group { #expect(layout.note(at: layout.center(of: note), in: chart.notes)?.id == note.id) }
    }
    @Test func aPairSharesTheColumnAndEveryZoneAtOnceStaysDistinct() throws {
        var layout = layout()
        let pair = SimaiParser.parse("(120){4}B2/B6,E").notes
        layout.touchSlots = VerticalTrackLayout.touchSlots(for: pair)
        #expect(!layout.inCluster(pair[0]) && layout.center(of: pair[0]).x < layout.center(of: pair[1]).x)
        let zones = ["C"] + "ABDE".flatMap { area in (1...8).map { "\(area)\($0)" } }
        let full = SimaiParser.parse("(120){4}" + zones.joined(separator: "/") + ",E").notes
        layout.touchSlots = VerticalTrackLayout.touchSlots(for: full)
        #expect(full.count == 33)
        #expect(Set(full.map { "\(layout.center(of: $0))" }).count == 33)
        for note in full { #expect(layout.note(at: layout.center(of: note), in: full)?.id == note.id) }
    }
    @Test @MainActor func lengthsCanBeChangedAfterPlacing() throws {
        let model = model("(120){4}Ch[4:1],,3h[4:1],,1-5[0##4:1],,,,E")
        model.trackDivisor = 8
        let touchHold = try #require(model.chart.notes.first { $0.kind == .touchHold })
        model.select(touchHold); model.setSelectedDuration("2:1")
        #expect(model.source == "(120){4}Ch[2:1],,3h[4:1],,1-5[0##4:1],,,,E")
        // Dragging the far end of the hold from 1.5 s to 2.25 s: five eighth-note steps.
        let canvas = VerticalTrackCanvas(model: model)
        model.trackSpan = 4; model.trackStart = 0; model.timelineFollow = false
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 446, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas; canvas.frame = NSRect(x: 0, y: 0, width: 446, height: 400)
        func event(_ type: NSEvent.EventType, time: Double) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: CGPoint(x: canvas.layout.x(lane: 3), y: 400 - canvas.layout.y(time)), modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, time: 1.5))
        canvas.mouseDragged(with: try event(.leftMouseDragged, time: 2.26))
        canvas.mouseUp(with: try event(.leftMouseUp, time: 2.26))
        #expect(model.source == "(120){4}Ch[2:1],,3h[8:5],,1-5[0##4:1],,,,E")
        // A slide keeps its wait prefix.
        model.select(try #require(model.chart.notes.first { $0.kind == .slide })); model.setSelectedDuration("8:3")
        #expect(model.source == "(120){4}Ch[2:1],,3h[8:5],,1-5[0##8:3],,,,E" && model.chart.diagnostics.isEmpty)
        model.undoVisualEdit(); model.undoVisualEdit(); model.undoVisualEdit()
        #expect(model.source == "(120){4}Ch[4:1],,3h[4:1],,1-5[0##4:1],,,,E")
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
        // A second click on the same zone at the same instant does not stack a copy.
        model.placeTouch(zone: "B3")
        #expect(model.source == "(120){4}1,B3,5,,E" && model.selectedNotes.map(\.area) == ["B"])
        model.trackTool = .slide; model.place(lane: 1, at: 1.5)
        #expect(model.pendingSlide == PendingSlide(lane: 1, time: 1.5) && model.source == "(120){4}1,B3,5,,E")
        model.finishSlide(zones: SlideMatching.zones(shape: "-", start: 1, end: 5), end: 5)
        #expect(model.source == "(120){4}1,B3,5,1-5[4:1],E" && model.pendingSlide == PendingSlide(lane: 1, time: 1.5, from: 5))
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
    @Test @MainActor func strokesAfterTheFirstConnectIntoOneSlide() throws {
        let model = model("(120){4}1,,,,,,,,E")
        model.trackTool = .slide; model.place(lane: 3, at: 0.5)
        model.finishSlide(zones: SlideMatching.zones(shape: "-", start: 3, end: 7), end: 7)
        model.finishSlide(zones: SlideMatching.zones(shape: "^", start: 7, end: 1), end: 1)
        model.finishSlide(zones: SlideMatching.zones(shape: "v", start: 1, end: 4), end: 4)
        #expect(model.source == "(120){4}1,3-7[4:1]^1[4:1]v4[4:1],,,,,,,E")
        #expect(model.chart.diagnostics.isEmpty)
        let slide = try #require(model.chart.notes.first { $0.kind == .slide })
        #expect(slide.segments.map { [$0.start, $0.end] } == [[3, 7], [7, 1], [1, 4]])
        // Clicking the same star on the track starts a separate tail from the head instead.
        model.place(lane: 3, at: 0.5)
        #expect(model.pendingSlide == PendingSlide(lane: 3, time: 0.5))
        model.finishSlide(zones: SlideMatching.zones(shape: "-", start: 3, end: 6), end: 6)
        #expect(model.source == "(120){4}1,3-7[4:1]^1[4:1]v4[4:1]*-6[4:1],,,,,,,E" && model.chart.diagnostics.isEmpty)
    }
    @Test @MainActor func starOptionsAreWrittenIntoTheToken() throws {
        let model = model("(120){4}1,,,,,,,,E")
        model.trackTool = .slide; model.placementFlags = ["h", "s"]; model.slideWaitsOneBeat = false
        model.place(lane: 2, at: 0.5)
        model.finishSlide(zones: SlideMatching.zones(shape: "-", start: 2, end: 6), end: 6)
        #expect(model.source == "(120){4}1,2?-6b[0##4:1],,,,,,,E" && model.chart.diagnostics.isEmpty)
        let slide = try #require(model.chart.notes.first { $0.kind == .slide })
        // Headless, break, and moving at once: no star head, no one-beat wait.
        #expect(slide.isBreak && slide.segments[0].startTime == slide.time)
        #expect(!model.chart.notes.contains { $0.kind == .tap && $0.isStar })
        model.pendingSlide = nil; model.placementFlags = []
        model.select(slide)
        model.toggleFlag("s"); #expect(model.source == "(120){4}1,2?-6[0##4:1],,,,,,,E")
        model.toggleFlag("h"); #expect(model.source == "(120){4}1,2-6[0##4:1],,,,,,,E")
        model.toggleFlag("s"); #expect(model.source == "(120){4}1,2-6b[0##4:1],,,,,,,E" && model.chart.diagnostics.isEmpty)
    }
    @Test @MainActor func anEditThatWouldBreakTheChartIsNotWritten() throws {
        // A hand-written connected slide with one total duration cannot take a per-segment one.
        let model = model("(120){4}1-4-7[4:1],,,,E")
        model.trackTool = .slide
        model.pendingSlide = PendingSlide(lane: 1, time: 0, from: 7)
        model.finishSlide(zones: SlideMatching.zones(shape: "-", start: 7, end: 3), end: 3)
        #expect(model.source == "(120){4}1-4-7[4:1],,,,E" && model.visualUndo.isEmpty)
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
    @Test @MainActor func menuTransformsAndSubdivisionUndoOneOperationAtATime() throws {
        for transform in ChartTransform.allCases {
            let model = model("(120){4}1,,5,,E")
            defer { model.invalidateAudio() }
            model.trackTool = .tap; model.place(lane: 3, at: 0.5)
            let placed = model.source, selection = model.selectedRange
            model.transform(transform) // The menu and tool panel call this same entry point.
            let transformed = model.source
            #expect(transformed != placed && model.visualUndo.count == 2)
            model.undoVisualEdit()
            #expect(model.source == placed && model.selectedRange == selection)
            model.redoVisualEdit(); #expect(model.source == transformed)
            model.undoVisualEdit(); model.undoVisualEdit()
            #expect(model.source == "(120){4}1,,5,,E")
        }
        let model = model("(120){4}1,,5,,E")
        defer { model.invalidateAudio() }
        model.trackTool = .tap; model.place(lane: 3, at: 0.5)
        model.selectedRange = NSRange(location: 0, length: model.source.utf16.count)
        let placed = model.source
        model.subdivide(); let subdivided = model.source
        #expect(subdivided != placed && model.visualUndo.count == 2)
        model.undoVisualEdit(); #expect(model.source == placed)
        model.redoVisualEdit(); #expect(model.source == subdivided)
    }
    @Test @MainActor func compactChordFlagsAndPseudoDeletionWorkThroughVisualHistory() throws {
        let model = model("(120){4}15`3,,E")
        defer { model.invalidateAudio() }
        let one = try #require(model.chart.notes.first { $0.lane == 1 })
        model.select(one); model.toggleFlag("b")
        #expect(model.source == "(120){4}1b/5`3,,E")
        #expect(model.selectedNotes.count == 1 && model.selectedNotes[0].isBreak)
        model.undoVisualEdit(); #expect(model.source == "(120){4}15`3,,E")
        model.delete(try #require(model.chart.notes.first { $0.lane == 5 }))
        #expect(model.chart.notes.first { $0.lane == 3 }?.time == 0.001)
        model.undoVisualEdit(); #expect(model.source == "(120){4}15`3,,E")
    }
    @Test @MainActor func stageMouseStrokeKeepsFullCircleAndLoopDirection() throws {
        for shape in ["<", ">", "p", "q"] {
            let model = model("(120){4},,,,E")
            defer { model.invalidateAudio() }
            model.trackTool = .slide; model.place(lane: 1, at: 0)
            let view = StageInputView(model: model)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 600),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view; view.frame = NSRect(x: 0, y: 0, width: 600, height: 600)
            let points = SlideGeometry.points(for: SlideSegment(shape: shape, start: 1, end: 1))
            func event(_ type: NSEvent.EventType, _ point: Point) throws -> NSEvent {
                let unit = 600.0 / 11.465929
                let location = CGPoint(x: 300 + point.x * 4.8 * unit, y: 300 - point.y * 4.8 * unit)
                return try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            }
            view.mouseDown(with: try event(.leftMouseDown, points[0]))
            for point in points.dropFirst() { view.mouseDragged(with: try event(.leftMouseDragged, point)) }
            view.mouseUp(with: try event(.leftMouseUp, points.last!))
            let slide = try #require(model.chart.notes.first { $0.kind == .slide })
            #expect(slide.segments.first?.shape == shape && slide.segments.first?.end == 1)
            #expect(!model.chart.hasErrors)
        }
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
