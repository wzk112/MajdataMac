import SwiftUI

struct StudioSettingsView: View {
    @Bindable var model: StudioModel
    @Binding var appearance: AppAppearance

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            ScrollView {
                VStack(spacing: 12) {
                    section("外观", icon: "circle.lefthalf.filled") {
                        Picker("界面外观", selection: $appearance) {
                            ForEach(AppAppearance.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden()
                        Text("舞台预览始终是深色，和游戏里一样。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    section("编辑器", icon: "text.cursor") {
                        HStack {
                            Text("字号"); Spacer()
                            Text("\(Int(model.fontSize))").monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: $model.fontSize, in: 11...26).accessibilityLabel("编辑器字号")
                        Toggle("播放时跟随源码", isOn: $model.follow)
                    }
                    section("画面特效 · 播放与导出", icon: "sparkles") {
                        StageEffectsControls(model: model)
                    }
                    section("资源", icon: "photo.on.rectangle") {
                        HStack {
                            Button("选择自定义皮肤…") { model.chooseSkin() }
                            Button("恢复默认皮肤") { model.loadSkin(nil) }
                        }.buttonStyle(.glass)
                    }
                    section("编码工具", icon: "film") {
                        TextField("FFmpeg 路径", text: $model.ffmpegPath)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: model.ffmpegPath) { _, value in
                                UserDefaults.standard.set(value, forKey: "ffmpegPath")
                            }
                    }
                    Text("Majdata Mac · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "本地构建")\n基于 MajdataView / MajdataEdit · GPL-3.0")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 4)
                }.padding(16)
            }
        }.background { StudioBackdrop().ignoresSafeArea() }
            .frame(width: 520, height: 650)
            .toggleStyle(StudioSwitchStyle())
    }

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).studioGlass(22)
    }
}
