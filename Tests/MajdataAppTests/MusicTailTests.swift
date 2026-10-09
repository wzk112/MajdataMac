import Testing
import AVFoundation
import MajdataCore
@testable import MajdataMac

@Suite(.serialized) struct MusicTailTests {
    static func music(at url: URL, seconds: Double = 8) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let count = AVAudioFrameCount(seconds * 48_000)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count))
        buffer.frameLength = count
        for channel in 0..<2 {
            for i in 0..<Int(count) { buffer.floatChannelData![channel][i] = Float(sin(Double(i) * 2 * .pi * 440 / 48_000)) * 0.1 }
        }
        var settings = format.settings; settings[AVLinearPCMIsNonInterleaved] = false
        try AVAudioFile(forWriting: url, settings: settings).write(from: buffer)
    }

    @Test @MainActor func earlyEndMarkerDoesNotTrimMusic() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let music = root.appendingPathComponent("music.wav")
        try Self.music(at: music)
        for offset in [-2.0, 0, 3] {
            let chart = SimaiParser.parse("(120){4}1,E", offset: offset)
            for withOpening in [false, true] {
                let audio = try AudioRenderer.render(chart: chart, music: music, resources: StudioModel.resourceURL,
                    destination: root.appendingPathComponent("mix.wav"), settings: AudioMixSettings(), retainStems: true,
                    opening: withOpening ? RecordingOpening(chart: chart, clockCount: "0") : nil)
                #expect(abs(audio.startTime + audio.duration - 8) < 1.0/48_000)
                let bgm = try AudioRenderer.decode(try #require(audio.stems[.bgm]))
                let lastSecond = Int((7 - audio.startTime) * 48_000)
                #expect(bgm[0].count > lastSecond)
                #expect(bgm[0].suffix(24_000).map(abs).max()! > 0.09)
                // BGM stays anchored at chart time zero, even with negative notes or the OP.
                let at = Int((7 - audio.startTime) * 48_000) + 17
                try #require(bgm[0].count > at)
                #expect(abs(bgm[0][at] - Float(sin(17 * 2 * Double.pi * 440 / 48_000)) * 0.1) < 0.0001)
            }
        }
    }

    @Test @MainActor func transportCanSeekAndPlayPastChartEnd() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let music = root.appendingPathComponent("music.wav")
        try Self.music(at: music)
        let model = StudioModel(audioOutputEnabled: false)
        model.source = "(120){4}1,E"; model.chart = SimaiParser.parse(model.source); model.musicURL = music
        model.prepareAudio(thenPlay: false)
        defer { model.invalidateAudio() }
        for _ in 0..<400 where model.isPreparing { try await Task.sleep(for: .milliseconds(25)) }
        let audio = try #require(model.prepared)
        #expect(model.rangeEnd == audio.startTime + audio.duration)
        #expect(model.rangeEnd == 8)
        model.seek(6); #expect(model.currentTime == 6)
        model.play()
        try await Task.sleep(for: .milliseconds(250)); model.tick()
        #expect(model.isPlaying && model.currentTime > 6.1)
        #expect(model.playback?.outputVolume == 0)
        model.seek(7.8)
        try await Task.sleep(for: .milliseconds(450)); model.tick()
        #expect(!model.isPlaying && model.currentTime == 8)
    }

    @Test @MainActor func exportRetainsTailWithAndWithoutOpening() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let music = root.appendingPathComponent("music.wav")
        try Self.music(at: music)
        let chart = SimaiParser.parse("(120){4}1,E")
        let info = StageChartInfo(title: "Outro test", artist: "", designer: "", difficulty: 4, level: "", notes: 1, breaks: 0)
        for includeOpening in [false, true] {
            let opening = includeOpening ? RecordingOpening(chart: chart, clockCount: "0") : nil
            let mix = try AudioRenderer.render(chart: chart, music: music, resources: StudioModel.resourceURL,
                destination: root.appendingPathComponent("mix-\(includeOpening).wav"), settings: AudioMixSettings(), opening: opening)
            let silent = root.appendingPathComponent("silent-\(includeOpening).mp4")
            let metrics = try await VideoExporter.render(chart: chart, audio: mix, video: nil, style: StageStyle(), width: 320, height: 320,
                destination: silent, intro: opening.map { RecordingIntro(opening: $0, info: info) }, codec: includeOpening ? .hevc : .h264) { _ in }
            #expect(metrics.frames == Int(ceil((8 - mix.startTime) * 60)))
            let aac = root.appendingPathComponent("audio-\(includeOpening).m4a"), final = root.appendingPathComponent("final-\(includeOpening).mp4")
            let encoder = try #require(AVAssetExportSession(asset: AVURLAsset(url: mix.url), presetName: AVAssetExportPresetAppleM4A))
            try await encoder.export(to: aac, as: .m4a)
            // Production uses PCM directly; also keep accepting existing AAC inputs.
            try await VideoExporter.mux(video: silent, audio: includeOpening ? aac : mix.url, output: final)
            let asset = AVURLAsset(url: final)
            #expect(abs(try await asset.load(.duration).seconds - mix.duration) < 1.0/60)
            let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
            let trackRange = try await track.load(.timeRange)
            print("MUSIC TAIL export opening=\(includeOpening) mixed=\(mix.duration) audioTrack=\(trackRange)")
            #expect(abs(trackRange.duration.seconds - mix.duration) < 1.0/48_000)
            let samples = try AudioRenderer.decode(final)[0]
            #expect(abs(Double(samples.count) / 48_000 - mix.duration) < 1.0/48_000)
            #expect(samples.suffix(12_000).map(abs).max()! > 0.01)
        }
    }

    @Test @MainActor func emptyChartAndShortMusicKeepTheirFullTails() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let music = root.appendingPathComponent("short.wav")
        try Self.music(at: music, seconds: 0.25)
        let chart = SimaiParser.parse("(120){4}1h[1:2],E")
        for bgm in [music, nil] {
            let audio = try AudioRenderer.render(chart: chart, music: bgm, resources: StudioModel.resourceURL,
                destination: root.appendingPathComponent("mix.wav"), settings: AudioMixSettings())
            #expect(audio.startTime + audio.duration == AllPerfectOutro(chart: chart)?.endTime)
            let samples = try AudioRenderer.decode(audio.url)[0]
            #expect(samples.suffix(96_000).map(abs).max()! > 0.001) // the AP sound's tail is retained too
        }
        try Self.music(at: music)
        let empty = try AudioRenderer.render(chart: SimaiParser.parse("(120){4},E"), music: music, resources: StudioModel.resourceURL,
            destination: root.appendingPathComponent("empty.wav"), settings: AudioMixSettings())
        #expect(empty.startTime + empty.duration == 8)
    }
}
