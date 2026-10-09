import Foundation
import AVFoundation
import Darwin
import MajdataCore

enum AudioChannel: String, Codable, CaseIterable, Identifiable, Sendable {
    case bgm, answer, judge, slide, `break`, breakSlide, ex, touch, hanabi
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bgm: "音乐 / BGM"
        case .answer: "Answer 正解音"
        case .judge: "Tap / Hold 判定音"
        case .slide: "Slide 启动音"
        case .break: "Break 判定 / 欢呼"
        case .breakSlide: "Break Slide 完成音"
        case .ex: "EX 判定音"
        case .touch: "Touch 判定音"
        case .hanabi: "烟花 / TouchHold 持续音"
        }
    }
}

struct AudioMixSettings: Codable, Equatable, Sendable {
    var master: Float = 1
    var levels: [AudioChannel: Float] = Dictionary(uniqueKeysWithValues: AudioChannel.allCases.map { ($0, 0.7) })
    var muted: Set<AudioChannel> = []
    var solo: Set<AudioChannel> = []
    var metronome = false
    var bgm: Float { get { level(.bgm) } set { levels[.bgm] = newValue } }
    var answer: Float { get { level(.answer) } set { levels[.answer] = newValue } }
    func level(_ channel: AudioChannel) -> Float { min(1, max(0, levels[channel] ?? 0.7)) }
    func gain(_ channel: AudioChannel) -> Float {
        guard !muted.contains(channel), solo.isEmpty || solo.contains(channel) else { return 0 }
        return level(channel) * min(1, max(0, master))
    }
    static func load(_ key: String = "audioMix.v3") -> Self {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }
    func save(_ key: String = "audioMix.v3") { if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: key) } }
}

struct SoundEvent: Equatable, Sendable {
    var sound: String
    var channel: AudioChannel
    var time: Double
    var duration: Double? = nil
}

enum SoundSchedule {
    /// Mirrors MajdataEdit/SoundEffect.cs, including releases and separate slide launch/completion sounds.
    static func events(_ chart: ParsedChart, metronome: Bool, recording: RegionRecording? = nil, opening: RecordingOpening? = nil) -> [SoundEvent] {
        var result: [SoundEvent] = []
        func add(_ sound: String, _ channel: AudioChannel, _ time: Double, duration: Double? = nil) {
            result.append(SoundEvent(sound: sound, channel: channel, time: time, duration: duration))
        }
        for note in chart.notes {
            let head = recording?.heads[note.id], judged = recording?.results[note.id]
            let hit = recording == nil || head != nil
            let success = recording == nil || (judged != nil && judged?.grade != .miss)
            let headTime = head?.time ?? note.time, endTime = judged?.time ?? note.endTime
            switch note.kind {
            case .tap, .hold:
                add("answer", .answer, note.time)
                if hit && note.isBreak { add("judge_break", .break, headTime); add("break", .break, headTime) }
                if hit && note.isEX { add("judge_ex", .ex, headTime) }
                if hit && !note.isBreak && !note.isEX { add("judge", .judge, headTime) }
                if note.kind == .hold && note.duration > 0 {
                    add("answer", .answer, note.endTime)
                    if success && !note.isBreak && !note.isEX { add("judge", .judge, endTime) }
                }
            case .slide:
                if let start = note.segments.first?.startTime { add(note.isBreak ? "break_slide_start" : "slide", .slide, start) }
                if success && note.isBreak { add("judge_break_slide", .breakSlide, endTime); add("break_slide", .breakSlide, endTime) }
            case .touch, .touchHold:
                add("answer", .answer, note.time); if hit { add("touch", .touch, headTime) }
                if note.kind == .touchHold && note.duration > 0 {
                    if hit { add("touchHold_riser", .hanabi, headTime, duration: max(0, note.endTime - headTime)) }
                    add("answer", .answer, note.endTime)
                }
                if success && note.isFirework { add("hanabi", .hanabi, endTime) }
            }
        }
        if metronome {
            // Generate beats independently of chart subdivision, restarting at tempo changes.
            var changes: [(Double, Double)] = []
            for point in chart.timings where changes.last?.1 != point.bpm { changes.append((point.time, point.bpm)) }
            for (i, tempo) in changes.enumerated() where tempo.1 > 0 {
                let end = i + 1 < changes.count ? changes[i + 1].0 : chart.duration
                var time = tempo.0
                while time < end - 0.000001 { add("clock", .bgm, time); time += 60 / tempo.1 }
            }
        }
        if let opening {
            add("track_start", .bgm, opening.startTime, duration: 5)
            for time in opening.clockTimes { add("clock", .bgm, time) }
        }
        // One upstream stream per sample. Simultaneous EACH notes trigger it only once.
        var last: [String: Double] = [:]
        return result.sorted { $0.time < $1.time }.filter { event in
            if let t = last[event.sound], abs(t - event.time) < 0.001 { return false }
            last[event.sound] = event.time; return true
        }
    }
}

private final class AudioLevels: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [AudioChannel: Float] = [:]
    func set(_ channel: AudioChannel, _ value: Float) { lock.withLock { values[channel] = value } }
    func get(_ channel: AudioChannel) -> Float { lock.withLock { values[channel] ?? 0 } }
}

