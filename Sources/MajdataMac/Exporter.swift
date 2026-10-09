import SwiftUI
@preconcurrency import AVFoundation
import AppKit
import UniformTypeIdentifiers
import MajdataCore

enum ExportFailure: LocalizedError {
    case failure(String)
    var errorDescription: String? { if case .failure(let message) = self { return message }; return nil }
}
@MainActor extension StudioModel {
    func exportJSON() {
        chart = SimaiParser.parse(source, offset: document.offset)
        guard !chart.hasErrors else { status = "请先修正语法错误"; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "chart.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(chart).write(to: url, options: .atomic); status = "已导出谱面 JSON" }
        catch { report(error) }
    }
    func exportAudio() {
        chart = SimaiParser.parse(source, offset: document.offset)
        guard !chart.hasErrors, exportTask == nil else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = title + ".wav"; panel.allowedContentTypes = [.wav]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let snapshot = chart, music = musicURL, settings = mix, resources = Self.resourceURL, ffmpeg = ffmpegPath, regions = regionJudgement, inputMode = inputMode
        let temporary = cacheDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        exportProgress = 0; exportStatus = "混合音乐与音效…"
        exportTask = Task {
            defer { exportProgress = nil; exportTask = nil; try? FileManager.default.removeItem(at: temporary) }
            do {
                let job = Task.detached {
                    let recording = regions ? try RegionRecording.simulate(snapshot, inputMode: inputMode) : nil
                    return try AudioRenderer.render(chart: snapshot, music: music, resources: resources, destination: temporary, settings: settings, ffmpeg: ffmpeg, recording: recording)
                }
                _ = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
                try Task.checkCancellation()
                try Data(contentsOf: temporary).write(to: destination, options: .atomic)
                status = "WAV 导出完成"; NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch is CancellationError { status = "导出已取消" }
            catch { report(error) }
        }
    }
    func exportVideo() {
        chart = SimaiParser.parse(source, offset: document.offset)
        guard !chart.hasErrors, exportTask == nil else { status = "请先修正语法错误"; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = title + ".mp4"; panel.allowedContentTypes = [.mpeg4Movie]
        let resolution = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        resolution.addItems(withTitles: ["1080 × 1080 · 60 fps", "1920 × 1080 · 60 fps", "720 × 720 · 60 fps"])
        panel.accessoryView = resolution
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let dimensions: [(Int, Int)] = [(1080, 1080), (1920, 1080), (720, 720)]
        let (width, height) = dimensions[max(0, resolution.indexOfSelectedItem)]
        pause()
        let snapshot = chart, music = musicURL, settings = mix, resources = Self.resourceURL, ffmpeg = ffmpegPath, regions = regionJudgement, inputMode = inputMode
        let style = stageStyle
        let video = videoURL, workspace = cacheDirectory.appendingPathComponent("Export-" + UUID().uuidString)
        exportProgress = 0; exportStatus = "准备音频…"
        exportTask = Task {
            defer { exportProgress = nil; exportTask = nil; try? FileManager.default.removeItem(at: workspace) }
            do {
                try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
                let wav = workspace.appendingPathComponent("mix.wav")
                let job = Task.detached {
                    let recording = regions ? try RegionRecording.simulate(snapshot, inputMode: inputMode) : nil
                    let audio = try AudioRenderer.render(chart: snapshot, music: music, resources: resources, destination: wav, settings: settings, ffmpeg: ffmpeg, recording: recording)
                    return (audio, recording)
                }
                let (audio, recording) = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
                var style = style; style.recording = recording
                let silent = workspace.appendingPathComponent("silent.mp4")
                try await VideoExporter.render(chart: snapshot, audio: audio, video: video, style: style, width: width, height: height, destination: silent) { progress in
                    self.exportProgress = progress * 0.9; self.exportStatus = "渲染 \(width) × \(height) · \(Int(progress * 100))%"
                }
                try Task.checkCancellation(); exportStatus = "合并立体声音轨…"; exportProgress = 0.92
                let encodedAudio = workspace.appendingPathComponent("mix.m4a")
                let audioAsset = AVURLAsset(url: wav)
                guard let audioSession = AVAssetExportSession(asset: audioAsset, presetName: AVAssetExportPresetAppleM4A) else { throw ExportFailure.failure("无法创建 AAC 编码器") }
                try await audioSession.export(to: encodedAudio, as: .m4a)
                try Task.checkCancellation()
                let final = workspace.appendingPathComponent("final.mp4")
                try await VideoExporter.mux(video: silent, audio: encodedAudio, output: final)
                try Task.checkCancellation()
                // Replace only after the complete movie exists. Existing exports survive cancellation/failure.
                try Data(contentsOf: final, options: .mappedIfSafe).write(to: destination, options: .atomic)
                status = "视频导出完成 · \(width) × \(height)"; NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch is CancellationError { status = "导出已取消" }
            catch { report(error) }
        }
    }
}
@MainActor enum VideoExporter {
    static func render(chart: ParsedChart, audio: PreparedAudio, video: URL?, style: StageStyle, width: Int, height: Int, destination: URL, progress: (Double) -> Void) async throws {
        guard width % 2 == 0, height % 2 == 0 else { throw ExportFailure.failure("导出宽高必须是偶数") }
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000, AVVideoExpectedSourceFrameRateKey: 60]])
        input.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        guard writer.canAdd(input) else { throw ExportFailure.failure("编码器不支持该视频设置") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ExportFailure.failure("视频写入失败") }
        writer.startSession(atSourceTime: .zero)
        var generator: AVAssetImageGenerator?
        if let video {
            generator = AVAssetImageGenerator(asset: AVURLAsset(url: video)); generator?.appliesPreferredTrackTransform = true
            generator?.maximumSize = CGSize(width: width, height: height)
            generator?.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 60); generator?.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)
        }
        let count = Int(ceil(audio.duration * 60))
        do {
            for frame in 0..<count {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    if writer.status == .failed { throw writer.error ?? ExportFailure.failure("视频编码器退出") }
                    try await Task.sleep(for: .milliseconds(2))
                }
                let time = audio.startTime + Double(frame) / 60
                var frameStyle = style
                if let generator, time >= 0, let image = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 60000)).image { frameStyle.background = NSImage(cgImage: image, size: .zero) }
                try autoreleasepool {
                    let view = StageView(chart: chart, time: time, style: frameStyle).frame(width: Double(width), height: Double(height))
                    let renderer = ImageRenderer(content: view); renderer.scale = 1; renderer.isOpaque = true
                    guard let cgImage = renderer.cgImage else { throw ExportFailure.failure("无法渲染谱面帧") }
                    var buffer: CVPixelBuffer?
                    guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw ExportFailure.failure("无法分配视频帧") }
                    CVPixelBufferLockBaseAddress(buffer, [])
                    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                    guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { throw ExportFailure.failure("无法创建离屏画布") }
                    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                    guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 60)) else { throw writer.error ?? ExportFailure.failure("无法写入视频帧") }
                }
                if frame % 12 == 0 { progress(Double(frame) / Double(count)); await Task.yield() }
            }
            input.markAsFinished(); await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? ExportFailure.failure("视频没有完整写入") }
            progress(1)
        } catch { writer.cancelWriting(); throw error }
    }
    static func mux(video: URL, audio: URL, output: URL) async throws {
        let videoAsset = AVURLAsset(url: video), audioAsset = AVURLAsset(url: audio)
        let composition = AVMutableComposition()
        let duration = try await videoAsset.load(.duration)
        guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
              let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw ExportFailure.failure("导出的媒体轨道缺失") }
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: .zero)
        let audioDuration = try await audioAsset.load(.duration)
        try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: min(duration, audioDuration)), of: sourceAudio, at: .zero)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { throw ExportFailure.failure("无法创建封装器") }
        try await exporter.export(to: output, as: .mp4)
    }
}
