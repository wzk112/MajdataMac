import Testing
import AVFoundation
import Darwin
import MajdataCore
@testable import MajdataMac

@Suite(.serialized) struct AudioClockTests {
    @Test func interpolatesRepeatedBuffersAndKeepsAudioAnchor() {
        for rate in [0.25, 0.75, 1.0, 1.5, 2.0] {
            let positions = (0..<12).map { frame in
                AudioPresentationClock.position(offset: 5, sampleTime: 48_000, sampleRate: 48_000,
                    renderHostSeconds: 100, hostSeconds: 100 + Double(frame) / 120,
                    rate: rate, duration: 30)
            }
            for i in 1..<positions.count { #expect(abs(positions[i] - positions[i - 1] - rate / 120) < 1e-9) }
            let reanchored = AudioPresentationClock.position(offset: 5, sampleTime: 52_800, sampleRate: 48_000,
                renderHostSeconds: 100.1, hostSeconds: 100.108, rate: rate, duration: 30)
            #expect(abs(reanchored - (6.1 + 0.008 * rate)) < 1e-9)
        }
    }
    @Test func scheduledStartsFutureStampsSeeksAndEnd() {
        func time(_ sample: Int64, _ anchor: Double?, _ now: Double, offset: Double = 5) -> Double {
            AudioPresentationClock.position(offset: offset, sampleTime: sample, sampleRate: 48_000,
                renderHostSeconds: anchor, hostSeconds: now, rate: 1, duration: 10)
        }
        #expect(time(-4800, 100, 100.05) == 5)
        #expect(abs(time(4800, 100.02, 100) - 5.08) < 1e-9)
        #expect(time(48000, nil, 100) == 6)
        #expect(time(48000, 100, 100.01, offset: 2) < 3.011)
        #expect(time(480000, 100, 100.01) == 10)
        #expect(time(48000, 100, 105) == 6.1) // a stopped render clock cannot run away
    }
    @Test @MainActor func realEngineClockAdvancesInsideOneBuffer() async throws {
        let model = StudioModel(audioOutputEnabled: false)
        model.load(StudioModel.resourceURL.appendingPathComponent("Demo/maidata.txt"))
        defer { model.invalidateAudio() }
        for _ in 0..<200 where model.isPreparing { try await Task.sleep(for: .milliseconds(25)) }
        let playback = try #require(model.playback)
        model.seek(3); model.play()
        try await Task.sleep(for: .milliseconds(250))
        var samples: [(raw: Int64, smooth: Double, delay: Double)] = []
        for _ in 0..<120 {
            if let render = playback.reference.lastRenderTime,
               let player = playback.reference.playerTime(forNodeTime: render) {
                samples.append((player.sampleTime, playback.currentTime,
                    AVAudioTime.seconds(forHostTime: mach_absolute_time()) - AVAudioTime.seconds(forHostTime: render.hostTime)))
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        let repeated = zip(samples, samples.dropFirst()).filter { $0.raw == $1.raw }
        print("AUDIO CLOCK samples=\(samples.count) repeatedRaw=\(repeated.count) smoothAdvances=\(repeated.filter { $1.smooth > $0.smooth }.count) hostDelayRange=\(samples.map(\.delay).min() ?? 0)...\(samples.map(\.delay).max() ?? 0)")
        #expect(samples.count == 120)
        // When the hardware block is shorter than the task scheduler interval, this can be empty.
        #expect(repeated.allSatisfy { $1.smooth > $0.smooth })
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $1.smooth >= $0.smooth })
        var previous = playback.currentTime
        for rate in [0.5, 1.5, 0.75, 1.0] {
            model.rate = rate
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(2))
                let position = playback.currentTime
                #expect(position >= previous)
                previous = position
            }
        }
        model.pause()
        let paused = playback.currentTime
        try await Task.sleep(for: .milliseconds(40))
        #expect(playback.currentTime == paused)
        model.seek(1); #expect(playback.currentTime == 1 - model.prepared!.startTime)
    }
}
