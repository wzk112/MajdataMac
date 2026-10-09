import Testing
import AudioToolbox
@testable import MajdataMac

/// Pure routing tests: no engine, no real device changes, and no sound playback.
struct AudioOutputRoutingTests {
    private let speakers = AudioOutputDevice(id: 88, uid: "speakers", name: "Speakers")
    private let capture = AudioOutputDevice(id: 150, uid: "capture", name: "iShot Multi-Output")

    @Test func followsDefaultAndRestoresRecreatedVirtualDevice() {
        let devices = [speakers, capture]
        #expect(AudioOutputRouting.resolve(preferredUID: "", devices: devices, defaultID: 88) == speakers)
        #expect(AudioOutputRouting.resolve(preferredUID: "", devices: devices, defaultID: 150) == capture)
        #expect(AudioOutputRouting.resolve(preferredUID: "capture", devices: devices, defaultID: 88) == capture)
        #expect(AudioOutputRouting.resolve(preferredUID: "capture", devices: [speakers], defaultID: 88) == speakers)
        let recreated = AudioOutputDevice(id: 260, uid: "capture", name: "iShot Multi-Output")
        #expect(AudioOutputRouting.resolve(preferredUID: "capture", devices: [speakers, recreated], defaultID: 88) == recreated)
        #expect(AudioOutputRouting.resolve(preferredUID: "", devices: [speakers], defaultID: 150) == nil)
        #expect(AudioOutputRouting.resolve(preferredUID: "capture", devices: [], defaultID: 0) == nil)
    }
    @Test func setsEngineRouteAndVerifiesActualDevice() throws {
        var actual: UInt32 = 88, writes: [UInt32] = []
        try AudioOutputRouting.bind(150, set: { target in writes.append(target); actual = target; return noErr }, current: { actual })
        #expect(writes == [150] && actual == 150)
        #expect(throws: AudioOutputRouting.Failure.self) {
            try AudioOutputRouting.bind(88, set: { _ in noErr }, current: { actual })
        }
        #expect(throws: AudioOutputRouting.Failure.self) {
            try AudioOutputRouting.bind(88, set: { _ in -50 }, current: { 88 })
        }
        #expect(throws: AudioOutputRouting.Failure.self) {
            try AudioOutputRouting.bind(88, set: { _ in noErr }, current: { nil })
        }
        #expect(throws: AudioOutputRouting.Failure.self) {
            try AudioOutputRouting.bind(0, set: { _ in Issue.record("Must not bind an unavailable route"); return noErr }, current: { 0 })
        }
    }
}
