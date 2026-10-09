import Foundation

/// Audio render timestamps arrive once per I/O block, not once per display frame.
/// Interpolate from that authoritative timestamp on the same host clock; re-anchor on every
/// audio block instead of allowing a separate wall-clock timer to drift away from the music.
enum AudioPresentationClock {
    static func position(offset: Double, sampleTime: Int64, sampleRate: Double,
                         renderHostSeconds: Double?, hostSeconds: Double,
                         rate: Double, duration: Double) -> Double {
        guard sampleRate > 0, sampleRate.isFinite else { return min(duration, max(0, offset)) }
        let elapsed = renderHostSeconds.map { min(0.1, max(-0.1, hostSeconds - $0)) } ?? 0
        // A scheduled start may still have negative player sample time. Keep the transport at
        // its seek position until that start, including after pause, seek and device reconnect.
        let played = max(0, Double(sampleTime) / sampleRate + elapsed * rate)
        return min(duration, max(0, offset + played))
    }
}
