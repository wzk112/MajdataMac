import SwiftUI
import MajdataCore

enum EditorMode: String, CaseIterable {
    case visual, code
    var title: String { self == .visual ? "可视化编辑" : "代码编辑" }
}

struct EditorModeSwitcher: View {
    @Binding var mode: EditorMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator
    var body: some View {
        HStack(spacing: 3) {
            ForEach(EditorMode.allCases, id: \.self) { item in
                Button { mode = item } label: {
                    Label(item.title, systemImage: item == .visual ? "pianokeys" : "curlybraces")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: mode == item ? .semibold : .medium))
                        .foregroundStyle(mode == item ? .primary : .secondary)
                        .frame(width: 112, height: 28)
                        .background {
                            if mode == item {
                                RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.09))
                                    .matchedGeometryEffect(id: "editor-mode", in: indicator)
                            }
                        }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(item.title).accessibilityAddTraits(mode == item ? .isSelected : [])
                    .help(item == .visual ? "可视化编辑 ⌘1" : "代码编辑 ⌘2")
            }
        }.padding(4).background {
            Color.clear.glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 12))
        }
            .animation(reduceMotion ? nil : StudioMotion.selection, value: mode)
            .accessibilityElement(children: .contain).accessibilityLabel("编辑模式")
    }
}

struct StagePreviewHeader: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        HStack {
            Label("舞台预览", systemImage: "circle.hexagongrid").font(.system(size: 12, weight: .semibold))
            Spacer()
            Button("独立舞台", systemImage: "arrow.up.left.and.arrow.down.right") { openWindow(id: "stage") }
                .labelStyle(.iconOnly).buttonStyle(.plain).help("打开独立舞台 ⇧⌘P")
        }.padding(.horizontal, 16).frame(height: 40)
    }
}

