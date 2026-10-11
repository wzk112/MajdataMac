import Testing
import SwiftUI
import CoreText
import AVFoundation
import Vision
import MajdataCore
@testable import MajdataMac

@Suite(.serialized) struct ChineseDemoTests {
    @Test @MainActor func bundledFontCoversChineseWithoutFallback() {
        let font = HarmonyOSFont.coreText(size: 24)
        let characters = Array("晨光序曲中文显示测试作曲者谱师星河简体繁體日本語「」×｜".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        #expect(CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count))
        #expect(glyphs.allSatisfy { $0 != 0 })
        #expect((CTFontCopyPostScriptName(font) as String).contains("HarmonyOS"))
        let path = StudioModel.resourceURL.appendingPathComponent("RecordingIntro/Minimoon.ttf") as CFURL
        if let provider = CGDataProvider(url: path), let graphicsFont = CGFont(provider) {
            let original = CTFontCreateWithGraphicsFont(graphicsFont, 24, nil, nil)
            var oldGlyphs = [CGGlyph](repeating: 0, count: characters.count)
            #expect(!CTFontGetGlyphsForCharacters(original, characters, &oldGlyphs, characters.count))
        }
    }

    @Test @MainActor func chineseDemoLoadsAndExports() async throws {
        let resources = StudioModel.resourceURL
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = resources.appendingPathComponent("Demo/maidata.txt")
        let decoded = try ChartTextCodec.decode(Data(contentsOf: file))
        #expect(decoded.encoding == "UTF-8")
        let model = StudioModel(audioOutputEnabled: false)
        model.load(file)
        defer { model.invalidateAudio() }
        #expect(model.document.title == "晨光序曲｜中文显示测试")
        #expect(model.stageInfo.designer == "测试谱师「星河」× 中文验证")
        #expect(!model.chart.hasErrors && model.chart.notes.count >= 40)
        #expect(Set(model.chart.notes.map(\.kind)) == Set(NoteKind.allCases))
        let info = model.stageInfo, chart = model.chart
        let opening = RecordingOpening(chart: chart, clockCount: model.document["clock_count"])
        let mix = try AudioRenderer.render(chart: chart, music: resources.appendingPathComponent("Demo/track.wav"), resources: resources,
            destination: root.appendingPathComponent("mix.wav"), settings: AudioMixSettings(), opening: opening)
        var proof: URL?
        if let folder = ProcessInfo.processInfo.environment["MAJDATA_CHINESE_DEMO_PROOF"] {
            proof = URL(fileURLWithPath: folder)
            try FileManager.default.createDirectory(at: proof!, withIntermediateDirectories: true)
            for name in ["maidata.txt", "track.wav"] {
                let destination = proof!.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.copyItem(at: resources.appendingPathComponent("Demo/" + name), to: destination)
            }
        }
        for codec in [VideoCodec.h264, .hevc] {
            let silent = root.appendingPathComponent("silent-\(codec).mp4"), final = root.appendingPathComponent("中文测试-\(codec).mp4")
            try await VideoExporter.render(chart: chart, audio: mix, video: nil, style: StageStyle(), width: 1920, height: 1080,
                destination: silent, info: info, intro: RecordingIntro(opening: opening, info: info), codec: codec) { _ in }
            try await VideoExporter.mux(video: silent, audio: mix.url, output: final)
            let asset = AVURLAsset(url: final)
            #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
            #expect(abs(try await asset.load(.duration).seconds - mix.duration) < 1.0 / 60)
            let generator = AVAssetImageGenerator(asset: asset)
            let image = try await generator.image(at: CMTime(seconds: 2, preferredTimescale: 60)).image
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            try VNImageRequestHandler(cgImage: image).perform([request])
            let recognized = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined().replacingOccurrences(of: " ", with: "")
            #expect(recognized.contains("晨光序曲"), "\(codec): \(recognized)")
            #expect(recognized.contains("测试作曲者"), "\(codec): \(recognized)")
            if let proof {
                let destination = proof.appendingPathComponent(final.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.copyItem(at: final, to: destination)
                try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                    .write(to: proof.appendingPathComponent("中文开场-\(codec).png"))
            }
        }
    }
}
