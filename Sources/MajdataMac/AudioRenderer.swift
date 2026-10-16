@preconcurrency import AVFoundation
import Accelerate
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
/// Decoded PCM of the files a render reads. Every edit re-renders the mix, and decoding a
/// four-minute MP3 each time costs more than mixing it; the effects are tiny and never change.
private final class DecodedAudioCache: @unchecked Sendable {
    static let shared = DecodedAudioCache()
    private struct Entry { var modified: Date?; var size: Int; var samples: [[Float]] }
    private let lock = NSLock()
    private var effects: [String: Entry] = [:]
    private var music: (path: String, entry: Entry)?
    private func stamp(_ url: URL) -> (Date?, Int) {
        // Not URL.resourceValues: a URL value caches them, so a file rewritten at the same path would look unchanged.
        let values = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (values?[.modificationDate] as? Date, (values?[.size] as? NSNumber)?.intValue ?? -1)
    }
    /// Only the most recent long file is kept: a decoded song is about 100 MB.
    func samples(_ url: URL, long: Bool, decode: () throws -> [[Float]]) rethrows -> [[Float]] {
        let (modified, size) = stamp(url), path = url.path
        let cached: Entry? = lock.withLock { long ? (music?.path == path ? music?.entry : nil) : effects[path] }
        if let cached, cached.modified == modified, cached.size == size { return cached.samples }
        let entry = Entry(modified: modified, size: size, samples: try decode())
        lock.withLock { if long { music = (path, entry) } else { effects[path] = entry } }
        return entry.samples
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
        let musicSamples = try music.map { url in try DecodedAudioCache.shared.samples(url, long: true) { try decode(url, ffmpeg: ffmpeg) } }
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
        // Whole-song loops go through vDSP: per-sample Swift loops made a four-minute chart take about a minute to prepare.
        var magnitude = [Float](repeating: 0, count: frames)
        let length = vDSP_Length(frames)
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
                for ch in 0..<2 {
                    input[ch].withUnsafeBufferPointer { source in
                        samples[ch].withUnsafeMutableBufferPointer { target in
                            let out = target.baseAddress! + offset + lo
                            vDSP_vadd(source.baseAddress! + lo, 1, out, 1, out, 1, vDSP_Length(hi - lo))
                        }
                    }
                }
            }
            if channel == .bgm, let musicSamples { mix(musicSamples, at: 0) }
            // Restarting the same sample truncates its previous tail, as in the source BASS streams.
            for (sound, group) in Dictionary(grouping: events, by: \.sound) {
                let file = resources.appendingPathComponent("SFX").appendingPathComponent(sound + ".wav")
                guard FileManager.default.fileExists(atPath: file.path) else { throw AudioRenderError.unreadable(file.lastPathComponent) }
                let input = try DecodedAudioCache.shared.samples(file, long: false) { try decode(file) }
                let sorted = group.sorted { $0.time < $1.time }
                for (i, event) in sorted.enumerated() {
                    let next = i + 1 < sorted.count ? sorted[i + 1].time - event.time : .infinity
                    mix(input, at: event.time, duration: min(event.duration ?? .infinity, next))
                }
            }
            let url = stemDirectory.appendingPathComponent(channel.rawValue + ".wav")
            try write(samples, to: url, floatingPoint: true)
            stems[channel] = url
            var gain = settings.gain(channel)
            for ch in 0..<2 {
                samples[ch].withUnsafeBufferPointer { source in
                    mixed[ch].withUnsafeMutableBufferPointer { vDSP_vsma(source.baseAddress!, 1, &gain, $0.baseAddress!, 1, $0.baseAddress!, 1, length) }
                    magnitude.withUnsafeMutableBufferPointer { scratch in
                        vDSP_vabs(source.baseAddress!, 1, scratch.baseAddress!, 1, length)
                        bound[ch].withUnsafeMutableBufferPointer { vDSP_vadd(scratch.baseAddress!, 1, $0.baseAddress!, 1, $0.baseAddress!, 1, length) }
                    }
                }
            }
        }
        // A fixed bound over every channel at 100% keeps live volume changes and exports consistent.
        // It never renormalizes a quiet or muted mix back to full volume.
        var peaks: [Float] = [0, 0]
        for ch in 0..<2 { bound[ch].withUnsafeBufferPointer { vDSP_maxv($0.baseAddress!, 1, &peaks[ch], length) } }
        let maximum = max(peaks[0], peaks[1], 1)
        var headroom: Float = 0.98 / maximum
        for ch in 0..<2 { mixed[ch].withUnsafeMutableBufferPointer { vDSP_vsmul($0.baseAddress!, 1, &headroom, $0.baseAddress!, 1, length) } }
        var waveform: [Float] = []
        let bucketSize = max(1, frames / 4096)
        waveform.reserveCapacity(frames / bucketSize)
        mixed[0].withUnsafeBufferPointer { left in mixed[1].withUnsafeBufferPointer { right in
            var first = 0
            while first + bucketSize <= frames {
                var l: Float = 0, r: Float = 0
                vDSP_maxmgv(left.baseAddress! + first, 1, &l, vDSP_Length(bucketSize))
                vDSP_maxmgv(right.baseAddress! + first, 1, &r, vDSP_Length(bucketSize))
                waveform.append(max(l, r)); first += bucketSize
            }
        } }
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
