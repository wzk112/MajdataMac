import Testing
import SwiftUI
import CoreText
import AVFoundation
import MajdataCore
@testable import MajdataMac

@Suite(.serialized) struct RecordingIntroTests {
    @Test @MainActor func allResolutionsAndMetadata() throws {
        let chart = SimaiParser.parse("(120){4},,,,1,2,E")
        let opening = RecordingOpening(chart: chart, clockCount: "0")
        func proof(_ image: CGImage, _ name: String) throws {
            if let path = ProcessInfo.processInfo.environment["MAJDATA_INTRO_PROOF"] {
                let folder = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                    .write(to: folder.appendingPathComponent(name + ".png"))
            }
        }
        for resolution in VideoResolution.allCases {
            let (width, height) = resolution.dimensions
            let info = StageChartInfo(title: "中文曲名 · Xaleid◆scopiX", artist: "作曲者 / Artist", designer: "谱师 / Note Designer", difficulty: 5, level: "15.0", notes: 2, breaks: 0)
            let style = StageStyle()
            let frame = try ExportFrameRenderer(chart: chart, style: style, info: info, statistics: nil, width: width, height: height,
                intro: RecordingIntro(opening: opening, info: info))
            let image = try frame.image(time: -3, style: style)
            #expect(image.width == width && image.height == height)
            try proof(image, "size-\(resolution.rawValue)")
        }
        for difficulty in 0..<7 {
            let info = StageChartInfo(title: "长标题检查：这是包含中文、日本語、English 和符号 ◆ 的谱面名称 / A very long track title",
                artist: "Composer A feat. Composer B / 作曲与编曲", designer: "Note Designer A × Designer B / 合作谱面", difficulty: difficulty,
                level: difficulty == 6 ? "" : "14+", notes: 2, breaks: 0)
            let style = StageStyle()
            let frame = try ExportFrameRenderer(chart: chart, style: style, info: nil, statistics: nil, width: 720, height: 720,
                intro: RecordingIntro(opening: opening, info: info))
            try proof(frame.image(time: -3, style: style), "difficulty-\(difficulty)")
        }
    }
    @Test func recordingOnlyAndClockCount() {
        let chart = SimaiParser.parse("(120){4},,,,1,2,E")
        let opening = RecordingOpening(chart: chart, clockCount: "4")
        #expect(opening.startTime == -5 && opening.endTime == 0)
        #expect(opening.clockTimes == [0, 0.5, 1, 1.5])
        #expect(!SoundSchedule.events(chart, metronome: false).contains { $0.sound == "track_start" || $0.sound == "clock" })
        let events = SoundSchedule.events(chart, metronome: true, opening: opening)
        #expect(events.filter { $0.sound == "track_start" } == [SoundEvent(sound: "track_start", channel: .bgm, time: -5, duration: 5)])
        #expect(events.filter { $0.sound == "clock" && $0.time == 0 }.count == 1)
        #expect(RecordingOpening(chart: chart, clockCount: "-2").clockTimes.isEmpty)
        #expect(RecordingOpening(chart: chart, clockCount: "invalid").clockTimes.isEmpty)
        let early = SimaiParser.parse("(120){4}1,2,E", offset: -2)
        let earlyOpening = RecordingOpening(chart: early, clockCount: "0")
        #expect(earlyOpening.endTime == -3)
        #expect(earlyOpening.startTime == -8)
    }

