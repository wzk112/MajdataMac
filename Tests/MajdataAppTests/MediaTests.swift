import Testing
import AVFoundation
import SwiftUI
import MajdataCore
@testable import MajdataMac

@Suite(.serialized) struct MediaTests {
    @Test func oldImplicitSimulationPreferenceDoesNotOverrideClassic() throws {
        let name = "MajdataModeTest-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "regionJudgement")
        #expect(PreviewJudgementMode.load(defaults) == .classic)
        defaults.set(PreviewJudgementMode.experimentalRegions.rawValue, forKey: "previewJudgementMode.v2")
        #expect(PreviewJudgementMode.load(defaults) == .experimentalRegions)
    }
    @Test @MainActor func classicPreviewKeepsSimulationOutOfScoringAndSound() async throws {
        let model = StudioModel(audioOutputEnabled: false)
        model.judgementMode = .classic
        model.load(StudioModel.resourceURL.appendingPathComponent("Demo/maidata.txt"))
        defer { model.invalidateAudio() }
        for _ in 0..<200 where model.isPreparing { try await Task.sleep(for: .milliseconds(25)) }
        try #require(model.prepared != nil)
        #expect(model.recording == nil && model.stageStyle.recording == nil)
        model.seek(model.rangeEnd)
        #expect(model.combo == model.chart.notes.count)
        let schedule = SoundSchedule.events(model.chart, metronome: false, recording: model.recording)
        for note in model.chart.notes where note.kind == .tap && !note.isBreak && !note.isEX {
            #expect(schedule.contains { $0.sound == "judge" && $0.time == note.time })
        }
    }
    @Test @MainActor func outputReconnectPreservesPositionMixAndPauseIntent() async throws {
        let model = StudioModel(audioOutputEnabled: false)
        model.load(StudioModel.resourceURL.appendingPathComponent("Demo/maidata.txt"))
        defer { model.invalidateAudio() }
        for _ in 0..<200 where model.isPreparing { try await Task.sleep(for: .milliseconds(25)) }
        let original = try #require(model.playback)
        let stems = try #require(model.prepared).stems
        model.rate = 0.75; model.seek(3); model.play()
        try await Task.sleep(for: .milliseconds(350)); model.tick()
        let position = model.currentTime
        // The real engine-configuration callback follows the same path as a default-device change.
        original.onConfigurationChange?()
        model.reconnectAudioOutput() // A burst must retain the original resume request.
        #expect(model.isPreparing && model.playWhenReady)
        for _ in 0..<200 where model.isPreparing { try await Task.sleep(for: .milliseconds(25)) }
        let replacement = try #require(model.playback)
        #expect(replacement !== original && model.prepared?.stems == stems)
        #expect(model.isPlaying && replacement.outputVolume == 0 && replacement.rate == 0.75)
        #expect(abs(replacement.channels[.judge]!.volume - model.mix.gain(.judge) * replacement.headroom) < 0.00001)
        try await Task.sleep(for: .milliseconds(350)); model.tick()
        #expect(model.currentTime > position + 0.1)
        model.reconnectAudioOutput(); model.pause(); model.seek(5)
        for _ in 0..<200 where model.isPreparing { try await Task.sleep(for: .milliseconds(25)) }
        #expect(!model.isPlaying && !model.playWhenReady && model.currentTime == 5)
        #expect(model.playback?.currentTime == 5 - model.prepared!.startTime)
        model.reconnectAudioOutput(); model.stop()
        for _ in 0..<200 where model.isPreparing { try await Task.sleep(for: .milliseconds(25)) }
        #expect(!model.isPlaying && model.currentTime == model.rangeStart)
    }
    @Test @MainActor func playDuringPreparationCanBeQueuedAndCancelled() async throws {
        let model = StudioModel(audioOutputEnabled: false)
        model.load(StudioModel.resourceURL.appendingPathComponent("Demo/maidata.txt"))
        #expect(model.isPreparing)
        model.togglePlayback(); #expect(model.playWhenReady)
        model.togglePlayback(); #expect(!model.playWhenReady)
        for _ in 0..<200 where model.isPreparing { try await Task.sleep(for: .milliseconds(25)) }
        #expect(model.prepared != nil && !model.isPlaying)
        // A partial/stale audio state must recover instead of silently ignoring Play.
        model.playback = nil
        model.togglePlayback()
        #expect(model.isPreparing && model.playWhenReady)
        for _ in 0..<200 where model.isPreparing { try await Task.sleep(for: .milliseconds(25)) }
        #expect(model.isPlaying && model.errorMessage == nil)
        let start = model.currentTime
        try await Task.sleep(for: .milliseconds(350)); model.tick()
        #expect(model.currentTime > start + 0.1)
        model.invalidateAudio()
        model.prepareAudio(thenPlay: false); model.togglePlayback(); model.stop()
        for _ in 0..<200 where model.isPreparing { try await Task.sleep(for: .milliseconds(25)) }
        #expect(!model.isPlaying && !model.playWhenReady)
    }
    @Test @MainActor func audioAndFixedSizeMovie() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Majdata-Validation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let chart = SimaiParser.parse("(120){4}1/5,3h[8:1],E")
        let resources = StudioModel.resourceURL
        let music = resources.appendingPathComponent("Demo/track.wav")
        let audio = try AudioRenderer.render(chart: chart, music: music, resources: resources, destination: root.appendingPathComponent("mix.wav"), settings: AudioMixSettings())
        #expect(audio.waveform.contains { $0 > 0.01 })
        let samples = try AudioRenderer.decode(audio.url)
        #expect(samples.count == 2)
        #expect(abs(Double(samples[0].count) / AudioRenderer.rate - audio.duration) < 0.01)
        let silent = root.appendingPathComponent("silent.mp4")
        try await VideoExporter.render(chart: chart, audio: audio, video: nil, style: StageStyle(), width: 1920, height: 1080, destination: silent) { _ in }
        let asset = AVURLAsset(url: silent)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let size = try await tracks[0].load(.naturalSize)
        #expect(size.width == 1920 && size.height == 1080)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - audio.duration) < 0.04)
        let m4a = root.appendingPathComponent("audio.m4a")
        let encoder = AVAssetExportSession(asset: AVURLAsset(url: audio.url), presetName: AVAssetExportPresetAppleM4A)!
        try await encoder.export(to: m4a, as: .m4a)
        let final = root.appendingPathComponent("final.mp4")
        try await VideoExporter.mux(video: silent, audio: m4a, output: final)
        let finalAsset = AVURLAsset(url: final)
        #expect(try await finalAsset.loadTracks(withMediaType: .video).count == 1)
        #expect(try await finalAsset.loadTracks(withMediaType: .audio).count == 1)
    }
    @Test @MainActor func repeatSeekAndPlayback() async throws {
        let model = StudioModel(audioOutputEnabled: false)
        model.load(StudioModel.resourceURL.appendingPathComponent("Demo/maidata.txt"))
        for _ in 0..<100 where model.isPreparing { try await Task.sleep(for: .milliseconds(100)) }
        #expect(!model.chart.hasErrors)
        #expect(model.prepared != nil)
        #expect(model.playback?.outputVolume == 0)
        for _ in 0..<3 {
            model.seek(3); model.togglePlayback()
            #expect(model.isPlaying)
            try await Task.sleep(for: .milliseconds(350)); model.tick()
            #expect(model.currentTime > 3.1 && model.currentTime < 3.6)
            model.pause()
            #expect(model.currentTime > 3.1)
            #expect(!model.isPlaying)
            model.seek(0); #expect(model.currentTime == 0)
        }
        model.stop()
    }
}
