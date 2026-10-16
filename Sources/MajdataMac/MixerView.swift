import SwiftUI

struct MixerControls: View {
    @Bindable var model: StudioModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("总音量"); Spacer(); Text("\(Int(model.mix.master * 100))%").monospacedDigit() }
            Slider(value: Binding(get: { Double(model.mix.master) }, set: { model.mix.master = Float($0) }), in: 0...1).accessibilityLabel("总音量")
            ForEach(AudioChannel.allCases) { channel in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(channel.title).font(.caption)
                        Spacer()
                        Text("\(Int(model.mix.level(channel) * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Button("M") { if !model.mix.muted.insert(channel).inserted { model.mix.muted.remove(channel) } }
                            .tint(model.mix.muted.contains(channel) ? .red : .secondary).help("静音：" + channel.title)
                            .accessibilityLabel(channel.title + "静音").accessibilityValue(model.mix.muted.contains(channel) ? "开" : "关")
                        Button("S") { if !model.mix.solo.insert(channel).inserted { model.mix.solo.remove(channel) } }
                            .tint(model.mix.solo.contains(channel) ? .yellow : .secondary).help("独听：" + channel.title)
                            .accessibilityLabel(channel.title + "独听").accessibilityValue(model.mix.solo.contains(channel) ? "开" : "关")
                    }.buttonStyle(.bordered).controlSize(.mini)
                    Slider(value: Binding(get: { Double(model.mix.level(channel)) }, set: { model.mix.levels[channel] = Float($0) }), in: 0...1)
                        .accessibilityLabel(channel.title)
                    AudioMeter(model: model, channel: channel)
                }
            }
            Toggle("节拍器（BGM 通道）", isOn: Binding(get: { model.mix.metronome }, set: { model.setMetronome($0) }))
            HStack {
                Button("保存为默认") { model.saveMixDefault() }
                Button("恢复默认") { model.restoreMixDefault() }
                Spacer()
                Button("取消静音 / 独听") { model.mix.muted = []; model.mix.solo = [] }
            }.controlSize(.small)
            Text("音量、静音和独听立即生效，并用于音频和视频导出。设置自动保存。更改节拍器需要重新准备音频。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct AudioMeter: View {
    var model: StudioModel
    var channel: AudioChannel
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15)) { _ in
            let level = model.isPlaying ? model.playback?.meter(channel) ?? 0 : 0
            GeometryReader { geometry in
                Capsule().fill(.primary.opacity(0.07))
                Capsule().fill(level > 0.9 ? Color.orange : Color.teal)
                    .frame(width: geometry.size.width * Double(min(1, max(0, (20 * log10(max(0.00001, level)) + 60) / 60))))
            }.frame(height: 3).accessibilityHidden(true)
        }
    }
}

struct MixerWindow: View {
    @Bindable var model: StudioModel
    var body: some View {
        GlassEffectContainer(spacing: 4) {
            VStack(spacing: 10) {
                ScrollView { MixerControls(model: model).padding(24) }.studioGlass(22)
                TransportBar(model: model).padding(16).studioGlass(20)
            }.padding(12)
        }.background { StudioBackdrop().ignoresSafeArea() }.frame(minWidth: 640, minHeight: 680)
    }
}
