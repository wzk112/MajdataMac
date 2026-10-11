import SwiftUI
import MajdataCore

struct StudioView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var model: StudioModel
    @State private var selection: String? = "studio"
    @AppStorage("sourcePanelWidth") private var sourcePanelWidth = 330.0
    @AppStorage("timelinePanelHeight") private var timelinePanelHeight = 240.0
    @AppStorage("sidebarPanelWidth") private var sidebarPanelWidth = 205.0
    @AppStorage("inspectorPanelWidth") private var inspectorPanelWidth = 255.0
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("editorMode") private var editorMode = EditorMode.visual
    // The visual editor needs the width for tools, track and stage, so its side panels start closed and are remembered separately.
    @AppStorage("visualShowSidebar") private var visualShowSidebar = false
    @AppStorage("visualShowInspector") private var visualShowInspector = false
    private var visual: Bool { editorMode == .visual }
    private var sidebarShown: Bool { visual ? visualShowSidebar : showSidebar }
    private var inspectorShown: Bool { visual ? visualShowInspector : model.showInspector }
    var body: some View {
        GeometryReader { outer in
        let sidebarLimit = max(185, min(420, outer.size.width - 600 - (inspectorShown ? 249 : 7)))
        let sidebarWidth = min(sidebarLimit, max(185, sidebarPanelWidth))
        let inspectorLimit = max(235, min(600, outer.size.width - 600 - (sidebarShown ? sidebarWidth + 14 : 7)))
        let inspectorWidth = min(inspectorLimit, max(235, inspectorPanelWidth))
        HStack(spacing: 0) {
        if sidebarShown {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path").font(.title2).foregroundStyle(.cyan)
                        .frame(width: 38, height: 38).background(.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) { Text("Majdata").font(.title3.bold()); Text("MAC STUDIO").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(.secondary) }
                }.padding(20)
                List(selection: $selection) {
                    Section("工作空间") {
                        Label("谱面工作台", systemImage: "slider.horizontal.below.rectangle").tag("studio")
                        Label("检查与分析", systemImage: "checkmark.seal").tag("analysis")
                        Label("使用指南", systemImage: "book.closed").tag("help")
                    }
                    Section("当前谱面") {
                        ForEach(0..<7, id: \.self) { diff in
                            Button { model.selectDifficulty(diff); selection = "studio" } label: {
                                HStack {
                                    Circle().fill(difficultyColor(diff)).frame(width: 6, height: 6)
                                    Text(ChartDocument.difficultyNames[diff]).font(.system(size: 11, weight: diff == model.difficulty ? .bold : .regular))
                                    Spacer()
                                    Text(model.document.level(diff)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    if diff == model.difficulty { Image(systemName: "checkmark").font(.caption2).foregroundStyle(.cyan) }
                                }.padding(.vertical, 3)
                            }.buttonStyle(.plain)
                        }
                    }
                    if !model.recentFiles.isEmpty {
                        Section("最近打开") {
                            ForEach(model.recentFiles.prefix(5), id: \.self) { path in
                                Button { if model.allowReplacing() { model.load(URL(fileURLWithPath: path)) } } label: {
                                    Label(URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent, systemImage: "doc.text").lineLimit(1).font(.caption)
                                }.buttonStyle(.plain).help(path)
                            }
                        }
                    }
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 8) {
                    Button("打开谱面…", systemImage: "folder") { model.openPanel() }.buttonStyle(.glass).frame(maxWidth: .infinity)
                    Button("加载示例", systemImage: "play.rectangle") { model.loadDemo() }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }.padding(16)
            }.frame(width: sidebarWidth).background(.background.secondary)
            PanelDivider(axis: .vertical, value: $sidebarPanelWidth, displayedValue: sidebarWidth,
                         limits: 185...sidebarLimit, label: "侧栏宽度分隔线")
        }
            VStack(spacing: 0) {
                if selection == "analysis" { AnalysisView(model: model) { selection = "studio" } }
                else if selection == "help" { HelpView() }
                else if editorMode == .visual { visualWorkspace }
                else { workspace }
                Divider()
                HStack(spacing: 8) {
                    Circle().fill(model.chart.hasErrors ? .orange : .teal).frame(width: 5, height: 5)
                    Text(model.status).lineLimit(1)
                    Spacer()
                    if model.isDirty { Text("未保存").foregroundStyle(.orange) }
                    Text(model.sourceEncoding.hasPrefix("UTF-8") ? "UTF-8 · SIMAI" : "\(model.sourceEncoding) → UTF-8 · SIMAI").foregroundStyle(.tertiary)
                }.font(.system(size: 10)).padding(.horizontal, 16).frame(height: 28)
            }
            .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(model.title + (model.isDirty ? " •" : ""))
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("侧栏", systemImage: "sidebar.left") { if visual { visualShowSidebar.toggle() } else { showSidebar.toggle() } }
                }
                ToolbarItem(placement: .principal) {
                    Picker("编辑模式", selection: Binding(get: { editorMode }, set: { editorMode = $0; selection = "studio" })) {
                        ForEach(EditorMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 230).help("可视化编辑 ⌘1 · 代码编辑 ⌘2")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("保存", systemImage: "square.and.arrow.down") { model.save() }.help("保存 ⌘S")
                    Menu {
                        Button("导出 MP4 视频…") { model.exportVideo() }
                        Button("导出 WAV 音频…") { model.exportAudio() }
                        Button("导出谱面 JSON…") { model.exportJSON() }
                    } label: { Label("导出", systemImage: "square.and.arrow.up") }
                    Button("检查", systemImage: "checkmark.seal") { model.checkConflicts(); selection = "analysis" }
                    Button("检查器", systemImage: "sidebar.right") { if visual { visualShowInspector.toggle() } else { model.showInspector.toggle() } }
                }
            }
            if inspectorShown {
                PanelDivider(axis: .vertical, value: $inspectorPanelWidth, displayedValue: inspectorWidth,
                             limits: 235...inspectorLimit, label: "设置栏宽度分隔线", reverse: true)
                InspectorView(model: model).frame(width: inspectorWidth)
            }
        }
        }
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .sheet(isPresented: Binding(get: { model.exportProgress != nil }, set: { _ in })) {
            VStack(spacing: 18) {
                Image(systemName: "film.stack").font(.largeTitle).foregroundStyle(.cyan)
                Text("导出谱面").font(.title2.bold())
                ProgressView(value: model.exportProgress ?? 0).frame(width: 330)
                Text(model.exportStatus).font(.caption).foregroundStyle(.secondary)
                Button("取消", role: .cancel) { model.exportTask?.cancel() }
            }.padding(32)
        }
    }
    var visualWorkspace: some View {
        VStack(spacing: 0) {
            VisualWorkspace(model: model) { editorMode = .code }
            Divider()
            TransportBar(model: model).padding(.horizontal, 16).padding(.vertical, 12)
        }
    }
    var workspace: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
            let editorWidth = min(max(240, sourcePanelWidth), max(240, geometry.size.width - 327))
            let timelineHeight = min(max(210, timelinePanelHeight), max(210, geometry.size.height - 287))
            VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Label("谱面源码", systemImage: "chevron.left.forwardslash.chevron.right").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Menu {
                            ForEach(ChartTransform.allCases, id: \.self) { transform in Button(transform.rawValue) { model.transform(transform) } }
                            Divider(); Button("选段分音细化 ×2") { model.subdivide() }
                        } label: { Image(systemName: "wand.and.stars") }.menuStyle(.borderlessButton).frame(width: 26)
                        Button { model.showFind.toggle() } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.plain)
                    }.padding(14)
                    Divider()
                    if model.showFind {
                        VStack(spacing: 6) {
                            HStack { TextField("查找", text: $model.findText); Button("下一个") { model.findNext() } }
                            HStack { TextField("替换为", text: $model.replacement); Button("全部替换") { model.replaceAll() } }
                        }.textFieldStyle(.roundedBorder).padding(10)
                    }
                    CodeEditor(model: model)
                    if !model.chart.diagnostics.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(model.chart.diagnostics.prefix(3)) { issue in
                                Button { model.locate(issue) } label: {
                                    Label("第 \(issue.location.line) 行：\(issue.message)", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange).lineLimit(2)
                                }.buttonStyle(.plain)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.orange.opacity(0.06))
                    }
                    HStack {
                        Text("\(model.source.components(separatedBy: "\n").count) 行")
                        Spacer(); Text("\(model.chart.notes.count) NOTES")
                    }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).padding(12)
                }.frame(width: editorWidth)
                PanelDivider(axis: .vertical, value: $sourcePanelWidth, displayedValue: editorWidth,
                             limits: 240...max(240, geometry.size.width - 327), label: "源码与预览分隔线")
                VStack(spacing: 0) {
                    HStack {
                        Text("MAJDATA RENDER").font(.system(size: 10, weight: .semibold)).tracking(1.7).foregroundStyle(.secondary)
                        Spacer()
                        Button("独立舞台", systemImage: "arrow.up.left.and.arrow.down.right") { openWindow(id: "stage") }.labelStyle(.iconOnly).buttonStyle(.plain).help("打开独立舞台 ⇧⌘P")
                        Text(model.regionJudgement ? "区域模拟" : "自动播放").font(.system(size: 9, weight: .medium)).foregroundStyle(.cyan).padding(.horizontal, 9).padding(.vertical, 4).background(.cyan.opacity(0.1), in: Capsule())
                    }.padding(16)
                    LiveStageView(model: model)
                        .aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    HStack(spacing: 22) {
                        stat("TAP", model.chart.count(.tap), .pink)
                        stat("HOLD", model.chart.count(.hold) + model.chart.count(.touchHold), .yellow)
                        stat("SLIDE", model.chart.count(.slide), .cyan)
                        stat("TOUCH", model.chart.count(.touch), .purple)
                        stat("BREAK", model.chart.breakCount, .orange)
                    }.padding(18)
                }.frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity).background(Color.primary.opacity(0.025))
            }.frame(height: max(280, geometry.size.height - timelineHeight - 7))
            PanelDivider(axis: .horizontal, value: $timelinePanelHeight, displayedValue: timelineHeight,
                         limits: 210...max(210, geometry.size.height - 287), label: "时间轴高度分隔线")
            TimelinePanel(model: model).frame(height: timelineHeight)
            }
            }
            TransportBar(model: model).padding(.horizontal, 16).padding(.vertical, 12)
        }
    }
    func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 5) { Text("\(value)").font(.system(size: 17, weight: .medium, design: .rounded)).monospacedDigit(); Text(label).font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(color) }
    }
    func difficultyColor(_ index: Int) -> Color { [.gray, .green, .yellow, .red, .purple, .pink, .cyan][index] }
}

