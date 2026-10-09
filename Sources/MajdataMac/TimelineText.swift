import AppKit
import CoreText

/// Timeline labels contain numbers and short symbols, so they don't need attributed-string layout.
/// Keep concrete fonts and glyph metrics outside draw(_:) and avoid the dynamic UI-font attribute
/// conversion that aborted in NSString.size(withAttributes:) on macOS 27.
@MainActor final class TimelineText {
    struct Layout {
        let glyphs: [CGGlyph]
        let positions: [CGPoint]
        let width: CGFloat
    }
    private struct Glyph {
        let id: CGGlyph
        let advance: CGFloat
    }
    private let font: CTFont
    private let ascent: CGFloat
    private var glyphs: [UniChar: Glyph] = [:]
    let height: CGFloat

    init(size: CGFloat, bold: Bool = false) {
        font = CTFontCreateWithName((bold ? "Menlo-Bold" : "Menlo-Regular") as CFString, size, nil)
        ascent = CTFontGetAscent(font)
        height = ceil(ascent + CTFontGetDescent(font) + CTFontGetLeading(font))
        // Warm every character emitted by the playhead, grid and note-area labels before drawing.
        for code in Array(UInt16(32)...UInt16(126)) + [0x00B7, 0x2212] { _ = glyph(for: code) }
    }
    private func glyph(for character: UniChar) -> Glyph {
        if let cached = glyphs[character] { return cached }
        var code = character, id: CGGlyph = 0
        CTFontGetGlyphsForCharacters(font, &code, &id, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &id, &advance, 1)
        let result = Glyph(id: id, advance: advance.width)
        glyphs[character] = result
        return result
    }
    func layout(_ text: String) -> Layout {
        var ids: [CGGlyph] = [], positions: [CGPoint] = []
        ids.reserveCapacity(text.utf16.count); positions.reserveCapacity(text.utf16.count)
        var x: CGFloat = 0
        for character in text.utf16 {
            let item = glyph(for: character)
            ids.append(item.id); positions.append(CGPoint(x: x, y: 0)); x += item.advance
        }
        return Layout(glyphs: ids, positions: positions, width: x)
    }
    func draw(_ layout: Layout, at point: CGPoint, color: NSColor, in context: CGContext) {
        guard point.x.isFinite, point.y.isFinite, !layout.glyphs.isEmpty else { return }
        context.saveGState()
        defer { context.restoreGState() }
        // TimelineCanvas and its cached background use an upper-left origin.
        context.translateBy(x: point.x, y: point.y + ascent)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.setFillColor(color.cgColor)
        CTFontDrawGlyphs(font, layout.glyphs, layout.positions, layout.glyphs.count, context)
    }
}
