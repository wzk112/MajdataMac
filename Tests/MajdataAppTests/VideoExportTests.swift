import Testing
import SwiftUI
import AVFoundation
import MajdataCore
@testable import MajdataMac

@Suite(.serialized) struct VideoExportTests {
    @Test @MainActor func cancelStopsExportAndReleasesWriter() async throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        let audio = PreparedAudio(url: output, waveform: [], startTime: 0, duration: 30)
        let task = Task {
            try await VideoExporter.render(chart: SimaiParser.parse("(120){4}1,2,3,4,E"), audio: audio, video: nil,
                style: StageStyle(), width: 720, height: 720, destination: output) { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                }
        }
        do { _ = try await task.value; Issue.record("Cancelled export unexpectedly completed") }
        catch is CancellationError { }
    }
    @Test @MainActor func fullRealChartMovie() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["MAJDATA_EXPORT_FULL_CHART"], let destination = env["MAJDATA_EXPORT_FULL_OUTPUT"] else { return }
        let root = URL(fileURLWithPath: path), final = URL(fileURLWithPath: destination)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let document = ChartDocument(text: try String(contentsOf: root.appendingPathComponent("maidata.txt"), encoding: .utf8))
        let chart = SimaiParser.parse(document.chart(5), offset: document.offset)
        let began = ProcessInfo.processInfo.systemUptime
        let audio = try AudioRenderer.render(chart: chart, music: root.appendingPathComponent("track.mp3"), resources: StudioModel.resourceURL,
                                             destination: scratch.appendingPathComponent("mix.wav"), settings: AudioMixSettings())
        let info = StageChartInfo(title: document.title, artist: document.artist, designer: document.designer(5), difficulty: 5,
                                  level: document.level(5), notes: chart.notes.count, breaks: chart.breakCount)
        let style = StageStyle(background: NSImage(contentsOf: root.appendingPathComponent("bg.png")), showSensors: true)
        let silent = scratch.appendingPathComponent("silent.mp4")
        let metrics = try await VideoExporter.render(chart: chart, audio: audio, video: root.appendingPathComponent("pv.mp4"), style: style,
                                                      width: 1920, height: 1080, destination: silent, info: info) { _ in }
        let aac = scratch.appendingPathComponent("mix.m4a")
        let encoder = try #require(AVAssetExportSession(asset: AVURLAsset(url: audio.url), presetName: AVAssetExportPresetAppleM4A))
        try await encoder.export(to: aac, as: .m4a)
        try await VideoExporter.mux(video: silent, audio: aac, output: final)
        let wall = ProcessInfo.processInfo.systemUptime - began
        let asset = AVURLAsset(url: final)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 1920, height: 1080))
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(abs(try await asset.load(.duration).seconds - audio.duration) < 1.0 / 60)
        let reader = try AVAssetReader(asset: asset)
        let frames = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        frames.alwaysCopiesSampleData = false; reader.add(frames)
        #expect(reader.startReading())
        var times: [Double] = []
        while let sample = frames.copyNextSampleBuffer() {
            if sample.imageBuffer != nil { times.append(sample.outputPresentationTimeStamp.seconds) }
        }
        #expect(reader.status == .completed)
        #expect(times.count == Int(ceil(audio.duration * 60)))
        // Decode to apply edit lists and exclude non-image edit-boundary markers.
        let maximumError = times.enumerated().map { abs($0.element - Double($0.offset) / 60) }.max() ?? .infinity
        #expect(maximumError < 0.0001)
        print("FULL EXPORT notes=\(chart.notes.count) duration=\(audio.duration) total=\(wall) metrics=\(metrics)")
    }
    @Test @MainActor func sequentialPVMatchesTimestampsRotationAndEnd() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Majdata-PV-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rotated.mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 96, AVVideoHeightKey: 64])
        input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 64, ty: 0)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 96, kCVPixelBufferHeightKey as String: 64,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<10 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
            var pixel: CVPixelBuffer?
            #expect(CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &pixel) == kCVReturnSuccess)
            let buffer = try #require(pixel)
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = try #require(CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 96, height: 64, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue))
            context.setFillColor(CGColor(red: CGFloat(frame) / 10, green: 0.2, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 96, height: 64))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
            context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1)); context.fill(CGRect(x: 64, y: 32, width: 32, height: 32))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            #expect(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)))
        }
        input.markAsFinished(); await writer.finishWriting()
        #expect(writer.status == .completed)
        let frames = try await ExportVideoFrames(url: url, startTime: 0, maximumSize: CGSize(width: 100, height: 100))
        #expect(try await frames.frame(at: -0.2) == nil)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        func pixels(_ image: CGImage) throws -> [UInt8] {
            let context = try #require(CGContext(data: nil, width: 64, height: 96, bitsPerComponent: 8, bytesPerRow: 64 * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 96))
            return Array(Data(bytes: try #require(context.data), count: 64 * 96 * 4))
        }
        for value in [0, 1, 3, 8] {
            let time = Double(value) / 10
            let actual = try #require(try await frames.frame(at: time))
            #expect(actual.width == 64 && actual.height == 96)
            let expected = try await generator.image(at: CMTime(value: Int64(value), timescale: 10)).image
            let a = try pixels(actual), e = try pixels(expected)
            let mean = Double(zip(a, e).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(a.count)
            print("PV PIXELS time=\(time) mean=\(mean)")
            #expect(mean < 2)
            let repeated = try await frames.frame(at: time + 0.04)
            #expect(repeated === actual)
        }
        #expect(try await frames.frame(at: 1.1) == nil)
        await frames.cancel()
    }
    @Test @MainActor func reusedFramesMatchImageRendererAndUpdateEveryFrame() throws {
        let chart = SimaiParser.parse("(120){4},,1b/3h[4:4]/5w1[2:1]/Ch[4:4]/Cf,E")
        let style = StageStyle(showSensors: true)
        let info = StageChartInfo(title: "Export · 渲染", artist: "Artist", designer: "Designer", difficulty: 5, level: "15", notes: chart.notes.count, breaks: chart.breakCount)
        let statistics = StageStatisticsTimeline.prepared(chart, recording: nil)
        let width = 1280, height = 720
        let optimized = ExportFrameRenderer(chart: chart, style: style, info: info, statistics: statistics, width: width, height: height)
        func context() throws -> CGContext {
            try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue))
        }
        var previous: Data?
        for time in [0.8, 1.22, 1.7, 2.6] {
            let reference = ImageRenderer(content: StagePresentation(info: info, statistics: statistics, time: time) {
                StageView(chart: chart, time: time, style: style)
            }.frame(width: Double(width), height: Double(height)))
            reference.scale = 1; reference.isOpaque = true
            let expected = try context(), actual = try context()
            expected.draw(try #require(reference.cgImage), in: CGRect(x: 0, y: 0, width: width, height: height))
            try optimized.draw(time: time, style: style, into: actual)
            let count = width * height * 4
            let a = Data(bytes: try #require(actual.data), count: count), e = Data(bytes: try #require(expected.data), count: count)
            let differences = zip(a, e).map { abs(Int($0) - Int($1)) }
            let mean = Double(differences.reduce(0, +)) / Double(count)
            print("EXPORT PIXELS time=\(time) mean=\(mean) max=\(differences.max() ?? 0)")
            #expect(mean < 0.1)
            #expect(a != previous)
            previous = a
            if let path = ProcessInfo.processInfo.environment["MAJDATA_EXPORT_PROOF"] {
                let root = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                for (label, image) in [("reference", expected.makeImage()), ("direct", actual.makeImage())] {
                    let cgImage = try #require(image)
                    try #require(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
                        .write(to: root.appendingPathComponent("\(label)-\(time).png"))
                }
            }
        }
    }
    @Test @MainActor func measuredRealChartExport() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["MAJDATA_EXPORT_BENCHMARK"] else { return }
        let root = URL(fileURLWithPath: path)
        let document = ChartDocument(text: try String(contentsOf: root.appendingPathComponent("maidata.txt"), encoding: .utf8))
        let chart = SimaiParser.parse(document.chart(5), offset: document.offset)
        #expect(!chart.hasErrors && chart.notes.count > 1000)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Majdata-Export-Benchmark-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }
        let audio = PreparedAudio(url: output.appendingPathComponent("unused.wav"), waveform: [], startTime: 55, duration: 2)
        let info = StageChartInfo(title: document.title, artist: document.artist, designer: document.designer(5), difficulty: 5,
                                  level: document.level(5), notes: chart.notes.count, breaks: chart.breakCount)
        let style = StageStyle(background: NSImage(contentsOf: root.appendingPathComponent("bg.png")), showSensors: true)
        for size in [(1280, 720), (1920, 1080)] {
            for pv in [false, true] {
                let result = try await VideoExporter.render(chart: chart, audio: audio, video: pv ? root.appendingPathComponent("pv.mp4") : nil,
                    style: style, width: size.0, height: size.1, destination: output.appendingPathComponent(UUID().uuidString + ".mp4"), info: info) { _ in }
                print("EXPORT BENCHMARK \(size.0)x\(size.1) PV=\(pv) \(result)")
                #expect(result.frames == 120)
            }
        }
    }
}
