import SwiftUI
import AppKit
import MajdataCore

struct CodeEditor: NSViewRepresentable {
    @Bindable var model: StudioModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        let text = PlaybackTextView(); text.isRichText = false; text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false; text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false; text.isContinuousSpellCheckingEnabled = false
        text.isGrammarCheckingEnabled = false; text.allowsUndo = false; text.isIncrementalSearchingEnabled = true
        text.usesFindBar = true; text.drawsBackground = false; text.textColor = .labelColor
        text.insertionPointColor = .systemPurple; text.font = .monospacedSystemFont(ofSize: model.fontSize, weight: .regular)
        text.textContainerInset = NSSize(width: 18, height: 18)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.model = model; model.sourceEditor = text
        text.string = model.source; text.delegate = context.coordinator
        context.coordinator.applyTypography(to: text)
        text.setAccessibilityLabel("Simai 谱面编辑器")
        scroll.documentView = text
        context.coordinator.textView = text
        context.coordinator.colorize()
        context.coordinator.highlightPlayback()
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        context.coordinator.model = model
        // Playback updates must not replace an in-progress Chinese input composition.
        guard !text.hasMarkedText() else { return }
        context.coordinator.updating = true
        if text.string != model.source {
            context.coordinator.clearPlaybackHighlight()
            let selection = text.selectedRange()
            text.string = model.source
            text.setSelectedRange(NSRange(location: min(selection.location, text.string.utf16.count), length: 0))
            context.coordinator.applyTypography(to: text)
            context.coordinator.colorize()
        }
        if text.font?.pointSize != CGFloat(model.fontSize) { context.coordinator.applyTypography(to: text) }
        let selectionChanged = text.selectedRange() != model.selectedRange
        if NSMaxRange(model.selectedRange) <= text.string.utf16.count && selectionChanged {
            text.setSelectedRange(model.selectedRange); text.scrollRangeToVisible(model.selectedRange)
        }
        context.coordinator.updating = false
        context.coordinator.highlightPlayback(allowScroll: !selectionChanged)
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var model: StudioModel
        weak var textView: NSTextView?
        var updating = false
        private var indexedRevision: UUID?
        private var indexedSource = ""
        private var sourceIndex: PlaybackSourceIndex?
        private var highlights: PlaybackSourceHighlights?
        private var following = false
        init(_ model: StudioModel) { self.model = model }
        func textDidChange(_ notification: Notification) {
            guard !updating, let textView, !textView.hasMarkedText(), textView.string != model.source else { return }
            clearPlaybackHighlight()
            let singleCharacter = abs(textView.string.utf16.count - model.source.utf16.count) == 1
            model.recordSourceUndo(VisualSnapshot(source: model.source, selection: model.selectedRange), typing: singleCharacter)
            model.selectedRange = textView.selectedRange(); model.edited(textView.string); colorize()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating, let textView else { return }
            // Selection movement ends a typing group; delegate selection changes during
            // a keystroke arrive before textDidChange and must retain the old caret for undo.
            guard textView.string == model.source else { return }
            if model.selectedRange != textView.selectedRange() { model.lastTypingTime = .distantPast }
            model.selectedRange = textView.selectedRange()
        }
        func applyTypography(to text: NSTextView) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = model.fontSize * 0.20
            paragraph.paragraphSpacing = model.fontSize * 0.45
            text.font = .monospacedSystemFont(ofSize: model.fontSize, weight: .regular)
            text.defaultParagraphStyle = paragraph
            text.typingAttributes[.paragraphStyle] = paragraph
            text.textStorage?.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.string.utf16.count))
        }
        func clearPlaybackHighlight() {
            guard let textView else { return }
            let count = textView.string.utf16.count
            for range in (highlights?.sustained ?? []) + (highlights?.current.map { [$0] } ?? []) where range.location < count {
                let valid = NSRange(location: range.location, length: min(range.length, count - range.location))
                textView.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: valid)
            }
            (textView as? PlaybackTextView)?.playbackRange = nil
            highlights = nil
        }
        func highlightPlayback(allowScroll: Bool = true) {
            guard let text = textView, let layout = text.layoutManager else { return }
            if indexedRevision != model.chart.renderRevision {
                clearPlaybackHighlight()
                sourceIndex = PlaybackSourceIndex(chart: model.chart); indexedRevision = model.chart.renderRevision
                indexedSource = text.string
            }
            guard indexedSource == text.string else { clearPlaybackHighlight(); return }
            guard let next = sourceIndex?.highlights(at: model.currentTime) else { return }
            let changed = highlights != next
            if changed {
                clearPlaybackHighlight()
                let count = text.string.utf16.count
                for range in next.sustained where range.location >= 0 && NSMaxRange(range) <= count {
                    layout.addTemporaryAttribute(.backgroundColor, value: NSColor.systemOrange.withAlphaComponent(0.20), forCharacterRange: range)
                }
                if let range = next.current, range.location >= 0, NSMaxRange(range) <= count {
                    layout.addTemporaryAttribute(.backgroundColor, value: NSColor.systemCyan.withAlphaComponent(0.32), forCharacterRange: range)
                }
                highlights = next
                (text as? PlaybackTextView)?.playbackRange = next.current
            }
            if allowScroll && model.follow && (changed || !following), let range = next.current, NSMaxRange(range) <= text.string.utf16.count {
                text.scrollRangeToVisible(range)
            }
            following = model.follow
        }
        func colorize() {
            guard let text = textView, let storage = text.textStorage else { return }
            let range = NSRange(location: 0, length: storage.length)
            storage.beginEditing(); storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            let patterns: [(String, NSColor)] = [(#"\([^)]*\)|\{[^}]*\}|<HS\*[^>]*>"#, .systemTeal), (#"\[[^\]]*\]"#, .systemOrange), (#"[bx]"#, .systemPink), (#"[ABCDE]"#, .systemPurple), (#"\|\|[^\n]*"#, .secondaryLabelColor)]
            for (pattern, color) in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    for match in regex.matches(in: text.string, range: range) { storage.addAttribute(.foregroundColor, value: color, range: match.range) }
                }
            }
            storage.endEditing()
        }
    }
}

