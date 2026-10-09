import AudioToolbox
import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

enum AudioOutputRouting {
    enum Failure: LocalizedError {
        case unavailable, binding(OSStatus), wrongDevice
        var errorDescription: String? {
            switch self {
            case .unavailable: "音频输出设备尚未就绪"
            case .binding(let code): "无法连接音频输出设备（\(code)）"
            case .wrongDevice: "音频引擎未连接到指定输出设备，请重新连接"
            }
        }
    }
    static var defaultID: AudioDeviceID {
        values(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice).first ?? 0
    }
    static var devices: [AudioOutputDevice] {
        values(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).compactMap { id in
            guard !values(id, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput).isEmpty,
                  values(id, kAudioDevicePropertyDeviceIsAlive).first == 1 else { return nil }
            return device(id)
        }
    }
    static func device(_ id: AudioDeviceID) -> AudioOutputDevice? {
        guard id != 0, let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName) else { return nil }
        return AudioOutputDevice(id: id, uid: uid, name: name)
    }
    // Device IDs can change when iShot recreates its aggregate device; persist only UIDs.
    static func resolve(preferredUID: String, devices: [AudioOutputDevice], defaultID: AudioDeviceID) -> AudioOutputDevice? {
        if !preferredUID.isEmpty, let preferred = devices.first(where: { $0.uid == preferredUID }) { return preferred }
        return devices.first { $0.id == defaultID }
    }
    static func currentID(_ unit: AudioUnit) -> AudioDeviceID? {
        var id = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, &size) == noErr,
              id != 0 else { return nil }
        return id
    }
    static func bind(_ unit: AudioUnit, to device: AudioDeviceID) throws {
        try bind(device, set: { id in
            var value = id
            return AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                        &value, UInt32(MemoryLayout<AudioDeviceID>.size))
        }, current: { currentID(unit) })
    }
    // Injectable only at the Core Audio boundary: routing tests never change a real device.
    static func bind(_ device: AudioDeviceID, set: (AudioDeviceID) -> OSStatus, current: () -> AudioDeviceID?) throws {
        guard device != 0 else { throw Failure.unavailable }
        let status = set(device)
        guard status == noErr else { throw Failure.binding(status) }
        guard current() == device else { throw Failure.wrongDevice }
    }
    private static func values(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [UInt32] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var result = [UInt32](repeating: 0, count: Int(size) / MemoryLayout<UInt32>.size)
        let status = result.withUnsafeMutableBytes { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0.baseAddress!) }
        return status == noErr ? Array(result.prefix(Int(size) / MemoryLayout<UInt32>.size)) : []
    }
    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: CFString?, size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        return status == noErr ? value as String? : nil
    }
}