@MainActor final class AudioPlayback {
    private(set) var channels: [AudioChannel: AVAudioPlayerNode] = [:]
    private var files: [AudioChannel: AVAudioFile] = [:]
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private let pitch = AVAudioUnitTimePitch()
    private let levels = AudioLevels()
    private var offset = 0.0
    private var pausedTime = 0.0
    private var lastClockPosition = 0.0
    private var running = false
    private var configurationObserver: NSObjectProtocol?
    var onConfigurationChange: (() -> Void)?
    private let duration: Double
    let headroom: Float
    var outputVolume: Float { engine.mainMixerNode.outputVolume }
    var engineIsRunning: Bool { engine.isRunning }
    var outputDeviceID: UInt32? { engine.outputNode.audioUnit.flatMap(AudioOutputRouting.currentID) }
    var outputDevice: AudioOutputDevice? {
        outputDeviceID.flatMap(AudioOutputRouting.device)
    }
    var reference: AVAudioPlayerNode { channels[.bgm]! }
    var currentTime: Double {
        guard running, engine.isRunning, let render = reference.lastRenderTime, let player = reference.playerTime(forNodeTime: render) else {
            return running ? lastClockPosition : pausedTime
        }
        // Smooth the block-stepped audio timestamp without replacing the audio master clock.
        let position = AudioPresentationClock.position(offset: offset, sampleTime: player.sampleTime, sampleRate: player.sampleRate,
            renderHostSeconds: render.isHostTimeValid ? AVAudioTime.seconds(forHostTime: render.hostTime) : nil,
            hostSeconds: AVAudioTime.seconds(forHostTime: mach_absolute_time()), rate: Double(rate), duration: duration)
        // Rate changes can briefly leave one block from the previous rate in the graph.
        // Re-anchor to audio as it catches up without ever moving the visible playhead backwards.
        lastClockPosition = max(lastClockPosition, position)
        return lastClockPosition
    }
    var isPlaying: Bool { running && currentTime < duration - 1.0 / AudioRenderer.rate }
    var rate: Float = 1 { didSet { pitch.rate = rate } }
    var channelTimes: [Double] {
        guard let render = reference.lastRenderTime else { return [] }
        return channels.values.compactMap { node in
            guard let time = node.playerTime(forNodeTime: render) else { return nil }
            return Double(time.sampleTime) / time.sampleRate
        }
    }
    init(_ audio: PreparedAudio, settings: AudioMixSettings, audioOutputEnabled: Bool = true, outputUID: String = "") throws {
        duration = audio.duration; headroom = audio.headroom
        guard let device = AudioOutputRouting.resolve(preferredUID: outputUID, devices: AudioOutputRouting.devices,
                                                      defaultID: AudioOutputRouting.defaultID),
              let output = engine.outputNode.audioUnit else { throw AudioOutputRouting.Failure.unavailable }
        // Bind this engine only; never change the user's global Core Audio defaults.
        try AudioOutputRouting.bind(output, to: device.id)
        let format = AVAudioFormat(standardFormatWithSampleRate: AudioRenderer.rate, channels: 2)!
        engine.attach(mixer); engine.attach(pitch)
        engine.connect(mixer, to: pitch, format: format)
        engine.connect(pitch, to: engine.mainMixerNode, format: format)
        // Tests exercise the real graph and clock without sending sound to speakers.
        engine.mainMixerNode.outputVolume = audioOutputEnabled ? 1 : 0
        for (channel, url) in audio.stems {
            let node = AVAudioPlayerNode()
            let file = try AVAudioFile(forReading: url)
            engine.attach(node); engine.connect(node, to: mixer, format: file.processingFormat)
            files[channel] = file; channels[channel] = node
            let levels = levels
            node.installTap(onBus: 0, bufferSize: 1024, format: file.processingFormat) { @Sendable buffer, _ in
                guard let data = buffer.floatChannelData else { return }
                var peak: Float = 0
                for ch in 0..<Int(buffer.format.channelCount) {
                    for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[ch][i])) }
                }
                levels.set(channel, peak)
            }
        }
        engine.prepare(); try engine.start()
        guard AudioOutputRouting.currentID(output) == device.id else { engine.stop(); throw AudioOutputRouting.Failure.wrongDevice }
        apply(settings)
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onConfigurationChange?() }
        }
    }
    isolated deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        engine.stop()
    }
    func shutdown() {
        onConfigurationChange = nil
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        pause(); engine.stop()
    }
    func apply(_ settings: AudioMixSettings) {
        for (channel, node) in channels { node.volume = settings.gain(channel) * headroom }
    }
    func play(at time: Double) throws {
        pause(); offset = min(duration, max(0, time)); pausedTime = offset; lastClockPosition = offset
        if !engine.isRunning { try engine.start() }
        let startFrame = AVAudioFramePosition((offset * AudioRenderer.rate).rounded())
        for (channel, node) in channels {
            guard let file = files[channel], startFrame < file.length else { continue }
            node.scheduleSegment(file, startingFrame: startFrame, frameCount: AVAudioFrameCount(file.length - startFrame), at: nil)
        }
        let latest = channels.values.compactMap { $0.lastRenderTime?.sampleTime }.max() ?? 0
        let start = AVAudioTime(sampleTime: latest + 4800, atRate: AudioRenderer.rate)
        for node in channels.values { node.play(at: start) }
        running = true
    }
    func pause() {
        if running { pausedTime = currentTime }
        running = false
        for node in channels.values { node.stop() }
    }
    func seek(_ time: Double, playing: Bool) throws {
        if playing { try play(at: time) }
        else { pause(); pausedTime = max(0, min(duration, time)) }
    }
    func meter(_ channel: AudioChannel) -> Float { min(1, levels.get(channel) * (channels[channel]?.volume ?? 0)) }
}
