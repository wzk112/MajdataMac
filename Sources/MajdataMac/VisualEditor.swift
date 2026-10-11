import SwiftUI
import MajdataCore

enum EditorMode: String, CaseIterable {
    case visual, code
    var title: String { self == .visual ? "可视化编辑" : "代码编辑" }
}

enum AppAppearance: String, CaseIterable {
    case system, light, dark
    var title: String { self == .system ? "跟随系统" : (self == .light ? "浅色" : "深色") }
    var colorScheme: ColorScheme? { self == .system ? nil : (self == .light ? .light : .dark) }
}

/// Tools of the vertical track. Keys follow Visual Maimai: 1–3 place on the track, 4–5 on the stage.
enum TrackTool: String, CaseIterable, Identifiable {
    case select, tap, hold, slide, touch, touchHold
    var id: String { rawValue }
    var title: String {
        switch self {
        case .select: "选择"; case .tap: "Tap"; case .hold: "Hold"; case .slide: "Slide"; case .touch: "Touch"; case .touchHold: "TouchHold"
        }
    }
    var key: String { self == .select ? "V" : String((Self.allCases.firstIndex(of: self) ?? 0)) }
    var placesNotes: Bool { self != .select }
}

/// 可视化编辑: tools | vertical track | stage and selection. The simai text stays the single source of truth.
struct VisualWorkspace: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var model: StudioModel
    var showCode: () -> Void
    @AppStorage("trackPanelWidth") private var trackPanelWidth = 430.0
    var body: some View {
        GeometryReader { geometry in
            // With both side panels open the tools shrink to a key rail so the stage keeps a usable size.
            let compact = geometry.size.width < 900
            let toolWidth = compact ? 56.0 : 232.0
            let trackLimit = max(300, geometry.size.width - toolWidth - 300)
            let trackWidth = min(max(300, trackPanelWidth), trackLimit)
            HStack(spacing: 0) {
                TrackToolPanel(model: model, compact: compact).frame(width: toolWidth)
                Divider()
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Picker("每小节", selection: $model.timelineBeatsPerBar) {
                            ForEach(2...12, id: \.self) { Text("\($0) 拍").tag($0) }
                        }.frame(width: 118).help("小节线按四分音符计拍；不修改 simai 的 {分音} 或音乐。")
                        Toggle("吸附", isOn: $model.timelineSnap).toggleStyle(.checkbox).help("拖动定位吸附到源码中的分音位置")
                        Toggle("跟随", isOn: $model.timelineFollow).toggleStyle(.checkbox).help("播放线快到顶部时翻页；手动平移后暂停跟随")
                        Spacer(minLength: 0)
                        Button { model.trackSpan = min(60, model.trackSpan * 1.5) } label: { Image(systemName: "minus.magnifyingglass") }.help("缩小")
                        Button { model.trackSpan = max(0.5, model.trackSpan / 1.5) } label: { Image(systemName: "plus.magnifyingglass") }.help("放大")
                    }.font(.caption).buttonStyle(.plain).padding(.horizontal, 12).frame(height: 30)
                    DivisorBar(model: model)
                    Divider()
                    TrackLaneHeader()
                    Divider()
                    VerticalTrackView(model: model)
                }.frame(width: trackWidth)
                PanelDivider(axis: .vertical, value: $trackPanelWidth, displayedValue: trackWidth,
                             limits: 300...trackLimit, label: "竖谱与舞台分隔线")
                VStack(spacing: 0) {
                    HStack {
                        Text("MAJDATA RENDER").font(.system(size: 10, weight: .semibold)).tracking(1.7).foregroundStyle(.secondary)
                        Spacer()
                        Button("独立舞台", systemImage: "arrow.up.left.and.arrow.down.right") { openWindow(id: "stage") }.labelStyle(.iconOnly).buttonStyle(.plain).help("打开独立舞台 ⇧⌘P")
                    }.padding(.horizontal, 16).frame(height: 34)
                    LiveStageView(model: model)
                        .overlay { StageInputSurface(model: model, tool: model.trackTool, pending: model.pendingSlide) }
                        .aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider().padding(.top, 12)
                    SelectionSummary(model: model, showCode: showCode).frame(height: 150)
                }.frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity).background(Color.primary.opacity(0.025))
            }
        }
    }
}

