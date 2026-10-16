import Testing
import AppKit
import SwiftUI
import MajdataCore
@testable import MajdataMac

@Suite(.serialized) struct FeedbackRegressionTests {
    @MainActor private func textView(in view: NSView) -> PlaybackTextView? {
        if let text = view as? PlaybackTextView { return text }
        return view.subviews.lazy.compactMap { textView(in: $0) }.first
    }
    @Test @MainActor func typingMirrorAndModeChangesShareUndoHistory() throws {
        let model = StudioModel(audioOutputEnabled: false)
        defer { model.invalidateAudio() }
        let host = NSHostingView(rootView: CodeEditor(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 350, height: 350); host.layoutSubtreeIfNeeded()
        let text = try #require(textView(in: host))
        let initial = model.source
        let source = "(120){4}1,2,3,4,E"
        text.insertText(source, replacementRange: NSRange(location: 0, length: text.string.utf16.count))
        #expect(model.source == source)
        text.setSelectedRange(NSRange(location: 0, length: text.string.utf16.count))
        model.transform(ChartTransform.allCases[0])
        let mirrored = model.source
        #expect(mirrored != source && text.string == mirrored)
        text.insertText("\n|| comment", replacementRange: NSRange(location: text.string.utf16.count, length: 0))
        let typed = model.source
        text.undo(nil); #expect(model.source == mirrored && text.string == mirrored)
        text.undo(nil); #expect(model.source == source && text.string == source)
        text.undo(nil); #expect(model.source == initial && text.string == initial)
        text.redo(nil); text.redo(nil); text.redo(nil)
        #expect(model.source == typed && text.string == typed)
        // The new source editor after a mode change must use the same history.
        let next = NSHostingView(rootView: CodeEditor(model: model))
        next.frame = host.frame; next.layoutSubtreeIfNeeded()
        let replacement = try #require(textView(in: next))
        replacement.undo(nil); replacement.undo(nil)
        #expect(model.source == source && replacement.string == source)
        model.selectDifficulty(0)
        #expect(!model.sourceUndoManager.canUndo && model.visualUndo.isEmpty)
    }
    @Test @MainActor func adjacentTypingCoalescesButCaretMovementStartsANewUndo() throws {
        let model = StudioModel(audioOutputEnabled: false)
        defer { model.invalidateAudio() }
        model.source = ""
        let host = NSHostingView(rootView: CodeEditor(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 350, height: 350); host.layoutSubtreeIfNeeded()
        let text = try #require(textView(in: host))
        text.insertText("1", replacementRange: NSRange(location: 0, length: 0))
        text.insertText("2", replacementRange: NSRange(location: 1, length: 0))
        #expect(model.visualUndo.count == 1)
        text.setSelectedRange(NSRange(location: 0, length: 0))
        text.insertText("3", replacementRange: text.selectedRange())
        text.undo(nil); #expect(model.source == "12")
        text.undo(nil); #expect(model.source.isEmpty)
    }
    @Test @MainActor func playbackUpdatesKeepMarkedTextUntilInputCommits() async throws {
        let model = StudioModel(audioOutputEnabled: false)
        defer { model.invalidateAudio() }
        model.source = "|| "; model.chart = SimaiParser.parse(model.source)
        let host = NSHostingView(rootView: CodeEditor(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 350, height: 350); host.layoutSubtreeIfNeeded()
        let text = try #require(textView(in: host))
        text.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: 3, length: 0))
        #expect(text.hasMarkedText() && model.source == "|| ")
        model.currentTime = 1
        try await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded()
        #expect(text.hasMarkedText() && text.string == "|| zhong")
        text.insertText("中", replacementRange: text.markedRange())
        #expect(!text.hasMarkedText() && model.source == "|| 中")
        text.undo(nil)
        #expect(model.source == "|| " && text.string == "|| ")
    }
    @Test @MainActor func hardReturnsHaveMoreSpaceThanSoftWrapping() throws {
        let model = StudioModel(audioOutputEnabled: false)
        defer { model.invalidateAudio() }
        model.source = String(repeating: "1,", count: 35) + "\n2,\n\n3,E"
        let host = NSHostingView(rootView: CodeEditor(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 220, height: 500); host.layoutSubtreeIfNeeded()
        let text = try #require(textView(in: host)), layout = try #require(text.layoutManager)
        layout.ensureLayout(for: try #require(text.textContainer))
        var lines: [NSRect] = []
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { rect, _, _, _, _ in lines.append(rect) }
        #expect(lines.count >= 6)
        let softGap = lines[1].minY - lines[0].minY
        let newline = (model.source as NSString).range(of: "\n").location
        func y(_ character: Int) -> Double {
            layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: character), effectiveRange: nil).minY
        }
        #expect(y(newline + 1) - y(newline - 1) > softGap + 5)
        #expect(abs((text.defaultParagraphStyle?.paragraphSpacing ?? 0) - model.fontSize * 0.45) < 0.001)
    }
    @MainActor private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(condition())
    }
    @Test @MainActor func silentEditsReuseAudioImmediatelyAndKeepThePlayhead() async throws {
        let model = StudioModel(audioOutputEnabled: false)
        defer { model.invalidateAudio() }
        model.source = "(120){4}1,,3,,5,,7,,E"; model.chart = SimaiParser.parse(model.source)
        model.prepareAudio(thenPlay: false)
        try await wait { model.prepared != nil && !model.isPreparing }
        let audio = try #require(model.prepared?.url)
        model.seek(1)
        model.selectedRange = NSRange(location: 0, length: model.source.utf16.count)
        model.transform(ChartTransform.allCases[0]); model.togglePlayback()
        #expect(model.isPlaying && !model.isPreparing && !model.audioStale && model.prepared?.url == audio)
        #expect(model.playbackTime >= 1 && model.playbackTime < 1.3)
        model.pause()
        model.edited("|| formatting only\n" + model.source.replacingOccurrences(of: ",,", with: ",,\n"))
        model.togglePlayback()
        #expect(model.isPlaying && !model.isPreparing && model.prepared?.url == audio)
        model.pause()
        model.document.title = "Updated title"; model.metadataChanged(); model.togglePlayback()
        #expect(model.isPlaying && !model.isPreparing && model.prepared?.url == audio)
    }
    @Test @MainActor func changedAudioCannotBePublishedFromAnOlderSourceRevision() async throws {
        let model = StudioModel(audioOutputEnabled: false)
        defer { model.invalidateAudio() }
        model.source = "(120){4}1,,3,,5,,7,,E"; model.chart = SimaiParser.parse(model.source)
        model.prepareAudio(thenPlay: true)
        model.edited("(120){4}2b,,,,,,,,2b,,,,,,,,E")
        try await wait { model.isPlaying && !model.audioStale && !model.isPreparing }
        #expect(model.chart.notes.filter(\.isBreak).count == 2)
        let prepared = try #require(model.prepared)
        #expect(prepared.stems[.break] != nil)
    }
    @Test func regionAndMetronomeChangesInvalidateAudioIdentity() {
        let chart = SimaiParser.parse("(120){4}1,3,5,7,E")
        let first = PreviewAudioIdentity(chart: chart, music: nil, metronome: false, regionSource: nil)
        #expect(first != PreviewAudioIdentity(chart: chart, music: nil, metronome: true, regionSource: nil))
        #expect(first != PreviewAudioIdentity(chart: chart, music: nil, metronome: false, regionSource: "regions"))
        #expect(first != PreviewAudioIdentity(chart: chart, music: URL(fileURLWithPath: "/test.wav"), metronome: false, regionSource: nil))
    }
}