    @Test @MainActor func audioPreRollPreservesMusicTimingAndVolume() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let chart = SimaiParser.parse("(120){4},,,,1,2,E")
        let opening = RecordingOpening(chart: chart, clockCount: "0")
        let resources = StudioModel.resourceURL, music = resources.appendingPathComponent("SFX/clock.wav")
        func render(_ name: String, _ mix: AudioMixSettings, _ op: RecordingOpening?) throws -> PreparedAudio {
            try AudioRenderer.render(chart: chart, music: music, resources: resources, destination: root.appendingPathComponent(name + ".wav"), settings: mix, retainStems: true, opening: op)
        }
        let mix = AudioMixSettings()
        let normal = try render("normal", mix, nil), recorded = try render("recorded", mix, opening)
        #expect(recorded.duration == normal.duration + 5)
        #expect(recorded.startTime == -5)
        let lead = 5 * 48000
        for channel in [AudioChannel.bgm, .answer, .judge] {
            let a = try AudioRenderer.decode(try #require(normal.stems[channel]))
            let b = try AudioRenderer.decode(try #require(recorded.stems[channel]))
            #expect(b[0].count == a[0].count + lead)
            #expect(Array(b[0].dropFirst(lead)) == a[0])
            #expect(Array(b[1].dropFirst(lead)) == a[1])
        }
        let signal = try AudioRenderer.decode(recorded.url)
        #expect(signal[0].prefix(lead).map(abs).max()! > 0.01)
        #expect(signal.flatMap { $0 }.allSatisfy { abs($0) <= 0.981 })
        var quiet = mix; quiet.levels[.bgm] = 0
        let muted = try AudioRenderer.decode(render("bgm-muted", quiet, opening).url)
        #expect(muted[0].prefix(lead).allSatisfy { $0 == 0 })
        quiet = mix; quiet.master = 0
        #expect(try AudioRenderer.decode(render("master-muted", quiet, opening).url).flatMap { $0 }.allSatisfy { $0 == 0 })
    }

    @Test @MainActor func originalArtworkAndTransitionExport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let chart = SimaiParser.parse("(120){4},,,,1,2,E")
        let opening = RecordingOpening(chart: chart, clockCount: "4")
        let info = StageChartInfo(title: "録制测试 · Recording", artist: "Artist / 作曲", designer: "Note designer", difficulty: 5, level: "15.0", notes: chart.notes.count, breaks: 0)
        let intro = RecordingIntro(opening: opening, info: info)
        let assets = RecordingIntroAssets.shared
        #expect(assets.images.count == 4 && assets.manifest.nodes.count == 16)
        #expect((CTFontCopyPostScriptName(HarmonyOSFont.coreText(size: 24)) as String).contains("HarmonyOS"))
        let entry = try #require(assets.manifest.animations["Entry"])
        #expect(abs(entry.duration - 50.0/60) < 0.00001)
        #expect(entry.value("SongDetail:m_Color.a", at: 0.41666666, default: 1) == 0)
        #expect(entry.value("SongDetail:m_Color.a", at: 0.8333333, default: 0) == 1)
        func context(_ width: Int, _ height: Int) throws -> CGContext {
            try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width*4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue))
        }
        for (width, height) in [(720,720),(1280,720)] {
            let style = StageStyle()
            let renderer = try ExportFrameRenderer(chart: chart, style: style, info: nil, statistics: nil, width: width, height: height, intro: intro)
            let normal = try ExportFrameRenderer(chart: chart, style: style, info: nil, statistics: nil, width: width, height: height)
            var previous: Data?
            for time in [-4.9, -4.4, -3, -0.95, -0.7, -0.4, 0, 1] {
                let actual = try context(width,height)
                try renderer.draw(time: time, style: style, into: actual)
                let pixels = Data(bytes: try #require(actual.data), count: width*height*4)
                if time < 0 { #expect(pixels != previous) }
                if time >= 0 {
                    let expected = try context(width,height)
                    try normal.draw(time: time, style: style, into: expected)
                    #expect(pixels == Data(bytes: try #require(expected.data), count: width*height*4))
                }
                previous = pixels
                if let path = ProcessInfo.processInfo.environment["MAJDATA_INTRO_PROOF"] {
                    let folder = URL(fileURLWithPath: path)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let image = try #require(actual.makeImage())
                    try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                        .write(to: folder.appendingPathComponent("intro-\(width)-\(time).png"))
                }
            }
        }
        let audio = try AudioRenderer.render(chart: chart, music: nil, resources: StudioModel.resourceURL,
            destination: root.appendingPathComponent("mix.wav"), settings: AudioMixSettings(), opening: opening)
        let silent = root.appendingPathComponent("silent.mp4")
        let metrics = try await VideoExporter.render(chart: chart, audio: audio, video: nil, style: StageStyle(), width: 720, height: 720,
            destination: silent, intro: intro) { _ in }
        #expect(metrics.frames == Int(ceil(audio.duration * 60)))
        let aac = root.appendingPathComponent("mix.m4a"), final = root.appendingPathComponent("final.mp4")
        let encoder = try #require(AVAssetExportSession(asset: AVURLAsset(url: audio.url), presetName: AVAssetExportPresetAppleM4A))
        try await encoder.export(to: aac, as: .m4a)
        try await VideoExporter.mux(video: silent, audio: aac, output: final)
        let movie = AVURLAsset(url: final)
        #expect(abs(try await movie.load(.duration).seconds - audio.duration) < 1.0/60)
        #expect(try await movie.loadTracks(withMediaType: .audio).count == 1)
        if let path = ProcessInfo.processInfo.environment["MAJDATA_INTRO_PROOF"] {
            try FileManager.default.copyItem(at: final, to: URL(fileURLWithPath: path).appendingPathComponent("intro-test.mp4"))
        }
        print("RECORDING INTRO export frames=\(metrics.frames), duration=\(audio.duration), elapsed=\(metrics.elapsed)")
    }
}
