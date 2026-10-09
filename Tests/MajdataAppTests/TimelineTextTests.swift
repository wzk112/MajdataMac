import Testing
import AppKit
import CoreText
import MajdataCore
@testable import MajdataMac

@Suite(.serialized) struct TimelineTextTests {
    @Test @MainActor func glyphMetricsAndDrawingPreserveLabels() throws {
        for bold in [false, true] {
            let size: CGFloat = bold ? 10 : 9
            let text = TimelineText(size: size, bold: bold)
            let font = CTFontCreateWithName((bold ? "Menlo-Bold" : "Menlo-Regular") as CFString, size, nil)
            for value in ["00:00.000", "−00:02.500", "30:00.000", "BPM 177.6 · {96}", "A8", "C", "-1.25s"] {
                let layout = text.layout(value)
                #expect(layout.glyphs.count == value.utf16.count && layout.glyphs.allSatisfy { $0 != 0 })
                let reference = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [.font: font]))
                #expect(abs(layout.width - CTLineGetTypographicBounds(reference, nil, nil, nil)) < 0.001)
                func makeContext() throws -> CGContext {
                    try #require(CGContext(data: nil, width: 200, height: 24, bitsPerComponent: 8, bytesPerRow: 800,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                }
                let actual = try makeContext(), expected = try makeContext()
                text.draw(layout, at: CGPoint(x: 2, y: 2), color: .black, in: actual)
                expected.translateBy(x: 2, y: 2 + CTFontGetAscent(font)); expected.scaleBy(x: 1, y: -1)
                expected.textMatrix = .identity; CTLineDraw(reference, expected)
                let a = Data(bytes: try #require(actual.data), count: 800 * 24)
                let e = Data(bytes: try #require(expected.data), count: 800 * 24)
                #expect(a == e && a.contains { $0 != 0 })
            }
        }
    }

    @Test @MainActor func repeatedNativeTimelineDrawingAcrossAppearanceAndViewportChanges() throws {
        let model = StudioModel(audioOutputEnabled: false)
        model.source = "(120){16}1/5h[1:4],2,3,4,5,6,7,8,(180){8}A1/B3/C,Ch[1:2],1-5[1:4],E"
        model.chart = SimaiParser.parse(model.source)
        model.timelineZoom = 4
        let view = TimelineCanvas(model: model)
        defer { view.stop() }
        let began = ProcessInfo.processInfo.systemUptime
        let count = Int(ProcessInfo.processInfo.environment["MAJDATA_TIMELINE_STRESS_FRAMES"] ?? "2000") ?? 2000
        var last: NSBitmapImageRep?
        for frame in 0..<count {
            try autoreleasepool {
                if frame.isMultiple(of: 200) {
                    let dark = (frame / 200).isMultiple(of: 2)
                    view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    view.frame = NSRect(x: 0, y: 0, width: dark ? 720 : 420, height: dark ? 160 : 96)
                    model.timelineZoom = dark ? 4 : 1; model.timelineStart = dark ? 1 : model.rangeStart
                    model.timelineBeatsPerBar = dark ? 3 : 4
                    model.selectedRange = NSRange(location: frame % model.source.utf16.count, length: 0)
                }
                let viewport = view.viewport
                model.currentTime = viewport.start + Double(frame % 200) / 200 * viewport.span
                view.update(model)
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.effectiveAppearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: bitmap) }
                #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
                last = bitmap
            }
        }
        // Invalid transient time must not reach integer formatting or font/graphics APIs.
        for time in [Double.nan, .infinity, -.infinity] {
            model.currentTime = time; view.update(model)
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
        }
        if let path = ProcessInfo.processInfo.environment["MAJDATA_TIMELINE_TEXT_PROOF"], let last {
            try #require(last.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        }
        print("TIMELINE TEXT redraws=\(count) seconds=\(ProcessInfo.processInfo.systemUptime - began) backgrounds=\(view.backgroundRenderCount)")
    }
}