struct TransportBar: View {
    @Bindable var model: StudioModel
    var body: some View {
        VStack(spacing: 8) {
        HStack(spacing: 10) {
            Text("播放进度").font(.caption).foregroundStyle(.secondary)
            PlaybackProgress(model: model).frame(height: 20)
        }
        HStack(spacing: 18) {
            HStack(spacing: 14) {
                Button("停止", systemImage: "stop.fill") { model.stop() }.labelStyle(.iconOnly).buttonStyle(.plain)
                Button { model.togglePlayback() } label: {
                    if model.isPreparing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small).frame(width: 18, height: 18)
                            Text(model.playWhenReady ? "等待播放 · 点击取消" : "准备中 · 点击后播放").font(.caption)
                        }
                    }
                    else { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 18, height: 18) }
                }.buttonStyle(.glassProminent).tint(.cyan).controlSize(.large).help("播放 / 暂停 ⇧⌘C；准备音频时可预约或取消播放")
                Button("回到开头", systemImage: "backward.end.fill") { model.seek(model.rangeStart) }.labelStyle(.iconOnly).buttonStyle(.plain)
            }
            TransportTimeLabel(model: model)
            Spacer()
            Toggle("跟随滚动", isOn: $model.follow).toggleStyle(.checkbox).font(.caption)
            Toggle(isOn: $model.loopEnabled) { Image(systemName: "repeat") }.toggleStyle(.button).help("循环 A–B 区间")
            Picker("速度", selection: $model.rate) { ForEach([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { Text(String(format: "%.2g×", $0)).tag($0) } }.frame(width: 108)
        }
        }
    }
}

