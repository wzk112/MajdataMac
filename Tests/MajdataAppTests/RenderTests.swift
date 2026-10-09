import Testing
import SwiftUI
import Metal
import AVFoundation
import MajdataCore
@testable import MajdataMac

@Suite(.serialized) struct RenderTests {
    @Test @MainActor func importedSourceGeometryAndAnimations() throws {
        let art = OriginalArt.shared
        #expect(art.manifest.slides.count == 42)
        #expect(art.manifest.sourceCommit == "5786452b45647eb15229ad601dab959288c0d88a")
        for (name, nodes) in art.manifest.slides {
            #expect(nodes.count >= 2)
            #expect(nodes.last!.name.hasPrefix("Just"))
            // Upstream v1 has an extra bar beyond the final sensor; it is removed at completion.
            #expect((art.manifest.areaSteps[name]?.last ?? 0) > 0)
            #expect((art.manifest.areaSteps[name]?.last ?? 0) <= nodes.count - 1)
        }
        for shape in ["-", "^", ">", "<", "v", "p", "q", "pp", "qq", "s", "z", "V", "w"] {
            for start in 1...8 { for end in 1...8 {
                let segment = SlideSegment(shape: shape, start: start, end: end, turn: (start + 5) % 8 + 1)
                guard let key = SlideGeometry.key(for: segment), key.name != "wifi" else { continue }
                let imported = try #require(art.manifest.slides[key.name])
                let points = SlideGeometry.points(for: segment)
                #expect(imported.count + 1 == points.count)
                for (i, node) in imported.dropLast().enumerated() {
                    let p = SlideGeometry.rotated(Point(key.mirror ? -node.x : node.x, -node.y), angle: Double(start - (key.mirror ? 0 : 1)) * .pi / 4)
                    #expect(abs(p.x / 4.8 - points[i + 1].x) < 0.00001)
                    #expect(abs(p.y / 4.8 - points[i + 1].y) < 0.00001)
                }
            } }
        }
        let fade = try #require(art.manifest.animations["SlideFadeIn"])
        #expect(abs(fade.value("Slide_01:m_Color.a", at: 0.1, default: -1) - 0.275) < 0.0001)
        let shine = try #require(art.manifest.animations["HoldShine"])
        #expect(abs(shine.value(":material._Brightness", at: 0.13333334, default: -1) - 1.5) < 0.0001)
        let metal = try #require(MTLCreateSystemDefaultDevice())
        let library = try metal.makeLibrary(URL: StudioModel.resourceURL.appendingPathComponent("MajdataShaders.metallib"))
        #expect(library.functionNames.contains("hanabi"))
    }
    @Test func timingAndEachRegressions() {
        let speed = NoteMotion.velocity(setting: 7.5)
        #expect(speed > 12 && speed < 13)
        #expect(NoteMotion.scale(distance: -1.275) == 0)
        #expect(abs(NoteMotion.scale(distance: 1.225) - 1) < 0.00001)
        #expect(NoteMotion.touchDistance(delta: 0, speed: 7.5) == 0)
        #expect(NoteMotion.hiddenBars(progress: 0.49, steps: [0,3,6,11,15,19]) == 6)
        #expect(NoteMotion.hiddenBars(progress: 1, steps: [0,1,4,6,11]) == 11)
        let mixed = SimaiParser.parse("(120)1-5[4:1]/3,1-5[4:1]*^3[4:1],2$$,E")
        #expect(!mixed.hasErrors)
        #expect(mixed.notes.first(where: { $0.kind == .slide })?.isEach == false)
        let eachSlides = mixed.notes.filter { $0.kind == .slide && $0.time == 0.5 }
        #expect(eachSlides.count == 2 && eachSlides.allSatisfy { $0.isEach })
        #expect(mixed.notes.last?.starSpin == 2)
        #expect(abs(hypot(SlideGeometry.touch("B", lane: 1).x, SlideGeometry.touch("B", lane: 1).y) * 4.8 - 2.3) < 0.00001)
    }
    @Test @MainActor func visualProofFrames() throws {
        guard let folder = ProcessInfo.processInfo.environment["MAJDATA_RENDER_PROOF"] else { return }
        let root = URL(fileURLWithPath: folder)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cases: [(String, String, Double)] = [
            ("01-ring-notes", "(120){4},,1/2x/3b/4h[4:4]/5h[4:4]b/6h[4:4]x/7h[4:4]/8h[4:4],E", 0.93),
            ("02-touch-entry", "(120){4},,A1/B3/E6/C/D8,Ch[4:2],E", 0.8),
            ("03-touchhold", "(120){4},,Ch[4:4],E", 1.7),
            ("04-slide-arrows", "(120){4},,1p5[2:1]/5q1[2:1],E", 1.35),
            ("05-wifi", "(120){4},,1w5[2:1],E", 1.7),
            ("06-critical", "(120){4},,1b/3/5b/7,E", 1.10),
            ("07-firework", "(120){4},,Cf,E", 1.22),
            ("08-slide-judge", "(120){4},,1-5[2:1]/5^8[2:1],E", 2.58)
        ]
        for (name, source, time) in cases {
            let chart = SimaiParser.parse(source)
            #expect(!chart.hasErrors, "\(name): \(chart.diagnostics)")
            let renderer = ImageRenderer(content: StageView(chart: chart, time: time, style: StageStyle(center: "NONE")).frame(width: 900, height: 900))
            renderer.scale = 1; renderer.isOpaque = true
            let image = try #require(renderer.cgImage)
            let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try data.write(to: root.appendingPathComponent(name + ".png"))
        }
    }
    @Test @MainActor func intervalIndexMatchesFullScanAfterSeeking() {
        var chart = ParsedChart()
        chart.notes = (0..<20_000).map { i in
            Note(id: i, kind: i % 30 == 0 ? .hold : .tap, lane: i % 8 + 1, time: Double(i) * 0.06,
                 duration: i % 30 == 0 ? 200 : 0, speed: i % 7 == 0 ? 0.2 : 1)
        }
        let speed = NoteMotion.velocity(setting: 7.5)
        let timeline = RenderTimeline.prepared(chart, speed: 7.5, touch: 7.5)
        for time in [900.12, 0, 18.5, 200, -2, 1199, 50] {
            let expected = chart.notes.filter { $0.time - 6.075 / (speed * $0.speed) <= time && $0.endTime + 1.4 >= time }
            #expect(timeline.visible(at: time).map(\.id) == expected.map(\.id))
            #expect(timeline.score(at: time).combo == chart.notes.filter { $0.judgeTime <= time }.count)
        }
        let before = chart.renderRevision
        chart.notes[0].time = 9999
        #expect(chart.renderRevision != before)
        #expect(RenderTimeline.prepared(chart, speed: 7.5, touch: 7.5) !== timeline)
        let start = ContinuousClock.now
        for i in 0..<600 { _ = timeline.visible(at: 500 + Double(i) / 60); _ = timeline.score(at: 500 + Double(i) / 60) }
        print("20,000-note interval query, 600 frames: \(start.duration(to: .now))")
    }
    @Test @MainActor func demonstrationMovie() async throws {
        guard let folder = ProcessInfo.processInfo.environment["MAJDATA_PROOF_MOVIE"] else { return }
        let root = URL(fileURLWithPath: folder)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let resources = StudioModel.resourceURL
        let document = ChartDocument(text: try String(contentsOf: resources.appendingPathComponent("Demo/maidata.txt"), encoding: .utf8))
        let chart = SimaiParser.parse(document.chart(4), offset: document.offset)
        let audio = try AudioRenderer.render(chart: chart, music: resources.appendingPathComponent("Demo/track.wav"), resources: resources,
                                             destination: root.appendingPathComponent("demo.wav"), settings: AudioMixSettings())
        let silent = root.appendingPathComponent("demo-silent.mp4")
        try await VideoExporter.render(chart: chart, audio: audio, video: nil, style: StageStyle(), width: 1080, height: 1080, destination: silent) { _ in }
        let m4a = root.appendingPathComponent("demo.m4a")
        let encoder = try #require(AVAssetExportSession(asset: AVURLAsset(url: audio.url), presetName: AVAssetExportPresetAppleM4A))
        try await encoder.export(to: m4a, as: .m4a)
        try await VideoExporter.mux(video: silent, audio: m4a, output: root.appendingPathComponent("Majdata-render-demo.mp4"))
        try FileManager.default.removeItem(at: silent)
        try FileManager.default.removeItem(at: m4a)
        try FileManager.default.removeItem(at: audio.url)
    }
}
