import Testing
import SwiftUI
import CoreVideo
import AVFoundation
import MajdataCore
@testable import MajdataMac

struct ExportTransferTests {
    @Test(arguments: VideoCodec.allCases) @MainActor func codecsWriteAllFrames(_ codec: VideoCodec) async throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        let audio = PreparedAudio(url: output, waveform: [], startTime: 0.8, duration: 2)
        try await VideoExporter.render(chart: SimaiParser.parse("(120){4},,1b/3h[4:4]/5w1[2:1]/Cf,E"), audio: audio, video: nil,
            style: StageStyle(showSensors: true), width: 720, height: 720, destination: output, codec: codec) { _ in }
        let asset = AVURLAsset(url: output)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let description = try #require(try await track.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(description) == (codec == .hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264))
        let reader = try AVAssetReader(asset: asset)
        let samples = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        samples.alwaysCopiesSampleData = false; reader.add(samples)
        #expect(reader.startReading())
        var frames = 0
        while let sample = samples.copyNextSampleBuffer() {
            if sample.imageBuffer != nil {
                #expect(abs(sample.outputPresentationTimeStamp.seconds - Double(frames)/60) < 0.0001)
                frames += 1
            }
        }
        #expect(reader.status == .completed && frames == 120)
    }
    @Test @MainActor func metalTransferPreservesPixelsAndOrientation() throws {
        let chart = SimaiParser.parse("(120){4},,1b/3h[4:4]/5w1[2:1]/Ch[4:4]/Cf,E")
        let style = StageStyle(showSensors: true)
        let info = StageChartInfo(title: "Export · 渲染", artist: "Artist", designer: "Designer", difficulty: 5, level: "15.0", notes: chart.notes.count, breaks: chart.breakCount)
        let intro = RecordingIntro(opening: RecordingOpening(chart: chart, clockCount: "0"), info: info)
        let renderer = ExportFrameRenderer(chart: chart, style: style, info: info, statistics: StageStatisticsTimeline.prepared(chart, recording: nil), width: 1280, height: 720, intro: intro)
        let cpu = ExportPixelTransfer(useMetal: false), metal = ExportPixelTransfer(useMetal: true)
        func buffer() throws -> CVPixelBuffer {
            var pixel: CVPixelBuffer?
            #expect(CVPixelBufferCreate(nil, 1280, 720, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary, &pixel) == kCVReturnSuccess)
            return try #require(pixel)
        }
        func pixels(_ b: CVPixelBuffer) throws -> [UInt8] {
            CVPixelBufferLockBaseAddress(b, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(b, .readOnly) }
            let bytes = try #require(CVPixelBufferGetBaseAddress(b)).assumingMemoryBound(to: UInt8.self)
            let row = CVPixelBufferGetBytesPerRow(b)
            return (0..<720).flatMap { y in Array(UnsafeBufferPointer(start: bytes + y*row, count: 1280*4)) }
        }
        for time in [-3.0, -0.4, 0.8, 1.22, 1.7, 2.6] {
            let image = try renderer.image(time: time, style: style)
            let reference = try buffer(), actual = try buffer()
            try cpu.copy(image, to: reference); try metal.copy(image, to: actual)
            let a = try pixels(actual), b = try pixels(reference)
            let differences = zip(a,b).enumerated().filter { $0.offset % 4 != 3 }.map { abs(Int($0.element.0)-Int($0.element.1)) }
            let mean = Double(differences.reduce(0,+))/Double(differences.count)
            let large = differences.filter { $0 > 3 }.count
            print("METAL TRANSFER time=\(time) mean=\(mean) max=\(differences.max() ?? 0) large=\(large) image=\(image.bitsPerComponent)/\(image.bitsPerPixel) \(String(describing: image.colorSpace?.name))")
            #expect(mean < 0.1)
            #expect(large == 0)
        }
    }
}
