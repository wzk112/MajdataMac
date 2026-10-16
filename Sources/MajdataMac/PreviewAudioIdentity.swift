import Foundation
import MajdataCore

/// Compare audible content instead of the source revision. Equal schedules can
/// keep their decoded audio, live engine and playhead across formatting/mirror edits.
struct PreviewAudioIdentity: Equatable {
    let music: URL?
    let metronome: Bool
    let start: Double
    let end: Double
    let events: [SoundEvent]
    let regionSource: String?
    init(chart: ParsedChart, music: URL?, metronome: Bool, regionSource: String?) {
        self.music = music; self.metronome = metronome; self.regionSource = regionSource
        start = min(0, (chart.notes.first?.time ?? 0) - 1)
        end = max(chart.duration + 2, AllPerfectOutro(chart: chart)?.endTime ?? 0)
        events = SoundSchedule.events(chart, metronome: metronome).sorted {
            if $0.time != $1.time { return $0.time < $1.time }
            if $0.sound != $1.sound { return $0.sound < $1.sound }
            if $0.channel != $1.channel { return $0.channel.rawValue < $1.channel.rawValue }
            return ($0.duration ?? 0) < ($1.duration ?? 0)
        }
    }
}
