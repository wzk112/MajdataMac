import CoreAudio
import Foundation

enum AudioOutputChange: Sendable { case devices, serviceRestart, verify }

/// Observe default routes and aggregate-device creation/removal. The low-frequency
/// check also catches a missed notification or an output unit staying on the old device.
@MainActor final class AudioOutputMonitor {
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var timer: Timer?

    init(onChange: @escaping @MainActor (AudioOutputChange) -> Void) {
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices,
                         kAudioHardwarePropertyServiceRestarted] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                Task { @MainActor in onChange(selector == kAudioHardwarePropertyServiceRestarted ? .serviceRestart : .devices) }
            }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
                listeners.append((address, block))
            }
        }
        let check = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { onChange(.verify) }
        }
        RunLoop.main.add(check, forMode: .common); timer = check
    }
    isolated deinit {
        timer?.invalidate()
        for (var address, listener) in listeners {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
    }
}
