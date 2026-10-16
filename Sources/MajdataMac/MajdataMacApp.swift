import SwiftUI
import AppKit
import MajdataCore

@main struct MajdataMacApp: App {
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model = StudioModel()
    @AppStorage("editorMode") private var editorMode = EditorMode.visual
    @AppStorage("appearance") private var appearance = AppAppearance.system
    var body: some Scene {
        WindowGroup("Majdata Mac") {
            StudioView(model: model).frame(minWidth: 1100, minHeight: 720)
                .tint(StudioPalette.accent).preferredColorScheme(appearance.colorScheme).environment(\.controlActiveState, .key)
                .containerBackground(.clear, for: .window)
                .onAppear { delegate.model = model; NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
                .onOpenURL { if model.allowReplacing() { model.load($0) } }
        }.defaultSize(width: 1440, height: 920)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建谱面") { model.newDocument() }.keyboardShortcut("n")
                Button("打开谱面…") { model.openPanel() }.keyboardShortcut("o")
                Button("加载示例") { model.loadDemo() }
            }
            CommandGroup(replacing: .saveItem) {
                Button("保存") { model.save() }.keyboardShortcut("s")
                Button("另存为…") { model.save(as: true) }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("恢复自动保存…") { model.recover() }
                Divider()
                Button("导出视频…") { model.exportVideo() }
                Button("导出音频…") { model.exportAudio() }
            }
            CommandMenu("播放") {
                Button("播放 / 暂停") { model.togglePlayback() }.keyboardShortcut("c", modifiers: [.command, .shift])
                Button("停止") { model.stop() }.keyboardShortcut("x", modifiers: [.command, .shift])
                Toggle("跟随源码", isOn: $model.follow)
                Divider()
                Button("上一帧") { model.stepFrame(-1) }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Button("下一帧") { model.stepFrame(1) }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Toggle("显示判定区", isOn: $model.showSensors).keyboardShortcut("j", modifiers: [.command, .shift])
                Button("打开混音器") { openWindow(id: "mixer") }.keyboardShortcut("m", modifiers: [.command, .shift])
                Button("打开独立舞台") { openWindow(id: "stage") }.keyboardShortcut("p", modifiers: [.command, .shift])
            }
            CommandMenu("谱面") {
                ForEach(ChartTransform.allCases, id: \.self) { transform in Button(transform.rawValue) { model.transform(transform) } }
                Button("分音细化 ×2") { model.subdivide() }
                Divider(); Button("语法与操作冲突检查") { model.checkConflicts() }
            }
            CommandGroup(before: .sidebar) {
                Button("可视化编辑") { editorMode = .visual }.keyboardShortcut("1")
                Button("代码编辑") { editorMode = .code }.keyboardShortcut("2")
                Divider()
            }
            CommandGroup(after: .textEditing) { Button("查找与替换") { model.showFind = true }.keyboardShortcut("f") }
        }
        Window("Majdata · 舞台", id: "stage") {
            StandaloneStageWindow(model: model).tint(StudioPalette.accent).preferredColorScheme(appearance.colorScheme).environment(\.controlActiveState, .key).containerBackground(.clear, for: .window)
        }.defaultSize(width: 900, height: 960)
        Window("音量混音器", id: "mixer") { MixerWindow(model: model).tint(StudioPalette.accent).preferredColorScheme(appearance.colorScheme).environment(\.controlActiveState, .key).containerBackground(.clear, for: .window) }.defaultSize(width: 660, height: 850)
        Settings {
            StudioSettingsView(model: model, appearance: $appearance)
                .tint(StudioPalette.accent).preferredColorScheme(appearance.colorScheme).environment(\.controlActiveState, .key)
                .containerBackground(.clear, for: .window)
        }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: StudioModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.allowReplacing() == false ? .terminateCancel : .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        model?.exportTask?.cancel(); model?.invalidateAudio()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
