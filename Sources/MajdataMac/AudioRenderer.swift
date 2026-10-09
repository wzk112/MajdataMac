@preconcurrency import AVFoundation
import Foundation
import MajdataCore

struct PreparedAudio: Sendable {
    let url: URL
    let waveform: [Float]
    let startTime: Double
    let duration: Double
    var stems: [AudioChannel: URL] = [:]
    var headroom: Float = 1
}
enum AudioRenderError: LocalizedError {
    case unreadable(String), tooLong, conversion, noEncoder
    var errorDescription: String? {
        switch self {
        case .unreadable(let name): return "无法解码音频：\(name)"
        case .tooLong: return "当前音频超过 30 分钟，无法在内存中混音。"
        case .conversion: return "音频格式转换失败。"
        case .noEncoder: return "此音频格式需要 FFmpeg。请在设置中指定 ffmpeg 可执行文件。"
        }
    }
}
enum AudioRenderer {
    static let rate = 48_000.0
    static func decode(_ url: URL, ffmpeg: String? = nil) throws -> [[Float]] {
        do { return try decodeNative(url) }
        catch {
            if case AudioRenderError.tooLong = error { throw error }
            guard let ffmpeg, FileManager.default.isExecutableFile(atPath: ffmpeg) else {
                if url.pathExtension.lowercased() == "ogg" { throw AudioRenderError.noEncoder }
                throw error
            }
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
            defer { try? FileManager.default.removeItem(at: temporary) }
            let process = Process(), errors = Pipe()
            process.executableURL = URL(fileURLWithPath: ffmpeg)
            process.arguments = ["-nostdin", "-v", "error", "-y", "-i", url.path, "-vn", "-t", "1800.01", "-ar", "48000", "-ac", "2", "-c:a", "pcm_f32le", temporary.path]
            process.standardError = errors; process.standardOutput = FileHandle.nullDevice
            try process.run()
            while process.isRunning {
                if Task.isCancelled { process.terminate(); process.waitUntilExit(); throw CancellationError() }
                Thread.sleep(forTimeInterval: 0.01)
            }
            guard process.terminationStatus == 0 else { throw AudioRenderError.unreadable(url.lastPathComponent) }
            return try decodeNative(temporary)
        }
    }
    private static func decodeNative(_ url: URL) throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { return [[], []] }
        guard Double(file.length) / file.processingFormat.sampleRate < 1800 else { throw AudioRenderError.tooLong }
        guard let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2),
              let converter = AVAudioConverter(from: file.processingFormat, to: format) else { throw AudioRenderError.conversion }
        try file.read(into: source)
        let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * rate / source.format.sampleRate)) + 2048
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw AudioRenderError.conversion }
        var provided = false
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, outStatus in
            if provided { outStatus.pointee = .endOfStream; return nil }
            provided = true; outStatus.pointee = .haveData; return source
        }
        if let conversionError { throw conversionError }
        guard status != .error, let channels = converted.floatChannelData else { throw AudioRenderError.conversion }
        return (0..<2).map { Array(UnsafeBufferPointer(start: channels[$0], count: Int(converted.frameLength))) }
    }
    static func render(chart: ParsedChart, music: URL?, resources: URL, destination: URL, settings: AudioMixSettings,
                       retainStems: Bool = false, ffmpeg: String? = nil, recording: RegionRecording? = nil, opening: RecordingOpening? = nil) throws -> PreparedAudio {
        let start = opening?.startTime ?? min(0, (chart.notes.first?.time ?? 0) - 1)
        // Allocate for the decoded music, not just E / the last note. BGM starts at
        // chart time zero; negative pre-roll is additional time, never a music trim.
        let musicSamples = try music.map { try decode($0, ffmpeg: ffmpeg) }
        try Task.checkCancellation()
        let end = max(chart.duration + 2, Double(musicSamples?[0].count ?? 0) / rate,
                      AllPerfectOutro(chart: chart, recording: recording)?.endTime ?? 0)
        let duration = max(2, end - start)
        guard duration <= 1800 else { throw AudioRenderError.tooLong }
        let frames = Int(ceil(duration * rate))
        let stemDirectory = destination.deletingPathExtension().appendingPathExtension("stems")
        try FileManager.default.createDirectory(at: stemDirectory, withIntermediateDirectories: true)
        var completed = false
        defer { if !retainStems || !completed { try? FileManager.default.removeItem(at: stemDirectory) } }
        let schedule = SoundSchedule.events(chart, metronome: settings.metronome, recording: recording, opening: opening)
        var mixed = [[Float]](repeating: [Float](repeating: 0, count: frames), count: 2)
        var bound = mixed
        var stems: [AudioChannel: URL] = [:]
        for channel in AudioChannel.allCases {
            try Task.checkCancellation()
            let events = schedule.filter { $0.channel == channel }
            guard channel == .bgm || !events.isEmpty else { continue }
            var samples = [[Float]](repeating: [Float](repeating: 0, count: frames), count: 2)
            func mix(_ input: [[Float]], at time: Double, duration limit: Double? = nil) {
                let offset = Int(((time - start) * rate).rounded())
                let count = min(input[0].count, limit.flatMap { $0.isFinite ? max(0, Int(($0 * rate).rounded())) : nil } ?? input[0].count)
                let lo = max(0, -offset), hi = min(count, frames - offset)
                guard hi > lo else { return }
                for ch in 0..<2 { for i in lo..<hi { samples[ch][offset + i] += input[ch][i] } }
            }
            if channel == .bgm, let musicSamples { mix(musicSamples, at: 0) }
            // Restarting the same sample truncates its previous tail, as in the source BASS streams.
            for (sound, group) in Dictionary(grouping: events, by: \.sound) {
                let file = resources.appendingPathComponent("SFX").appendingPathComponent(sound + ".wav")
                guard FileManager.default.fileExists(atPath: file.path) else { throw AudioRenderError.unreadable(file.lastPathComponent) }
                let input = try decode(file)
                let sorted = group.sorted { $0.time < $1.time }
                for (i, event) in sorted.enumerated() {
                    let next = i + 1 < sorted.count ? sorted[i + 1].time - event.time : .infinity
                    mix(input, at: event.time, duration: min(event.duration ?? .infinity, next))
                }
            }
            let url = stemDirectory.appendingPathComponent(channel.rawValue + ".wav")
            try write(samples, to: url, floatingPoint: true)
            stems[channel] = url
            for ch in 0..<2 { for i in 0..<frames {
                mixed[ch][i] += samples[ch][i] * settings.gain(channel)
                bound[ch][i] += abs(samples[ch][i])
            } }
        }
        // A fixed bound over every channel at 100% keeps live volume changes and exports consistent.
        // It never renormalizes a quiet or muted mix back to full volume.
        let maximum = max(bound[0].max() ?? 1, bound[1].max() ?? 1, 1)
        let headroom: Float = 0.98 / maximum
        var waveform: [Float] = [], bucketPeak: Float = 0
        let bucketSize = max(1, frames / 4096)
        for i in 0..<frames {
            for ch in 0..<2 { mixed[ch][i] *= headroom }
            bucketPeak = max(bucketPeak, abs(mixed[0][i]), abs(mixed[1][i]))
            if (i + 1) % bucketSize == 0 { waveform.append(bucketPeak); bucketPeak = 0 }
        }
        try write(mixed, to: destination, floatingPoint: false)
        completed = true
        return PreparedAudio(url: destination, waveform: waveform, startTime: start, duration: duration,
                             stems: retainStems ? stems : [:], headroom: headroom)
    }
    private static func write(_ samples: [[Float]], to url: URL, floatingPoint: Bool) throws {
        let frames = samples[0].count
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else { throw AudioRenderError.conversion }
        buffer.frameLength = AVAudioFrameCount(frames)
        for ch in 0..<2 { samples[ch].withUnsafeBufferPointer { pointer in channels[ch].update(from: pointer.baseAddress!, count: frames) } }
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: floatingPoint ? 32 : 16,
            AVLinearPCMIsFloatKey: floatingPoint, AVLinearPCMIsBigEndianKey: false])
        try file.write(from: buffer)
    }
}