/// Column captions that line up with `VerticalTrackLayout`.
private struct TrackLaneHeader: View {
    var body: some View {
        GeometryReader { geometry in
            let lane = max(12, (geometry.size.width - VerticalTrackLayout.gutter - VerticalTrackLayout.aux * 2) / 8)
            HStack(spacing: 0) {
                Color.clear.frame(width: VerticalTrackLayout.gutter)
                ForEach((1...8).reversed(), id: \.self) { key in Text("\(key)").frame(width: lane) }
                Text("T").frame(width: VerticalTrackLayout.aux)
                Text("BPM").frame(width: VerticalTrackLayout.aux)
            }.font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary).frame(maxHeight: .infinity)
        }.frame(height: 22)
    }
}

/// 分音: the grid clicks snap to. The field takes any value, e.g. 7 or 28 for septuplets.
private struct DivisorBar: View {
    @Bindable var model: StudioModel
    @State private var custom = ""
    var body: some View {
        HStack(spacing: 5) {
            Text("分音").foregroundStyle(.secondary)
            ForEach([4, 8, 12, 16, 24, 32], id: \.self) { value in
                Button { model.trackDivisor = value; custom = "" } label: {
                    Text("\(value)").font(.system(size: 11, weight: model.trackDivisor == value ? .bold : .regular, design: .monospaced))
                        .frame(minWidth: 24, minHeight: 20)
                        .foregroundStyle(model.trackDivisor == value ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .background(model.trackDivisor == value ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.08)), in: RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.plain).accessibilityLabel("\(value) 分音")
            }
            TextField("自定", text: $custom).textFieldStyle(.roundedBorder).controlSize(.small).frame(width: 52)
                .onSubmit { if let value = Int(custom), (1...384).contains(value) { model.trackDivisor = value } else { custom = "" } }
                .help("输入 1–384 的任意分音后回车，例如 7、14、28")
            if ![4, 8, 12, 16, 24, 32].contains(model.trackDivisor) {
                Text("{\(model.trackDivisor)}").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.tint)
            }
            Spacer(minLength: 0)
        }.font(.caption).padding(.horizontal, 12).frame(height: 30)
    }
}

