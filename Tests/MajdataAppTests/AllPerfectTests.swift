import Testing
import SwiftUI
import MajdataCore
@testable import MajdataMac

@Suite(.serialized) struct AllPerfectTests {
    @Test func lastCompletedNoteControlsOutro() throws {
        for source in ["(120){4}1h[1:2],E", "(120){4}1-5[1:2],E", "(120){4}Ch[1:2],E"] {
            let chart = SimaiParser.parse(source)
            let outro = try #require(AllPerfectOutro(chart: chart))
            #expect(outro.startTime > chart.endTime)
            #expect(outro.startTime == chart.notes.map(\.endTime).max())
            #expect(outro.endTime == outro.startTime + 4)
            #expect(SoundSchedule.events(chart, metronome: false).filter { $0.sound == "all_perfect" } ==
                [SoundEvent(sound: "all_perfect", channel: .bgm, time: outro.startTime)])
        }
        let lateMarker = SimaiParser.parse("(120){1}1,,,,E")
        #expect(AllPerfectOutro(chart: lateMarker)?.startTime == 0)
        #expect(AllPerfectOutro(chart: SimaiParser.parse("(120){4},,,E")) == nil)
    }

    @Test func experimentalResultsMustQualify() throws {
        let chart = SimaiParser.parse("(120){4}1/A1,E")
        let failed = try RegionRecording.simulate(chart)
        let perfect = try RegionRecording.simulate(chart, inputMode: .outerButtons)
        #expect(AllPerfectOutro(chart: chart, recording: failed) == nil)
        #expect(!SoundSchedule.events(chart, metronome: false, recording: failed).contains { $0.sound == "all_perfect" })
        #expect(AllPerfectOutro(chart: chart, recording: perfect)?.startTime == 0)
        #expect(AllPerfectOutro(chart: chart) != nil)
    }

    @Test @MainActor func originalAssetsAndSeekableFrames() throws {
        let assets = AllPerfectAssets.shared
        #expect(assets.images.count == 11 && assets.manifest.nodes.count == 7)
        #expect(assets.manifest.animation.curves.count == 50)
        #expect(assets.manifest.animation.value(":ifDestroy", at: 2.85, default: 0) == 1)
        let chart = SimaiParser.parse("(120){4}1,E")
        let style = StageStyle()
        let renderer = ExportFrameRenderer(chart: chart, style: style, info: nil, statistics: nil, width: 720, height: 720)
        func pixels(_ time: Double) throws -> (CGImage, Data) {
            let image = try renderer.image(time: time, style: style)
            let context = try #require(CGContext(data: nil, width: 720, height: 720, bitsPerComponent: 8, bytesPerRow: 720*4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 720, height: 720))
            return (image, Data(bytes: try #require(context.data), count: 720*720*4))
        }
        var frames: [Double: Data] = [:]
        for time in [0.2, 0.65, 0.8, 1.5, 2.5, 3.0, 7.0] {
            let (image, data) = try pixels(time); frames[time] = data
            if let path = ProcessInfo.processInfo.environment["MAJDATA_OUTRO_PROOF"] {
                let folder = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                    .write(to: folder.appendingPathComponent("outro-\(time).png"))
            }
        }
        #expect(frames[0.65] != frames[0.8] && frames[0.8] != frames[1.5])
        #expect(frames[3] == frames[7]) // removed once; never loops while BGM is still playing
        #expect(try pixels(0.8).1 == frames[0.8]) // seek back / replay restores the same frame
    }
}
