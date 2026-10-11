import SwiftUI
@preconcurrency import AVFoundation
import AppKit
import UniformTypeIdentifiers
import MajdataCore
import VideoToolbox

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
        let resolution = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        resolution.addItems(withTitles: VideoResolution.allCases.map(\.title))
        resolution.selectItem(at: VideoResolution.allCases.firstIndex(of: videoResolution) ?? 1)
        let codecChoice = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        codecChoice.addItems(withTitles: VideoCodec.allCases.map(\.title))
        codecChoice.selectItem(at: VideoCodec.allCases.firstIndex(of: videoCodec) ?? 0)
        let infoSwitch = NSButton(checkboxWithTitle: "16:9 导出包含谱面信息", target: nil, action: nil)
        infoSwitch.state = exportChartInfo ? .on : .off
        let introSwitch = NSButton(checkboxWithTitle: "录制开场（5 秒谱面信息及音效）", target: nil, action: nil)
        introSwitch.state = exportRecordingIntro ? .on : .off
        let fireworks = NSButton(checkboxWithTitle: "烟花特效", target: nil, action: nil)
        let hits = NSButton(checkboxWithTitle: "击打光效", target: nil, action: nil)
        let particles = NSButton(checkboxWithTitle: "长押粒子", target: nil, action: nil)
        fireworks.state = showFireworks ? .on : .off
        hits.state = showHitEffects ? .on : .off
        particles.state = showHoldParticles ? .on : .off
        let options = NSStackView(views: [NSTextField(labelWithString: "视频分辨率 · 60 fps"), resolution, codecChoice, introSwitch, infoSwitch,
                                        NSTextField(labelWithString: "画面特效 · 与播放共用"), fireworks, hits, particles])
        options.orientation = .vertical; options.alignment = .leading; options.spacing = 8
        options.frame = NSRect(x: 0, y: 0, width: 340, height: 270)
        panel.accessoryView = options
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        videoResolution = VideoResolution.allCases[max(0, resolution.indexOfSelectedItem)]
        videoCodec = VideoCodec.allCases[max(0, codecChoice.indexOfSelectedItem)]
        exportRecordingIntro = introSwitch.state == .on
        exportChartInfo = infoSwitch.state == .on
        showFireworks = fireworks.state == .on
        showHitEffects = hits.state == .on
        showHoldParticles = particles.state == .on
        let (width, height) = videoResolution.dimensions
        let codec = videoCodec
        pause()
        let snapshot = chart, music = musicURL, settings = mix, resources = Self.resourceURL, ffmpeg = ffmpegPath, regions = regionJudgement, inputMode = inputMode
        let style = stageStyle
        let info = exportChartInfo ? stageInfo : nil
        let opening = exportRecordingIntro ? RecordingOpening(chart: snapshot, clockCount: document["clock_count"]) : nil
        let intro = opening.map { RecordingIntro(opening: $0, info: stageInfo) }
        let video = videoURL, workspace = cacheDirectory.appendingPathComponent("Export-" + UUID().uuidString)
        exportProgress = 0; exportStatus = "准备音频…"
        exportTask = Task {
            defer { exportProgress = nil; exportTask = nil; try? FileManager.default.removeItem(at: workspace) }
            do {
                try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
                let wav = workspace.appendingPathComponent("mix.wav")
                let job = Task.detached {
                    let recording = regions ? try RegionRecording.simulate(snapshot, inputMode: inputMode) : nil
                    let audio = try AudioRenderer.render(chart: snapshot, music: music, resources: resources, destination: wav, settings: settings, ffmpeg: ffmpeg, recording: recording, opening: opening)
                    return (audio, recording)
                }
                let (audio, recording) = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
                var style = style; style.recording = recording
                let silent = workspace.appendingPathComponent("silent.mp4")
                let renderStarted = ProcessInfo.processInfo.systemUptime
                try await VideoExporter.render(chart: snapshot, audio: audio, video: video, style: style, width: width, height: height, destination: silent, info: info, intro: intro, codec: codec) { progress in
                    self.exportProgress = progress * 0.9
                    let elapsed = ProcessInfo.processInfo.systemUptime - renderStarted
                    let speed = elapsed > 0 ? Int(progress * ceil(audio.duration * 60) / elapsed) : 0
                    self.exportStatus = "渲染 \(width) × \(height) · \(codec.name) · \(Int(progress * 100))%" + (elapsed > 1 ? " · \(speed) 帧/秒" : "")
                }
                try Task.checkCancellation(); exportStatus = "合并立体声音轨…"; exportProgress = 0.92
                let final = workspace.appendingPathComponent("final.mp4")
                try await VideoExporter.mux(video: silent, audio: wav, output: final)
                try Task.checkCancellation()
                // Replace only after the complete movie exists. Existing exports survive cancellation/failure.
                try Data(contentsOf: final, options: .mappedIfSafe).write(to: destination, options: .atomic)
                status = "视频导出完成 · \(width) × \(height) · \(codec.name)"; NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch is CancellationError { status = "导出已取消" }
            catch { report(error) }
        }
    }
}
struct VideoRenderMetrics: Sendable {
    var frames = 0
    var elapsed = 0.0
    var background = 0.0
    var drawing = 0.0
    var copying = 0.0
    var encoding = 0.0
    var waiting = 0.0
    var finishing = 0.0
    var framesPerSecond: Double { Double(frames) / max(0.001, elapsed) }
}
@MainActor enum VideoExporter {
    @discardableResult static func render(chart: ParsedChart, audio: PreparedAudio, video: URL?, style: StageStyle, width: Int, height: Int, destination: URL, info: StageChartInfo? = nil, intro: RecordingIntro? = nil, useMetalTransfer: Bool = true, codec: VideoCodec = .h264, progress: @escaping @MainActor (Double) -> Void) async throws -> VideoRenderMetrics {
        let started = ProcessInfo.processInfo.systemUptime
        var metrics = VideoRenderMetrics()
        guard width > 0, height > 0, width <= 4096, height <= 4096, width % 2 == 0, height % 2 == 0 else { throw ExportFailure.failure("导出宽高必须为 2–4096 之间的偶数") }
        guard audio.duration.isFinite, audio.duration > 0, audio.duration <= 1800, audio.startTime.isFinite else { throw ExportFailure.failure("无效的视频导出时长") }
        let background: ExportVideoFrames?
        if let video {
            background = try await ExportVideoFrames(url: video, startTime: audio.startTime, maximumSize: CGSize(width: width, height: height))
        } else { background = nil }
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        let bitrate = min(50_000_000, max(8_000_000, Int(Double(width * height) / (1920 * 1080) * 12_000_000)))
        let compression: [String: Any] = [AVVideoAverageBitRateKey: bitrate, AVVideoExpectedSourceFrameRateKey: 60]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: codec.avCodec, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoEncoderSpecificationKey: [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true], AVVideoCompressionPropertiesKey: compression])
        input.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferIOSurfacePropertiesKey as String: [:], kCVPixelBufferMetalCompatibilityKey as String: true, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        guard writer.canAdd(input) else { throw ExportFailure.failure("编码器不支持该视频设置") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ExportFailure.failure("视频写入失败") }
        writer.startSession(atSourceTime: .zero)
        let statistics = info == nil ? nil : StageStatisticsTimeline.prepared(chart, recording: style.recording)
        let transfer = ExportPixelTransfer(useMetal: useMetalTransfer)
        let count = Int(ceil(audio.duration * 60))
        do {
            let renderer = try ExportFrameRenderer(chart: chart, style: style, info: info, statistics: statistics, width: width, height: height, intro: intro)
            for frame in 0..<count {
                try Task.checkCancellation()
                var measured = ProcessInfo.processInfo.systemUptime
                while !input.isReadyForMoreMediaData {
                    if writer.status != .writing { throw writer.error ?? ExportFailure.failure("视频编码器退出") }
                    try await Task.sleep(for: .milliseconds(2))
                }
                metrics.waiting += ProcessInfo.processInfo.systemUptime - measured
                let time = audio.startTime + Double(frame) / 60
                var frameStyle = style
                measured = ProcessInfo.processInfo.systemUptime
                if let background, let image = try await background.frame(at: time) { frameStyle.background = NSImage(cgImage: image, size: .zero) }
                metrics.background += ProcessInfo.processInfo.systemUptime - measured
                try autoreleasepool {
                    measured = ProcessInfo.processInfo.systemUptime
                    var buffer: CVPixelBuffer?
                    guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw ExportFailure.failure("无法分配视频帧") }
                    metrics.copying += ProcessInfo.processInfo.systemUptime - measured
                    measured = ProcessInfo.processInfo.systemUptime
                    let image = try renderer.image(time: time, style: frameStyle)
                    try transfer.copy(image, to: buffer)
                    metrics.drawing += ProcessInfo.processInfo.systemUptime - measured
                    measured = ProcessInfo.processInfo.systemUptime
                    guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 60)) else { throw writer.error ?? ExportFailure.failure("无法写入视频帧") }
                    metrics.encoding += ProcessInfo.processInfo.systemUptime - measured
                }
                if frame % 12 == 0 { progress(Double(frame) / Double(count)); await Task.yield() }
            }
            let finishing = ProcessInfo.processInfo.systemUptime
            input.markAsFinished(); await writer.finishWriting()
            metrics.finishing = ProcessInfo.processInfo.systemUptime - finishing
            guard writer.status == .completed else { throw writer.error ?? ExportFailure.failure("视频没有完整写入") }
            await background?.cancel()
            progress(1)
            metrics.frames = count
            metrics.elapsed = ProcessInfo.processInfo.systemUptime - started
            return metrics
        } catch { writer.cancelWriting(); await background?.cancel(); throw error }
    }
    static func mux(video: URL, audio: URL, output: URL) async throws {
        let videoAsset = AVURLAsset(url: video), audioAsset = AVURLAsset(url: audio)
        let duration = try await videoAsset.load(.duration)
        guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
              let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let videoFormat = try await sourceVideo.load(.formatDescriptions).first else { throw ExportFailure.failure("导出的媒体轨道缺失") }
        // Encoding to M4A then composition-passthrough to MP4 loses AAC's 2,112
        // priming samples on this system. Encode PCM directly into the final MP4;
        // compressed video packets pass through unchanged (no second video encode).
        let videoReader = try AVAssetReader(asset: videoAsset), audioReader = try AVAssetReader(asset: audioAsset)
        let videoOutput = AVAssetReaderTrackOutput(track: sourceVideo, outputSettings: nil)
        let audioOutput = AVAssetReaderTrackOutput(track: sourceAudio, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false])
        videoOutput.alwaysCopiesSampleData = false; audioOutput.alwaysCopiesSampleData = false
        videoReader.add(videoOutput); audioReader.add(audioOutput)
        audioReader.timeRange = CMTimeRange(start: .zero, duration: min(duration, try await audioAsset.load(.duration)))
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        videoInput.transform = try await sourceVideo.load(.preferredTransform)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 320_000])
        writer.add(videoInput); writer.add(audioInput)
        var complete = false
        defer {
            if !complete {
                videoReader.cancelReading(); audioReader.cancelReading(); writer.cancelWriting()
                try? FileManager.default.removeItem(at: output)
            }
        }
        guard writer.startWriting(), videoReader.startReading(), audioReader.startReading() else {
            throw writer.error ?? videoReader.error ?? audioReader.error ?? ExportFailure.failure("无法启动音视频封装")
        }
        writer.startSession(atSourceTime: .zero)
        var videoDone = false, audioDone = false
        while !videoDone || !audioDone {
            try Task.checkCancellation()
            var advanced = false
            for (reader, readerOutput, input, isVideo) in [(videoReader, videoOutput, videoInput, true), (audioReader, audioOutput, audioInput, false)] {
                guard !(isVideo ? videoDone : audioDone), input.isReadyForMoreMediaData else { continue }
                if let sample = readerOutput.copyNextSampleBuffer() {
                    guard input.append(sample) else { throw writer.error ?? ExportFailure.failure("音视频封装写入失败") }
                } else {
                    guard reader.status == .completed else { throw reader.error ?? ExportFailure.failure("音视频封装读取失败") }
                    input.markAsFinished()
                    if isVideo { videoDone = true } else { audioDone = true }
                }
                advanced = true
            }
            guard writer.status == .writing else { throw writer.error ?? ExportFailure.failure("音视频封装中断") }
            if !advanced { try await Task.sleep(for: .milliseconds(1)) }
        }
        writer.endSession(atSourceTime: duration)
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ExportFailure.failure("音视频封装未完成") }
        complete = true
    }
}
