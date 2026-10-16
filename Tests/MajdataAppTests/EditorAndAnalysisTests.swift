import Testing
import AppKit
import SwiftUI
import MajdataCore
@testable import MajdataMac

@Suite(.serialized) struct EditorAndAnalysisTests {
    @Test @MainActor func switchingModesKeepsThePlayableMixSourceAndSelection() async throws {
        let defaults = UserDefaults.standard, previous = defaults.object(forKey: "editorMode")
        defaults.set(EditorMode.visual.rawValue, forKey: "editorMode")
        let model = StudioModel(audioOutputEnabled: false)
        model.source = "(120){4}1,,3,,5,,7,,1,,3,,5,,7,,E"
        model.chart = SimaiParser.parse(model.source)
        model.selectedRange = NSRange(location: 7, length: 1)
        let source = model.source, selection = model.selectedRange
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 920),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: StudioView(model: model))
        window.contentView = host
        // A visible host advances AppKit-backed opacity transitions and their teardown.
        window.orderFront(nil)
        defer {
            model.invalidateAudio(); window.close()
            if let previous { defaults.set(previous, forKey: "editorMode") } else { defaults.removeObject(forKey: "editorMode") }
        }
        model.prepareAudio(thenPlay: true)
        let deadline = Date().addingTimeInterval(20)
        while !model.isPlaying && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
        #expect(model.isPlaying)
        let mix = try #require(model.prepared?.url), start = model.playbackTime
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for mode in [EditorMode.code, .visual, .code, .visual] {
            defaults.set(mode.rawValue, forKey: "editorMode")
            let transitionDeadline = Date().addingTimeInterval(2)
            var views = descendants(host)
            repeat {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(30))
                views = descendants(host)
                if views.filter({ $0 is VerticalTrackCanvas }).count == (mode == .visual ? 1 : 0)
                    && views.filter({ $0 is PlaybackTextView }).count == (mode == .code ? 1 : 0) { break }
            } while Date() < transitionDeadline
            #expect(views.filter { $0 is VerticalTrackCanvas }.count == (mode == .visual ? 1 : 0))
            #expect(views.filter { $0 is PlaybackTextView }.count == (mode == .code ? 1 : 0))
            #expect(model.source == source && model.selectedRange == selection && !model.isDirty)
            #expect(model.isPlaying && model.prepared?.url == mix && !model.isPreparing)
        }
        #expect(model.playbackTime > start)
    }
    @Test @MainActor func visualWorkspaceKeepsTrackAndSquareStageInsideNarrowLayouts() async throws {
        let model = StudioModel(audioOutputEnabled: false)
        let host = NSHostingView(rootView: VisualWorkspace(model: model, showCode: {}))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 800),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close(); model.invalidateAudio() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for size in [NSSize(width: 600, height: 560), NSSize(width: 850, height: 650),
                     NSSize(width: 1100, height: 650), NSSize(width: 1440, height: 800)] {
            window.setContentSize(size); host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded()
            let views = descendants(host)
            let track = try #require(views.first { $0 is VerticalTrackCanvas })
            let input = try #require(views.first { $0 is StageInputView })
            for view in [track, input] {
                let rect = view.convert(view.bounds, to: host)
                #expect(rect.minX >= -1 && rect.maxX <= size.width + 1)
                #expect(rect.minY >= -1 && rect.maxY <= size.height + 1)
                #expect(rect.width > 100 && rect.height > 100)
            }
            #expect(abs(input.bounds.width - input.bounds.height) < 1)
            #expect(!model.isDirty)
        }
    }
    @Test @MainActor func completeWorkspaceSurvivesWindowResizing() async {
        let model = StudioModel(audioOutputEnabled: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 920),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: StudioView(model: model))
        defer { window.close() }
        for size in [NSSize(width: 1440, height: 920), NSSize(width: 1100, height: 720), NSSize(width: 1728, height: 980)] {
            window.setContentSize(size)
            window.contentView?.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(80))
            #expect(window.contentView?.bounds.size == size)
            #expect(!model.isDirty)
        }
    }
    @Test @MainActor func hostedEditorFollowsPlaybackUpdates() async throws {
        let model = StudioModel(audioOutputEnabled: false)
        model.source = "(120){4}1,,3,E"; model.chart = SimaiParser.parse(model.source)
        let host = NSHostingView(rootView: CodeEditor(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        host.layoutSubtreeIfNeeded()
        func findText(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { findText($0) }.first
        }
        let text = try #require(findText(host))
        let selection = text.selectedRange()
        for time in [0.6, 1.1, 0.1] {
            model.currentTime = time
            try await Task.sleep(for: .milliseconds(70))
            host.layoutSubtreeIfNeeded()
            let range = try #require(PlaybackSourceIndex(chart: model.chart).highlights(at: time).current)
            #expect(text.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: range.location, effectiveRange: nil) is NSColor)
            #expect(text.selectedRange() == selection)
            #expect((text as? PlaybackTextView)?.playbackRange == range)
        }
    }
    @MainActor private func saveProof(_ bitmap: NSBitmapImageRep, to url: URL) throws {
        let context = try #require(CGContext(data: nil, width: bitmap.pixelsWide, height: bitmap.pixelsHigh,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let bounds = CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(bounds)
        context.draw(try #require(bitmap.cgImage), in: bounds)
        let image = try #require(context.makeImage())
        try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: url)
    }
    @Test @MainActor func editorAndAnalysisProof() async throws {
        guard let folder = ProcessInfo.processInfo.environment["MAJDATA_EDITOR_PROOF"] else { return }
        let root = URL(fileURLWithPath: folder)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = StudioModel()
        model.source = "|| 播放位置高亮\n(120){4}\n1h[4:4]/5,2,3,4,\n5-1[4:2],6,7,8,\nE"
        model.chart = SimaiParser.parse(model.source); model.currentTime = 0.65; model.follow = false
        let editor = NSHostingView(rootView: CodeEditor(model: model).background(Color.white).environment(\.colorScheme, .light))
        editor.frame = NSRect(x: 0, y: 0, width: 680, height: 340)
        editor.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let bitmap = try #require(editor.bitmapImageRepForCachingDisplay(in: editor.bounds))
        editor.cacheDisplay(in: editor.bounds, to: bitmap)
        try saveProof(bitmap, to: root.appendingPathComponent("editor-highlight.png"))
        let proofModel = StudioModel()
        if let chartPath = ProcessInfo.processInfo.environment["MAJDATA_REAL_CHART"] {
            proofModel.document = ChartDocument(text: try String(contentsOf: URL(fileURLWithPath: chartPath).appendingPathComponent("maidata.txt"), encoding: .utf8))
            proofModel.source = proofModel.document.chart(5)
        } else { proofModel.source = "(120){4}1/1,E" }
        proofModel.chart = SimaiParser.parse(proofModel.source, offset: proofModel.document.offset)
        proofModel.analysis = try ChartAnalysis.inspect(proofModel.chart)
        let view = AnalysisView(model: proofModel) {}.frame(width: 900, height: 800).background(.white).environment(\.colorScheme, .light)
        let analysis = NSHostingView(rootView: view)
        analysis.frame = NSRect(x: 0, y: 0, width: 900, height: 800)
        analysis.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let reportBitmap = try #require(analysis.bitmapImageRepForCachingDisplay(in: analysis.bounds))
        analysis.cacheDisplay(in: analysis.bounds, to: reportBitmap)
        try saveProof(reportBitmap, to: root.appendingPathComponent("analysis-real.png"))
    }
    @Test @MainActor func playbackHighlightDoesNotMoveSelectionOrChangeText() throws {
        let model = StudioModel()
        model.source = "(120){4}1h[4:4],2,3,E"; model.chart = SimaiParser.parse(model.source)
        let text = NSTextView(); text.string = model.source
        let caret = NSRange(location: 4, length: 2)
        text.setSelectedRange(caret); model.selectedRange = caret
        let coordinator = CodeEditor.Coordinator(model); coordinator.textView = text
        model.currentTime = 0.6; coordinator.highlightPlayback()
        let range = try #require(PlaybackSourceIndex(chart: model.chart).highlights(at: 0.6).current)
        #expect(text.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: range.location, effectiveRange: nil) is NSColor)
        #expect(text.selectedRange() == caret && model.selectedRange == caret && text.string == model.source)
        model.follow = false; model.currentTime = 1.1; coordinator.highlightPlayback()
        #expect(text.selectedRange() == caret)
        model.currentTime = 0; coordinator.highlightPlayback()
        #expect(text.selectedRange() == caret)
        model.currentTime = 10; coordinator.highlightPlayback()
        #expect(text.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: range.location, effectiveRange: nil) == nil)
        #expect(text.string == model.source)
    }
    @Test @MainActor func analysisIsInvalidatedByEditsAndDifficultyChanges() async throws {
        let model = StudioModel()
        model.source = "(120){4}1/1,E"; model.chart = SimaiParser.parse(model.source)
        model.checkConflicts()
        for _ in 0..<100 where model.isAnalyzing { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.analysis?.inputConflicts.count == 1)
        model.selectDifficulty(0)
        #expect(model.analysis == nil && !model.isAnalyzing)
        model.source = "(120){4}1/1,E"; model.checkConflicts()
        model.edited("(120){4}1,E")
        // Parsing is debounced and shares MainActor with render/export tests.
        // Wait for the observable completion, not a fixed wall-clock deadline.
        for _ in 0..<200 where model.chart.notes.count != 1 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.analysis == nil && !model.isAnalyzing)
        #expect(model.chart.notes.count == 1)
    }
}