/// Playback has its own non-editing cursor, including empty comma cells.
/// It must never steal the user's insertion point, selection or undo history.
@MainActor final class PlaybackTextView: NSTextView {
    weak var model: StudioModel?
    // NSTextView must not register private typing operations into our snapshot history.
    // The responder actions below bridge native Undo/Redo to the persistent model.
    override var undoManager: UndoManager? { nil }
    @objc func undo(_ sender: Any?) { model?.undoVisualEdit() }
    @objc func redo(_ sender: Any?) { model?.redoVisualEdit() }
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) { return model?.sourceUndoManager.canUndo == true }
        if item.action == #selector(redo(_:)) { return model?.sourceUndoManager.canRedo == true }
        return super.validateUserInterfaceItem(item)
    }
    func synchronizeSource() {
        guard let model else { return }
        let coordinator = delegate as? CodeEditor.Coordinator
        coordinator?.updating = true
        coordinator?.clearPlaybackHighlight()
        if string != model.source { string = model.source }
        setSelectedRange(model.selectedRange)
        coordinator?.applyTypography(to: self)
        coordinator?.colorize()
        coordinator?.updating = false
        coordinator?.highlightPlayback()
    }
    var playbackRange: NSRange? { didSet { if oldValue != playbackRange { needsDisplay = true } } }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let range = playbackRange, range.location < string.utf16.count,
              let layout = layoutManager, let container = textContainer else { return }
        layout.ensureLayout(for: container)
        let glyph = layout.glyphIndexForCharacter(at: range.location)
        let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let position = layout.location(forGlyphAt: glyph)
        let rect = NSRect(x: textContainerOrigin.x + line.minX + position.x - 1,
                          y: textContainerOrigin.y + line.minY, width: 2, height: line.height)
        guard rect.intersects(dirtyRect) else { return }
        NSColor.systemCyan.setFill(); rect.fill()
        let cap = NSBezierPath()
        cap.move(to: CGPoint(x: rect.midX, y: rect.minY))
        cap.line(to: CGPoint(x: rect.midX + 5, y: rect.minY))
        cap.line(to: CGPoint(x: rect.midX, y: rect.minY + 5)); cap.close(); cap.fill()
    }
}
