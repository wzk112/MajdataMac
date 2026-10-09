import Testing
import SwiftUI
import AVFoundation
import MajdataCore
@testable import MajdataMac

@Suite(.serialized) struct AudioAndSensorTests {
    @Test func sourceAudioRouting() {
        var chart = ParsedChart()
        chart.notes = [Note(kind: .hold, lane: 1, time: 1, duration: 2),
                       Note(kind: .tap, lane: 3, time: 1, isBreak: true, isEX: true),
                       Note(kind: .touchHold, lane: 1, area: "C", time: 4, duration: 2, isFirework: true),
                       Note(kind: .slide, lane: 1, time: 7, segments: [SlideSegment(shape: "-", start: 1, end: 5, startTime: 8, duration: 2)]),
                       Note(kind: .slide, lane: 1, time: 10, isBreak: true, segments: [SlideSegment(shape: "-", start: 1, end: 5, startTime: 11, duration: 2)])]
        let events = SoundSchedule.events(chart, metronome: false)
        #expect(events.filter { $0.sound == "answer" && $0.time == 1 }.count == 1)
        for sound in ["answer", "judge"] { #expect(events.contains { $0.sound == sound && $0.time == 3 }) }
        #expect(events.contains { $0.sound == "judge_ex" && $0.channel == .ex && $0.time == 1 })
        #expect(events.contains { $0.sound == "slide" && $0.time == 8 })
        #expect(!events.contains { $0.sound == "slide" && $0.time == 10 })
        #expect(events.contains { $0.sound == "break_slide_start" && $0.channel == .slide && $0.time == 11 })
        #expect(events.contains { $0.sound == "judge_break_slide" && $0.channel == .breakSlide && $0.time == 13 })
        #expect(events.contains { $0.sound == "touchHold_riser" && $0.duration == 2 && $0.time == 4 })
        #expect(events.contains { $0.sound == "hanabi" && $0.channel == .hanabi && $0.time == 6 })
        let sparse = SimaiParser.parse("(120){1}1,2,3,E")
        #expect(SoundSchedule.events(sparse, metronome: true).filter { $0.sound == "clock" }.map(\.time).prefix(5) == [0, 0.5, 1, 1.5, 2])
    }
    @Test func sensorGeometryAndSeekState() throws {
        #expect(SensorGeometry.regions.count == 33)
        #expect(SensorGeometry.polygons.count == 34)
        let a1 = try #require(SensorGeometry.regions.first)
        #expect(abs(a1.x - 1.626505436) < 0.000001)
        #expect(abs(a1.radius - 0.9882515793691173) < 0.000001)
        #expect(a1.contains(Point(a1.x + a1.radius - 1e-12, a1.y)))
        #expect(!a1.contains(Point(a1.x + a1.radius + 0.001, a1.y)))
        let radius = sqrt(a1.radius * a1.radius + SensorGeometry.starRadius * SensorGeometry.starRadius)
        #expect(a1.contains(Point(a1.x + radius - 0.00001, a1.y), contactRadius: SensorGeometry.starRadius))
        #expect(!a1.contains(Point(a1.x + radius + 0.00001, a1.y), contactRadius: SensorGeometry.starRadius))
        let chart = SimaiParser.parse("(120){4},,1h[1:1]/Ch[1:1],2w6[2:1],E")
        #expect(!chart.hasErrors)
        let active = SensorGeometry.active(notes: chart.notes, at: 1.4)
        #expect(active.contains(0) && active.contains(16))
        #expect(SensorGeometry.active(notes: chart.notes, at: 0).isEmpty)
        #expect(SensorGeometry.active(notes: chart.notes, at: 1.4) == active)
        #expect(SensorGeometry.active(notes: chart.notes, at: 20).isEmpty)
    }
    @Test @MainActor func liveChannelsAndExportVolumes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let chart = SimaiParser.parse("(120){4},,1/2x/3b/Chf[4:4],1-5[2:1],2-6[2:1]b,E")
        #expect(!chart.hasErrors)
        var settings = AudioMixSettings()
        let audio = try AudioRenderer.render(chart: chart, music: nil, resources: StudioModel.resourceURL, destination: root.appendingPathComponent("mix.wav"), settings: settings, retainStems: true)
        #expect(audio.stems.count == 9)
        let playback = try AudioPlayback(audio, settings: settings, audioOutputEnabled: false)
        #expect(playback.outputVolume == 0)
        try playback.play(at: 1)
        #expect(playback.isPlaying)
        try await Task.sleep(for: .milliseconds(220))
        settings.levels[.judge] = 0.12; settings.muted = [.touch]; settings.solo = [.judge, .touch]
        playback.apply(settings)
        #expect(playback.outputVolume == 0)
        #expect(playback.isPlaying)
        #expect(abs(playback.channels[.judge]!.volume - 0.12 * audio.headroom) < 0.00001)
        #expect(playback.channels[.touch]!.volume == 0 && playback.channels[.bgm]!.volume == 0)
        playback.rate = 0.75; try playback.seek(2, playing: true)
        try await Task.sleep(for: .milliseconds(220))
        let times = playback.channelTimes
        print("STEM CLOCK times=\(times)")
        try #require(times.count == 9)
        #expect(times.count == 9 && times.max()! - times.min()! < 0.005)
        playback.pause()
        var quiet = AudioMixSettings(); quiet.master = 0
        let zero = try AudioRenderer.render(chart: chart, music: nil, resources: StudioModel.resourceURL, destination: root.appendingPathComponent("zero.wav"), settings: quiet)
        #expect(try AudioRenderer.decode(zero.url)[0].allSatisfy { $0 == 0 })
        var half = AudioMixSettings(); half.master = 0.5
        let reduced = try AudioRenderer.render(chart: chart, music: nil, resources: StudioModel.resourceURL, destination: root.appendingPathComponent("half.wav"), settings: half)
        let fullSamples = try AudioRenderer.decode(audio.url)[0], halfSamples = try AudioRenderer.decode(reduced.url)[0]
        #expect(zip(fullSamples, halfSamples).allSatisfy { abs($0 * 0.5 - $1) < 0.0001 })
        #expect(fullSamples.allSatisfy { abs($0) <= 0.98 })
    }
    @Test @MainActor func userChartValidation() async throws {
        guard let folder = ProcessInfo.processInfo.environment["MAJDATA_REAL_CHART"] else { return }
        let root = URL(fileURLWithPath: folder)
        let document = ChartDocument(text: try String(contentsOf: root.appendingPathComponent("maidata.txt"), encoding: .utf8))
        for difficulty in 0..<7 where !document.chart(difficulty).isEmpty {
            let chart = SimaiParser.parse(document.chart(difficulty), offset: document.offset)
            print("REAL CHART difficulty=\(difficulty + 1) notes=\(chart.notes.count) duration=\(chart.duration) errors=\(chart.diagnostics)")
            #expect(!chart.hasErrors)
            let replay = try RegionRecording.simulate(chart)
            #expect(replay.results.count == chart.notes.count)
            for r in replay.results.values.sorted(by: { $0.time < $1.time }) where r.grade != .critical {
                let note = try #require(chart.notes.first { $0.id == r.noteID })
                print("REAL NONCRITICAL difficulty=\(difficulty + 1) id=\(r.noteID) kind=\(note.kind) lane=\(note.lane) area=\(note.area) time=\(note.time) line=\(note.location.line) grade=\(r.grade) diff=\(r.difference) coverage=\(r.coverage)")
            }
        }
        let chart = SimaiParser.parse(document.chart(4), offset: document.offset)
        let started = ContinuousClock.now
        let recording = try RegionRecording.simulate(chart)
        print("REAL REGION duration=\(started.duration(to: .now)) results=\(recording.results.count) sensorChanges=\(recording.frames.count) grades=\(Dictionary(grouping: recording.results.values, by: \.grade).mapValues(\.count))")
        #expect(recording.results.count == chart.notes.count)
        guard let output = ProcessInfo.processInfo.environment["MAJDATA_REAL_PROOF"] else { return }
        let dest = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let map = ImageRenderer(content: StageView(chart: ParsedChart(), time: 0, style: StageStyle(center: "NONE", showSensors: true, sensorOpacity: 1)).frame(width: 1080, height: 1080))
        map.scale = 1
        let mapImage = try #require(map.cgImage)
        try #require(NSBitmapImageRep(cgImage: mapImage).representation(using: .png, properties: [:])).write(to: dest.appendingPathComponent("sensor-map.png"))
        let timeline = RenderTimeline.prepared(chart, speed: 7.5, touch: 7.5)
        let samples = stride(from: 1.0, to: chart.duration, by: 0.1).map { ($0, timeline.visible(at: $0).count) }
        let densest = try #require(samples.max { $0.1 < $1.1 })
        print("REAL CHART densest=\(densest.0) visible=\(densest.1)")
        let video = AVAssetImageGenerator(asset: AVURLAsset(url: root.appendingPathComponent("pv.mp4")))
        video.appliesPreferredTrackTransform = true
        for (index, time) in [30.0, 60.0, 90.0, densest.0].enumerated() {
            var style = StageStyle(showSensors: true, sensorOpacity: 0.8, recording: recording)
            style.background = NSImage(cgImage: try await video.image(at: CMTime(seconds: time, preferredTimescale: 600)).image, size: .zero)
            let renderer = ImageRenderer(content: StageView(chart: chart, time: time, style: style).frame(width: 1080, height: 1080))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: dest.appendingPathComponent("xaleid-\(index).png"))
        }
        if let moviePath = ProcessInfo.processInfo.environment["MAJDATA_REAL_MOVIE"] {
            let movieChart = SimaiParser.parse(document.chart(5), offset: document.offset)
            let replay = try RegionRecording.simulate(movieChart)
            let scratch = dest.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let audio = try AudioRenderer.render(chart: movieChart, music: root.appendingPathComponent("track.mp3"), resources: StudioModel.resourceURL, destination: scratch.appendingPathComponent("mix.wav"), settings: AudioMixSettings(), recording: replay)
            let silent = scratch.appendingPathComponent("silent.mp4")
            var reported = -1
            try await VideoExporter.render(chart: movieChart, audio: audio, video: root.appendingPathComponent("pv.mp4"), style: StageStyle(showSensors: true, sensorOpacity: 0.45, recording: replay), width: 720, height: 720, destination: silent) { progress in
                let step = Int(progress * 10)
                if step != reported { print("REAL MOVIE \(step * 10)%"); reported = step }
            }
            let aac = scratch.appendingPathComponent("mix.m4a")
            let encoder = try #require(AVAssetExportSession(asset: AVURLAsset(url: audio.url), presetName: AVAssetExportPresetAppleM4A))
            try await encoder.export(to: aac, as: .m4a)
            let output = URL(fileURLWithPath: moviePath)
            try await VideoExporter.mux(video: silent, audio: aac, output: output)
            let asset = AVURLAsset(url: output)
            #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
            #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
            #expect(abs(try await asset.load(.duration).seconds - audio.duration) < 0.04)
            print("REAL MOVIE COMPLETE path=\(output.path) seconds=\(audio.duration)")
        }
    }
}