private struct TrackToolPanel: View {
    @Bindable var model: StudioModel
    var compact = false
    var body: some View {
        if compact { rail } else { full }
    }
    /// Keys only; the labels live in the tooltips.
    private var rail: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(TrackTool.allCases) { tool in
                    let selected = model.trackTool == tool
                    Button { model.trackTool = tool } label: {
                        Text(tool.key).font(.system(size: 13, weight: .bold, design: .monospaced)).frame(width: 40, height: 34)
                            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                            .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.08)), in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).help(tool.title).accessibilityLabel(tool.title).accessibilityAddTraits(selected ? .isSelected : [])
                }
                Divider().padding(.vertical, 4)
                ForEach(Array("bxfw"), id: \.self) { flag in
                    let armed = model.selectedNotes.isEmpty && model.placementFlags.contains(flag)
                    let title = ["b": "绝赞", "x": "保护", "f": "烟花", "w": "扇形"][flag] ?? ""
                    Button { model.toggleFlag(flag) } label: {
                        Text(String(flag).uppercased()).font(.system(size: 12, weight: .semibold, design: .monospaced)).frame(width: 40, height: 28)
                            .foregroundStyle(armed ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                            .background(armed ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.08)), in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain).help(title).accessibilityLabel(title).accessibilityAddTraits(armed ? .isSelected : [])
                }
            }.padding(.vertical, 10).frame(maxWidth: .infinity)
        }.background(Color.primary.opacity(0.025))
    }
    private var full: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                caption("工具")
                tool(.select)
                caption("Tap 编辑 · 在竖谱上点").padding(.top, 8)
                tool(.tap); tool(.hold); tool(.slide)
                caption("Touch 编辑 · 在舞台上点").padding(.top, 8)
                tool(.touch); tool(.touchHold)
                Text(hint).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.top, 4).fixedSize(horizontal: false, vertical: true)
                if model.pendingSlide != nil {
                    Button("取消这颗星星", role: .cancel) { model.pendingSlide = nil }.controlSize(.small).padding(.horizontal, 6)
                }
                caption(model.selectedNotes.isEmpty ? "修饰 · 用于接下来放的音符" : "修饰 · 改选中的音符").padding(.top, 10)
                HStack(spacing: 5) { flag("绝赞", "b"); flag("保护", "x") }
                HStack(spacing: 5) { flag("烟花", "f"); flag("扇形", "w") }
                caption("新 Slide / TouchHold 的时长").padding(.top, 10)
                HStack(spacing: 6) {
                    TextField("4:1", text: $model.slideLength).textFieldStyle(.roundedBorder).controlSize(.small).frame(width: 70)
                    Text("分音:拍数 → \(model.slideLengthToken)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }.padding(.horizontal, 6)
                caption("音符操作").padding(.top, 10)
                operation("删除选中", "⌫", enabled: !model.selectedNotes.isEmpty) { model.deleteSelectedNotes() }
                operation("撤销", "⌘Z", enabled: !model.visualUndo.isEmpty) { model.undoVisualEdit() }
                operation("重做", "⇧⌘Z", enabled: !model.visualRedo.isEmpty) { model.redoVisualEdit() }
                ForEach(ChartTransform.allCases, id: \.self) { transform in
                    operation(transform.rawValue, "", enabled: model.selectedRange.length > 0) { model.undoable { model.transform(transform) } }
                }
                operation("选段分音细化 ×2", "", enabled: model.selectedRange.length > 0) { model.undoable { model.subdivide() } }
            }.padding(10)
        }.background(Color.primary.opacity(0.025))
    }
    private var hint: String {
        switch model.trackTool {
        case .select: "点音符选中，右键删除。拖左边的小节号一栏可以定位播放。"
        case .tap: "点一下放一个 Tap，落在最近的分音线上。"
        case .hold: "按住往上拖出长度，松手确认。"
        case .slide: model.pendingSlide == nil ? "先在竖谱上点星星头，再到舞台上按住左键画星星尾。点已有的星星可以再加一条尾巴（同头多尾）。" : "到舞台上按住左键，从起点画到终点的键，经过的判定区决定形状。"
        case .touch: "在舞台上点一个判定区，时间取当前播放位置。"
        case .touchHold: "在舞台上点一个判定区，时长用下面填的值。"
        }
    }
    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 6).frame(height: 20)
    }
    private func tool(_ tool: TrackTool) -> some View {
        let selected = model.trackTool == tool
        return Button { model.trackTool = tool } label: {
            HStack(spacing: 9) {
                Text(tool.key).font(.system(size: 11, weight: .semibold, design: .monospaced)).frame(width: 18, height: 18)
                    .background(Color.primary.opacity(selected ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 5))
                Text(tool.title)
                Spacer(minLength: 0)
            }.padding(.horizontal, 9).frame(height: 30)
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func flag(_ title: String, _ flag: Character) -> some View {
        let armed = model.selectedNotes.isEmpty && model.placementFlags.contains(flag)
        return Button { model.toggleFlag(flag) } label: {
            HStack(spacing: 5) {
                Text(title); Spacer(minLength: 0)
                Text(String(flag).uppercased()).font(.system(size: 10.5, design: .monospaced)).opacity(0.75)
            }.font(.system(size: 12)).padding(.horizontal, 8).frame(height: 24).frame(maxWidth: .infinity)
                .foregroundStyle(armed ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(armed ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.08)), in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).accessibilityAddTraits(armed ? .isSelected : [])
    }
    private func operation(_ title: String, _ key: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(minLength: 0); Text(key).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary) }
                .font(.system(size: 12.5)).padding(.horizontal, 9).frame(height: 26).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled)
    }
}

/// What the current source selection contains, so the track and the text never disagree about it.
private struct SelectionSummary: View {
    var model: StudioModel
    var showCode: () -> Void
    var body: some View {
        let notes = model.selectedNotes
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(notes.isEmpty ? "未选中音符" : "已选 \(notes.count) 个音符").font(.system(size: 13, weight: .semibold))
                if notes.count > 1, Set(notes.map(\.time)).count == 1 {
                    Text("EACH").font(.system(size: 10, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 1)
                        .foregroundStyle(.black).background(.yellow, in: RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
                if let first = notes.first {
                    Button("在代码编辑中定位", systemImage: "arrow.up.forward.square") {
                        model.select(first); showCode()
                    }.buttonStyle(.plain).foregroundStyle(.tint).font(.caption)
                }
            }
            if notes.isEmpty {
                Text("在竖谱上点一个音符，或在代码编辑里把光标放进音符里。").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(notes.prefix(4)) { note in
                    HStack(spacing: 8) {
                        Text(note.kind.rawValue.capitalized).frame(width: 74, alignment: .leading)
                        Text(note.area == "C" ? "C" : (note.kind == .touch || note.kind == .touchHold ? note.area + String(note.lane) : "键 \(note.lane)")).frame(width: 44, alignment: .leading)
                        Text(StudioModel.timeLabel(note.time)).monospacedDigit()
                        Spacer()
                        Text("第 \(note.location.line) 行 第 \(note.location.column) 列").foregroundStyle(.secondary)
                    }.font(.system(size: 12))
                }
                if notes.count > 4 { Text("还有 \(notes.count - 4) 个").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }
}
