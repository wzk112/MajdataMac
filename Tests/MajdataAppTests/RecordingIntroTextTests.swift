import Testing
import AppKit
import AVFoundation
import Vision
import MajdataCore
@testable import MajdataMac

@Suite(.serialized) struct RecordingIntroTextTests {
    @MainActor private func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "ja-JP", "en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    @Test @MainActor func unicodeLabelsRemainReadable() throws {
        let info = StageChartInfo(title: "中文曲名 测试", artist: "作曲者 Artist", designer: "谱师 Designer",
                                  difficulty: 5, level: "15.0", notes: 2, breaks: 0)
        let text = try RecordingIntroText(info: info, height: 1080)
        #expect(text.labels.count == 7)
        for (name, expected) in [("TitleText", "中文曲名"), ("ArtistText", "作曲者"), ("DesText", "谱师")] {
            let label = try #require(text.labels["SongDetail/TextWrapper/" + name])
            let context = try #require(CGContext(data: nil, width: label.image.width, height: label.image.height,
                bitsPerComponent: 8, bytesPerRow: label.image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: label.image.width, height: label.image.height))
            context.draw(label.image, in: CGRect(x: 0, y: 0, width: label.image.width, height: label.image.height))
            let result = try recognize(#require(context.makeImage())).replacingOccurrences(of: " ", with: "")
            #expect(result.contains(expected), "OCR of \(name): \(result)")
        }
    }

    @Test(arguments: [VideoCodec.h264, .hevc]) @MainActor func encodedIntroKeepsChineseAndLatinText(_ codec: VideoCodec) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let chart = SimaiParser.parse("(120){4},,,,1,2,E")
        let info = StageChartInfo(title: "中文曲名 测试", artist: "作曲者 Artist", designer: "谱师 Designer",
                                  difficulty: 5, level: "15.0", notes: 2, breaks: 0)
        let opening = RecordingOpening(chart: chart, clockCount: "0")
        let audio = PreparedAudio(url: root.appendingPathComponent("unused.wav"), waveform: [], startTime: -3, duration: 1)
        let output = root.appendingPathComponent("intro.mp4")
        try await VideoExporter.render(chart: chart, audio: audio, video: nil, style: StageStyle(), width: 1080, height: 1080,
            destination: output, intro: RecordingIntro(opening: opening, info: info), codec: codec) { _ in }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for seconds in [0.1, 0.8] {
            let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 60)).image
            let result = try recognize(image).replacingOccurrences(of: " ", with: "")
            #expect(result.contains("中文曲名"), "\(codec) frame \(seconds): \(result)")
            #expect(result.localizedCaseInsensitiveContains("Artist"), "\(codec) frame \(seconds): \(result)")
            if let path = ProcessInfo.processInfo.environment["MAJDATA_INTRO_PROOF"] {
                let folder = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                    .write(to: folder.appendingPathComponent("text-\(codec)-\(seconds).png"))
            }
        }
    }
}