struct TransportTimeLabel: View {
    var model: StudioModel
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(StudioModel.timeLabel(model.currentTime)).font(.system(size: 18, weight: .medium, design: .monospaced)).monospacedDigit()
            Text("/ " + StudioModel.timeLabel(model.rangeEnd)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}

struct InspectorView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var model: StudioModel
    var body: some View {
        Form {
            Section("谱面信息") {
                TextField("曲名", text: Binding(get: { model.document.title }, set: { model.document.title = $0; model.metadataChanged() }))
                TextField("作曲", text: Binding(get: { model.document.artist }, set: { model.document.artist = $0; model.metadataChanged() }))
                TextField("谱师", text: Binding(get: { model.document.designer(model.difficulty) }, set: { model.document.setDesigner($0, difficulty: model.difficulty); model.metadataChanged() }))
                TextField("等级", text: Binding(get: { model.document.level(model.difficulty) }, set: { model.document["lv_\(model.difficulty + 1)"] = $0; model.metadataChanged() }))
                TextField("偏移 / 秒", text: Binding(get: { model.document["first"] }, set: { model.document["first"] = $0; model.metadataChanged() }))
            }
            Section("预览") {
                slider("音符速度", value: $model.noteSpeed, range: 1...12)
                slider("Touch 速度", value: $model.touchSpeed, range: 1...12)
                slider("背景遮罩", value: $model.backgroundDim, range: 0...1)
                Picker("中心显示", selection: $model.centerDisplay) { ForEach(["COMBO", "ACHIEVEMENT", "DX SCORE", "NONE"], id: \.self) { Text($0) } }
                Picker("播放判定", selection: Binding(get: { model.judgementMode }, set: { model.setRegionJudgement($0 == .experimentalRegions) })) {
                    ForEach(PreviewJudgementMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text(model.regionJudgement ? "按假设的输入轨迹计算成绩，可能产生低判；尚未与原版 DJAuto 对齐。" : "与原版 Classic 一样直接给出最高判定；判定区高亮仅作位置演示。")
                    .font(.caption).foregroundStyle(.secondary)
                if model.regionJudgement {
                    Picker("输入方式", selection: Binding(get: { model.inputMode }, set: { model.setInputMode($0) })) {
                        ForEach(AutomaticInputMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text("内外配合会把阻挡 A 区 Touch 的 Tap/Hold 移到外键；不改变滑条触屏判定。").font(.caption).foregroundStyle(.secondary)
                }
                if model.regionJudgement, let recording = model.recording {
                    let misses = recording.results.values.filter { $0.grade == .miss }.count
                    Text("模拟结果：\(misses) MISS / \(recording.results.count) 个判定").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("判定区底纹", isOn: $model.showSensorPattern).help("在舞台上用细线画出 34 块判定区；只影响预览，不进导出视频。")
                Toggle("显示判定区", isOn: $model.showSensors)
                if model.showSensors {
                    Toggle("判定区按压高亮", isOn: $model.showSensorPresses)
                    Toggle("显示区域编号", isOn: $model.showSensorLabels)
                    slider("判定区透明度", value: $model.sensorOpacity, range: 0.1...1)
                    Text("34 块触屏区域，C1/C2 合并为 C；外圈短条显示 8 个外键。两者独立高亮，短按保留 80 ms，仅影响显示。").font(.caption).foregroundStyle(.secondary)
                }
                Picker("主界面刷新率", selection: $model.previewFrameRate) {
                    Text("跟随显示器").tag(0); Text("120 Hz").tag(120); Text("60 Hz").tag(60); Text("30 Hz").tag(30); Text("20 Hz").tag(20)
                }
                .help("主界面预览独立刷新，打开舞台后仍使用此设置。播放中修改立即生效。")
                Picker("独立舞台刷新率", selection: $model.frameRate) {
                    Text("跟随显示器").tag(0); Text("120 Hz").tag(120); Text("60 Hz").tag(60); Text("30 Hz").tag(30); Text("20 Hz").tag(20)
                }
                Toggle("显示刷新统计", isOn: $model.showFrameStats)
                Button("导入皮肤文件夹…") { model.chooseSkin() }
            }
            Section("画面特效 · 播放与导出") {
                StageEffectsControls(model: model)
                Text("立即应用于预览，视频导出使用相同设置。音效音量在混音器中单独调整。").font(.caption).foregroundStyle(.secondary)
            }
            Section("声音") {
                Picker("输出设备", selection: $model.audioOutputUID) {
                    Text("跟随系统").tag("")
                    ForEach(model.audioOutputDevices) { device in Text(device.name).tag(device.uid) }
                    if model.audioOutputUnavailable { Text("已断开的设备").tag(model.audioOutputUID) }
                }
                Text("实际输出：" + model.audioOutputName).font(.caption).foregroundStyle(.secondary)
                if model.audioOutputUnavailable { Text("所选设备已断开，暂时跟随系统输出。").font(.caption).foregroundStyle(.orange) }
                Button("重新连接音频输出") { model.reconnectAudioOutput() }.disabled(model.prepared == nil)
                Text(model.musicURL?.lastPathComponent ?? "未加载音乐").font(.caption).foregroundStyle(.secondary)
                Button("选择音乐…") { model.importMusic() }
                HStack {
                    Text("总音量"); Spacer(); Text("\(Int(model.mix.master * 100))%").monospacedDigit()
                }
                Slider(value: Binding(get: { Double(model.mix.master) }, set: { model.mix.master = Float($0) }), in: 0...1).accessibilityLabel("总音量")
                Button("打开 9 路混音器…") { openWindow(id: "mixer") }
                if !model.mix.muted.isEmpty || !model.mix.solo.isEmpty { Text("已启用静音或独听").font(.caption).foregroundStyle(.orange) }
            }
            Section("BPM 测量") {
                HStack { Text(model.tappedBPM.map { String(format: "%.1f BPM", $0) } ?? "点击测量").monospacedDigit(); Spacer(); Button("TAP") { model.tapBPM() } }
            }
        }.formStyle(.grouped).controlSize(.small)
    }
    func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) { HStack { Text(title); Spacer(); Text(String(format: "%.2g", value.wrappedValue)).foregroundStyle(.secondary).monospacedDigit() }; Slider(value: value, in: range) }
    }
}
struct AnalysisView: View {
    @State private var inputMode: AutomaticInputMode = .mixed
    @Bindable var model: StudioModel
    var showSource: () -> Void
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("谱面检查").font(.largeTitle.bold())
                Text("按区域进入、松开和音符实际判定结果检查输入冲突。仅靠近滑条不会报警。").foregroundStyle(.secondary)
                HStack {
                    Button(model.isAnalyzing ? "正在检查…" : "运行检查", systemImage: "checkmark.seal") { model.checkConflicts() }
                        .buttonStyle(.glassProminent).disabled(model.isAnalyzing)
                    if model.isAnalyzing { ProgressView().controlSize(.small) }
                    Text("\(model.chart.notes.count) 个音符 · \(model.chart.breakCount) 个 BREAK").foregroundStyle(.secondary)
                }
                ForEach(model.chart.diagnostics) { issue in
                    Button { model.locate(issue); showSource() } label: {
                        HStack(alignment: .top) {
                            Image(systemName: issue.severity == .error ? "xmark.circle" : "exclamationmark.triangle")
                                .foregroundStyle(issue.severity == .error ? .red : .orange)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(issue.message)
                                Text("第 \(issue.location.line) 行，第 \(issue.location.column) 列").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.padding(14).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
                if let report = model.analysis {
                    GroupBox("全内屏输入冲突") {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(report.inputConflicts.isEmpty ? "本次模拟未发现输入冲突" : "\(report.inputConflicts.count) 个输入冲突",
                                  systemImage: report.inputConflicts.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                                .font(.headline).foregroundStyle(report.inputConflicts.isEmpty ? .green : .orange)
                            Text("以下列出全内屏策略的冲突，并用外键重新计算；可消除项单独说明。外键和 A 区相互独立，但滑条进入 A 区仍可提前触发 Tap。").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                    ForEach(report.inputConflicts) { issue in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                                Text(String(format: "%.3f 秒 · %@", issue.target.time, issue.title)).font(.headline)
                            }
                            Text(issue.detail).font(.callout)
                            if report.mixedRecording.results[issue.id]?.grade == .critical {
                                Label("内外配合复算为 Critical：将阻挡 A 区的 Tap/Hold 改用外键。", systemImage: "checkmark.circle").font(.callout).foregroundStyle(.green)
                            } else if issue.kind == .early {
                                Text("改用外键不会撤销已发生的触屏早判；需核实滑条经过该区的时间或采用其他手法。").font(.caption).foregroundStyle(.secondary)
                            }
                            sourceButton("目标音符", note: issue.target, time: issue.target.time)
                            ForEach(issue.causes) { note in sourceButton("触发来源 · \(note.kind.rawValue)", note: note, time: issue.eventTime) }
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    }
                    GroupBox("固定区域多押") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(report.multiPressHints.count) 处同时占用超过两个外圈区域").font(.headline)
                            Text("仅统计 Tap、Hold 和尚未结束的 Hold，合并同一区域。区域数不等于手数；Touch 组与滑条手势不作手数结论。").font(.caption).foregroundStyle(.secondary)
                            if !report.multiPressHints.isEmpty {
                                DisclosureGroup("查看操作提示") {
                                    ForEach(report.multiPressHints) { hint in
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(String(format: "%.3f 秒 · ", hint.time) + hint.lanes.map { "A\($0)" }.joined(separator: " / ")).font(.callout.bold())
                                            ForEach(hint.notes) { note in sourceButton(note.kind.rawValue, note: note, time: hint.time) }
                                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                                    }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                } else if !model.isAnalyzing && !model.chart.hasErrors {
                    ContentUnavailableView("尚未运行输入冲突检查", systemImage: "checkmark.seal", description: Text("点击运行检查。修改源码或切换难度后需要重新检查。"))
                }
                if let report = model.analysis {
                    GroupBox("实验输入模拟 · 方式对比") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                ForEach(AutomaticInputMode.allCases, id: \.self) { mode in
                                    let results = report.recording(for: mode).results.values
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(mode.title).font(.headline)
                                        Text("\(results.filter { $0.grade != .critical }.count) 个非 Critical · \(results.filter { $0.grade == .miss }.count) MISS").font(.caption)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            Text("内外配合只调整与 A 区 Touch 重叠的 Tap/Hold。滑条轨迹保持相同；这些是输入方案复算，不代表无法游玩或完整双手解法。").font(.caption).foregroundStyle(.secondary)
                        }.padding(6)
                    }
                    Picker("查看模拟", selection: $inputMode) {
                        ForEach(AutomaticInputMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                }
                if let recording = model.analysis?.recording(for: inputMode) ?? model.recording {
                    let nonCritical = recording.results.values.filter { $0.grade != .critical }.sorted { $0.time == $1.time ? $0.noteID < $1.noteID : $0.time < $1.time }
                    GroupBox("区域模拟（实验）· " + (model.analysis == nil ? model.inputMode.title : inputMode.title)) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(recording.results.count) 个判定 · \(nonCritical.count) 个非 Critical 结果").font(.headline)
                            Text("这是本程序假设输入轨迹的结果，不是原版 Classic 播放成绩，尚未与 DJAuto 对齐。FAST/LATE 是模拟时间差，低判不直接代表谱面错误。").font(.caption).foregroundStyle(.secondary)
                            ForEach(nonCritical, id: \.noteID) { result in
                                if let note = model.chart.notes.first(where: { $0.id == result.noteID }) {
                                    VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        sourceButton(StudioModel.timeLabel(note.time) + " · " + note.kind.rawValue + " · " + note.area + (note.area == "C" ? "" : String(note.lane)), note: note, time: note.time)
                                        Spacer()
                                        Text(result.grade == .miss ? "未触发 / 未完成" : String(format: "%@ %.1f ms", result.difference < 0 ? "FAST" : "LATE", abs(result.difference) * 1000)).font(.caption).foregroundStyle(.secondary)
                                        Text(result.grade.title).foregroundStyle(result.grade == .miss ? .red : .orange)
                                    }
                                    if let head = recording.heads[note.id], head.difference < 0,
                                       let press = recording.lastPress(sensor: RegionJudgeEngine.sensor(note), at: head.time), abs(press.time - head.time) < 1e-8 {
                                        let causes = model.chart.notes.filter { press.noteIDs.contains($0.id) && $0.id != note.id }
                                        if !causes.isEmpty {
                                            Text("触发来源：" + causes.map { "\($0.kind.rawValue) · \(StudioModel.timeLabel($0.time)) · 第 \($0.location.line) 行" }.joined(separator: "；"))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                }
            }.padding(32).frame(maxWidth: 900, alignment: .leading)
        }
    }
    private func sourceButton(_ title: String, note: Note, time: Double) -> some View {
        Button { model.locate(note, at: time); showSource() } label: {
            Label("\(title) · 第 \(note.location.line) 行，第 \(note.location.column) 列", systemImage: "arrow.up.forward.square")
                .font(.callout)
        }.buttonStyle(.plain).foregroundStyle(.cyan)
    }
}
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("使用说明").font(.largeTitle.bold())
                Text("打开包含 maidata.txt 与 track.mp3 / track.wav 的文件夹。左侧选择难度，在源码中编写 simai，右侧实时预览。").foregroundStyle(.secondary)
                GroupBox("常用语法") { Text("(120){4} 1,2,3,4,\n1/5, 2b, 3x, 4h[4:2],\n1-5[4:1], 1w5[4:1],\nA1, C, Ch[4:1],\n1-3-5[4:1], 1-5*^3[4:1],\nE").font(.system(.body, design: .monospaced)).textSelection(.enabled).padding().frame(maxWidth: .infinity, alignment: .leading) }
                GroupBox("可视化编辑（⌘1）") {
                    Text("竖谱里时间从下往上走，左边是键 8，右边是键 1，再往右是 Touch 列和 BPM 列。先选分音，再选工具：\n1 Tap：点一下放一个。\n2 Hold：按住往上拖出长度。\n3 Slide：在竖谱上点星星头，再到右边舞台按住左键画到终点的键，经过的判定区决定形状；点已有的星星可以再加一条尾巴。\n4 Touch / 5 TouchHold：在舞台上点判定区，时间取当前播放位置。\nV 选择 · 右键删除 · ⌫ 删除选中 · B 绝赞 · X 保护 · F 烟花 · W 扇形 · ⌘Z 撤销 · 空格播放。\n每次操作只改 simai 文本里对应的那一处，切到代码编辑（⌘2）随时能看到结果。")
                        .font(.callout).padding().frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("⌘O 打开  ·  ⌘S 保存  ·  ⇧⌘C 播放/暂停  ·  ⇧⌘X 停止  ·  ⌘F 查找  ·  ⇧⌘P 独立舞台  ·  ⌥⌘←/→ 逐帧").font(.callout)
                Text("选中文字后可镜像、旋转或细分。时间轴可拖动定位，循环模式下点击 A / B 设置区间。源码中青色标记当前播放单元，橙色标记仍在持续的 Hold/Slide；跟随滚动不会移动编辑光标。修改每 15 秒保存到本地恢复目录，可通过文件菜单恢复。").foregroundStyle(.secondary)
                Text("区域模式先生成按压和滑动，再按区域队列判定；可在检查与分析中定位非 Critical 的结果。关闭区域模式后使用自动全 PERFECT。⇧⌘J 显示判定区，⇧⌘M 打开九路混音器。仍在开发的功能和兼容差异见 Documentation/Feature-audit.txt。").font(.callout).foregroundStyle(.secondary)
                Text("曲目信息使用内置 HarmonyOS Sans（鸿蒙字体）。Copyright 2021 Huawei Device Co., Ltd.；完整字体许可随应用附带。谱面保存为 UTF-8，读入支持 UTF-8 及带 BOM 的 UTF-16/UTF-32。").font(.caption).foregroundStyle(.secondary)
                Link("simai 官方语法文档", destination: URL(string: "https://w.atwiki.jp/simai/pages/1003.html")!)
                Link("Majdata 原项目", destination: URL(string: "https://github.com/LingFeng-bbben/MajdataView")!)
            }.padding(32).frame(maxWidth: 800, alignment: .leading)
        }
    }
}