/// Both workspaces share the same stage proportions, margins and rendering surface.
struct EditorStagePreview: View {
    var model: StudioModel
    var editable = false
    var body: some View {
        GeometryReader { space in
            let side = max(1, min(560, space.size.width - 32, space.size.height - 32))
            LiveStageView(model: model)
                .overlay {
                    if editable { StageInputSurface(model: model, tool: model.trackTool, pending: model.pendingSlide) }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.08)).allowsHitTesting(false) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
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
    @Bindable var model: StudioModel
    var showCode: () -> Void
    @AppStorage("trackPanelWidth") private var trackPanelWidth = 430.0
    var body: some View {
        GeometryReader { geometry in
            // With both side panels open the tools shrink to a key rail so the stage keeps a usable size.
            let compact = geometry.size.width < 1000
            let toolWidth = compact ? 56.0 : 224.0
            let trackMinimum = 280.0
            let stageMinimum = compact ? 220.0 : 320.0
            let trackLimit = max(trackMinimum, geometry.size.width - toolWidth - stageMinimum - 15)
            let trackWidth = min(max(trackMinimum, trackPanelWidth), trackLimit)
            HStack(spacing: 0) {
                TrackToolPanel(model: model, compact: compact).frame(width: toolWidth).studioGlass(20)
                Color.clear.frame(width: 8)
                VStack(spacing: 0) {
                    HStack {
                        Label("竖谱", systemImage: "pianokeys").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("8 → 1").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                    }.padding(.horizontal, 12).frame(height: 40)
                    Divider()
                    HStack(spacing: 8) {
                        Picker("每小节", selection: $model.timelineBeatsPerBar) {
                            ForEach(2...12, id: \.self) { Text("\($0) 拍").tag($0) }
                        }.labelsHidden().frame(width: 76).help("小节线按四分音符计拍；不修改 simai 的 {分音} 或音乐。")
                        Toggle("吸附", isOn: $model.timelineSnap).toggleStyle(.checkbox).help("拖动定位吸附到源码中的分音位置")
                        Toggle("跟随", isOn: $model.timelineFollow).toggleStyle(.checkbox).help("播放时连续跟随；手动平移后暂停跟随")
                        Spacer(minLength: 0)
                        Button { model.trackSpan = min(60, model.trackSpan * 1.5) } label: { Image(systemName: "minus.magnifyingglass") }.help("缩小")
                        Button { model.trackSpan = max(0.5, model.trackSpan / 1.5) } label: { Image(systemName: "plus.magnifyingglass") }.help("放大")
                    }.font(.caption).buttonStyle(.plain).padding(.horizontal, 12).frame(height: 30)
                    DivisorBar(model: model)
                    Divider()
                    TrackLaneHeader()
                    Divider()
                    VerticalTrackView(model: model)
                }.frame(width: trackWidth).studioGlass(20)
                PanelDivider(axis: .vertical, value: $trackPanelWidth, displayedValue: trackWidth,
                             limits: trackMinimum...trackLimit, label: "竖谱与舞台分隔线")
                VStack(spacing: 0) {
                    StagePreviewHeader()
                    Divider()
                    EditorStagePreview(model: model, editable: true)
                    Divider()
                    SelectionSummary(model: model, showCode: showCode)
                        .frame(height: model.selectedNotes.isEmpty ? 88 : min(164, geometry.size.height * 0.28))
                }.frame(minWidth: stageMinimum, maxWidth: .infinity, maxHeight: .infinity).studioGlass(20)
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
        HStack(spacing: 4) {
            Text("分音").foregroundStyle(.secondary)
            ForEach([4, 8, 12, 16, 24, 32], id: \.self) { value in
                Button { model.trackDivisor = value; custom = "" } label: {
                    Text("\(value)").font(.system(size: 11, weight: model.trackDivisor == value ? .bold : .regular, design: .monospaced))
                        .frame(minWidth: 22, minHeight: 22)
                        .foregroundStyle(model.trackDivisor == value ? AnyShapeStyle(StudioPalette.onAccent) : AnyShapeStyle(.primary))
                        .background(model.trackDivisor == value ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.08)), in: RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.plain).accessibilityLabel("\(value) 分音")
            }
            TextField("自定", text: $custom).textFieldStyle(.roundedBorder).controlSize(.small).frame(width: 48)
                .onSubmit { if let value = Int(custom), (1...384).contains(value) { model.trackDivisor = value } else { custom = "" } }
                .onChange(of: model.trackDivisor) { _, value in
                    custom = [4, 8, 12, 16, 24, 32].contains(value) ? "" : String(value)
                }
                .help("输入 1–384 的任意分音后回车，例如 7、14、28")
            Spacer(minLength: 0)
        }.font(.caption).padding(.horizontal, 12).frame(height: 30)
    }
}

private struct TrackToolPanel: View {
    @Bindable var model: StudioModel
    var compact = false
    @State private var showOptions = false
    var body: some View {
        if compact { rail } else {
            VStack(spacing: 0) {
                HStack {
                    Label("制谱工具", systemImage: "cursorarrow.and.square.on.square.dashed")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                }.padding(.horizontal, 16).frame(height: 40)
                Divider()
                full
            }
        }
    }
    /// Keys only; the labels live in the tooltips.
    private var rail: some View {
        ScrollView {
            VStack(spacing: 4) {
                Button { showOptions.toggle() } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 40, height: 30)
                }.buttonStyle(.plain).help("工具选项与音符操作")
                    .accessibilityLabel("工具选项与音符操作")
                    .popover(isPresented: $showOptions, arrowEdge: .trailing) {
                        full.frame(width: 264, height: 600)
                    }
                Divider().padding(.bottom, 4)
                ForEach(TrackTool.allCases) { tool in
                    let selected = model.trackTool == tool
                    Button { model.trackTool = tool } label: {
                        Text(tool.key).font(.system(size: 13, weight: .bold, design: .monospaced)).frame(width: 40, height: 34)
                            .foregroundStyle(selected ? AnyShapeStyle(StudioPalette.onAccent) : AnyShapeStyle(.primary))
                            .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.08)), in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).help(tool.title).accessibilityLabel(tool.title).accessibilityAddTraits(selected ? .isSelected : [])
                }
                Divider().padding(.vertical, 4)
                ForEach(Array("bxfwhs"), id: \.self) { flag in
                    let armed = model.selectedNotes.isEmpty && model.placementFlags.contains(flag)
                    let title = ["b": "绝赞", "x": "保护", "f": "烟花", "w": "扇形", "h": "无头星星", "s": "绝赞星尾"][flag] ?? ""
                    Button { model.toggleFlag(flag) } label: {
                        Text(String(flag).uppercased()).font(.system(size: 12, weight: .semibold, design: .monospaced)).frame(width: 40, height: 28)
                            .foregroundStyle(armed ? AnyShapeStyle(StudioPalette.onAccent) : AnyShapeStyle(.primary))
                            .background(armed ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.08)), in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain).help(title).accessibilityLabel(title).accessibilityAddTraits(armed ? .isSelected : [])
                }
            }.padding(.vertical, 10).frame(maxWidth: .infinity)
        }.background(Color.primary.opacity(0.025))
    }
    private var full: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(TrackTool.allCases) { tool($0) }
                }
                Text(hint).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.pendingSlide != nil {
                    Button(model.pendingSlide?.from == nil ? "取消这颗星星" : "完成这颗星星") { model.pendingSlide = nil }
                        .controlSize(.small)
                }
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    caption(model.selectedNotes.isEmpty ? "新音符修饰" : "所选音符修饰")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        flag("绝赞", "b"); flag("保护", "x")
                        flag("烟花", "f"); flag("扇形", "w")
                        flag("无头星星", "h"); flag("绝赞星尾", "s")
                    }
                    Toggle(isOn: $model.slideWaitsOneBeat) {
                        HStack { Text("星星一拍后启动"); Spacer(minLength: 0); Text("O").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary) }
                    }.toggleStyle(.checkbox).font(.system(size: 11))
                        .help("关闭后，新星星不等待一拍便开始移动。")
                }
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        caption("时长")
                        Spacer()
                        Text("分音 : 拍数").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        TextField("4:1", text: $model.slideLength).textFieldStyle(.roundedBorder)
                            .controlSize(.small).frame(width: 62).accessibilityLabel("音符时长")
                        Button("应用到所选") { model.setSelectedDuration(String(model.slideLengthToken.dropFirst().dropLast())) }
                            .controlSize(.small).disabled(model.selectedSustained.isEmpty)
                            .help("修改所选 Hold、TouchHold 或 Slide 的时长；也用于新建 Slide 和 TouchHold。")
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    caption("音符操作")
                    HStack(spacing: 6) {
                        operation("撤销", "⌘Z", enabled: !model.visualUndo.isEmpty) { model.undoVisualEdit() }
                        operation("重做", "⇧⌘Z", enabled: !model.visualRedo.isEmpty) { model.redoVisualEdit() }
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        ForEach(ChartTransform.allCases, id: \.self) { transform in
                            operation(transform.rawValue, "", enabled: model.selectedRange.length > 0) { model.transform(transform) }
                        }
                        operation("分音细化 ×2", "", enabled: model.selectedRange.length > 0) { model.subdivide() }
                    }
                    operation("删除选中", "⌫", enabled: !model.selectedNotes.isEmpty) { model.deleteSelectedNotes() }
                }
            }.padding(14)
        }.background(Color.primary.opacity(0.02))
    }
    private var hint: String {
        switch model.trackTool {
        case .select: "点音符选中，右键删除。拖 Hold / TouchHold 的顶端改长度。拖左边的小节号一栏可以定位播放。"
        case .tap: "点一下放一个 Tap，落在最近的分音线上。"
        case .hold: "按住往上拖出长度，松手确认。"
        case .slide:
            if let pending = model.pendingSlide {
                pending.from == nil ? "到舞台上按住左键，从起点画到终点的键，画线的轨迹和方向决定形状。" : "接着画下一段，会和上一段连成一条连续的星星。画完按回车或点「完成这颗星星」。"
            } else { "先在竖谱上点星星头，再到舞台上按住左键画星星尾。点已有的星星可以再加一条尾巴（同头多尾）。" }
        case .touch: "在舞台上点一个判定区，时间取当前播放位置。"
        case .touchHold: "在舞台上点一个判定区，时长用下面填的值。"
        }
    }
    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }
    private func tool(_ tool: TrackTool) -> some View {
        let selected = model.trackTool == tool
        return Button { model.trackTool = tool } label: {
            HStack(spacing: 6) {
                Text(tool.key).font(.system(size: 11, weight: .semibold, design: .monospaced)).frame(width: 18, height: 18)
                    .background(Color.primary.opacity(selected ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 5))
                Text(tool.title).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }.font(.system(size: 11, weight: .medium)).padding(.horizontal, 7).frame(height: 34)
                .foregroundStyle(selected ? AnyShapeStyle(StudioPalette.onAccent) : AnyShapeStyle(.primary))
                .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.05)), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func flag(_ title: String, _ flag: Character) -> some View {
        let armed = model.selectedNotes.isEmpty && model.placementFlags.contains(flag)
        return Button { model.toggleFlag(flag) } label: {
            HStack(spacing: 5) {
                Text(title); Spacer(minLength: 0)
                Text(String(flag).uppercased()).font(.system(size: 10.5, design: .monospaced)).opacity(0.75)
            }.font(.system(size: 11)).padding(.horizontal, 8).frame(height: 28).frame(maxWidth: .infinity)
                .foregroundStyle(armed ? AnyShapeStyle(StudioPalette.onAccent) : AnyShapeStyle(.primary))
                .background(armed ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.08)), in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).accessibilityAddTraits(armed ? .isSelected : [])
    }
    private func operation(_ title: String, _ key: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) { Text(title); Spacer(minLength: 0); Text(key).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary) }
                .font(.system(size: 11)).lineLimit(1).padding(.horizontal, 6).frame(height: 28)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 5)).contentShape(Rectangle())
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
