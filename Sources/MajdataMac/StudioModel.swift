import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers
import MajdataCore

enum PreviewJudgementMode: String, CaseIterable {
    case classic, experimentalRegions
    var title: String { self == .classic ? "原版自动播放 / Classic" : "区域输入模拟（实验）" }
    // The old regionJudgement default accidentally replaced Classic. Do not migrate that implicit opt-in.
    static func load(_ defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: "previewJudgementMode.v2") ?? "") ?? .classic
    }
}

@MainActor @Observable final class StudioModel {
    var document = ChartDocument.blank
    var difficulty = 4
    var chart = ParsedChart() { didSet { parsedDuration = chart.duration } }
    private var parsedDuration = 0.0
    var source = ""
    var fileURL: URL?
    var musicURL: URL?
    var backgroundURL: URL?
    var videoURL: URL?
    var background: NSImage?
    var videoPlayer: AVPlayer?
    var selectedRange = NSRange(location: 0, length: 0)
    var isDirty = false
    var isPlaying = false
    var isPreparing = false
    var playWhenReady = false
    var currentTime = 0.0
    var rate = 1.0 { didSet { playback?.rate = Float(rate); if isPlaying { videoPlayer?.rate = Float(rate) } } }
    var noteSpeed = 7.5
    var touchSpeed = 7.5
    var backgroundDim = 0.65
    var fontSize = 15.0
    var follow = true
    var centerDisplay = "COMBO"
    var waveform: [Float] = []
    var mix = AudioMixSettings.load() { didSet { playback?.apply(mix); mix.save() } }
    var showSensors = UserDefaults.standard.bool(forKey: "showSensors") { didSet { UserDefaults.standard.set(showSensors, forKey: "showSensors") } }
    var showSensorPresses = UserDefaults.standard.object(forKey: "showSensorPresses") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showSensorPresses, forKey: "showSensorPresses") }
    }
    var showSensorLabels = true
    var sensorOpacity = 0.45
    var showFrameStats = false
    var showFireworks = UserDefaults.standard.object(forKey: "showFireworks") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showFireworks, forKey: "showFireworks") }
    }
    var showHitEffects = UserDefaults.standard.object(forKey: "showHitEffects") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showHitEffects, forKey: "showHitEffects") }
    }
    var showHoldParticles = UserDefaults.standard.object(forKey: "showHoldParticles") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showHoldParticles, forKey: "showHoldParticles") }
    }
    var showStageInfo = UserDefaults.standard.object(forKey: "showStageInfo") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showStageInfo, forKey: "showStageInfo") }
    }
    var videoResolution = VideoResolution(rawValue: UserDefaults.standard.string(forKey: "videoResolution") ?? "") ?? .square1080 {
        didSet { UserDefaults.standard.set(videoResolution.rawValue, forKey: "videoResolution") }
    }
    var videoCodec = VideoCodec(rawValue: UserDefaults.standard.string(forKey: "videoCodec") ?? "") ?? .hevc {
        didSet { UserDefaults.standard.set(videoCodec.rawValue, forKey: "videoCodec") }
    }
    var exportRecordingIntro = UserDefaults.standard.object(forKey: "exportRecordingIntro") as? Bool ?? true {
        didSet { UserDefaults.standard.set(exportRecordingIntro, forKey: "exportRecordingIntro") }
    }
    var exportChartInfo = UserDefaults.standard.object(forKey: "exportChartInfo") as? Bool ?? true {
        didSet { UserDefaults.standard.set(exportChartInfo, forKey: "exportChartInfo") }
    }
    var previewFrameRate = (UserDefaults.standard.object(forKey: "previewFrameRate") as? Int) ?? 60 { didSet { UserDefaults.standard.set(previewFrameRate, forKey: "previewFrameRate") } }
    var frameRate = (UserDefaults.standard.object(forKey: "frameRate") as? Int) ?? 60 { didSet { UserDefaults.standard.set(frameRate, forKey: "frameRate") } }
    var judgementMode = PreviewJudgementMode.load()
    var regionJudgement: Bool { judgementMode == .experimentalRegions }
    var inputMode = AutomaticInputMode(rawValue: UserDefaults.standard.string(forKey: "automaticInputMode") ?? "") ?? .mixed
    var recording: RegionRecording?
    var prepared: PreparedAudio?
    @ObservationIgnored var playback: AudioPlayback?
    var audioOutputName = "尚未连接"
    var audioOutputDevices = AudioOutputRouting.devices
    var audioOutputUID = UserDefaults.standard.string(forKey: "audioOutputUID") ?? "" {
        didSet {
            UserDefaults.standard.set(audioOutputUID, forKey: "audioOutputUID")
            refreshAudioOutput(.devices, force: true)
        }
    }
    var audioOutputUnavailable: Bool { !audioOutputUID.isEmpty && !audioOutputDevices.contains { $0.uid == audioOutputUID } }
    @ObservationIgnored private var audioTargetID: UInt32 = 0
    @ObservationIgnored private var outputMonitor: AudioOutputMonitor?
    var errorMessage: String?
    var status = "打开谱面文件夹，或试试内置示例"
    var recentFiles: [String] = UserDefaults.standard.stringArray(forKey: "recentCharts") ?? []
    var showFind = false
    var findText = ""
    var replacement = ""
    var analysis: ChartAnalysisReport?
    var isAnalyzing = false
    private var analysisTask: Task<Void, Never>?
    var exportProgress: Double?
    var exportStatus = ""
    var exportTask: Task<Void, Never>?
    var loopEnabled = false
    var loopStart = 0.0
    var loopEnd = 8.0
    var skinDirectory: URL?
    var skinImages: [String: NSImage] = [:]
    var taps: [Double] = []
    var tappedBPM: Double?
    var showInspector = true
    var timelineZoom = 1.0
    var timelineStart = 0.0
    var timelineFollow = true
    var timelineBeatsPerBar = 4
    var timelineSnap = false
    /// Seconds visible in the vertical track and the time at its bottom edge.
    var trackSpan = 4.0
    var trackStart = 0.0
    var trackTool = TrackTool.select { didSet { if trackTool != .slide { pendingSlide = nil } } }
    /// Grid of the vertical track: clicks land on the nearest 1/trackDivisor point.
    var trackDivisor = 8
    /// 分音:拍数 written into new slides and touch holds.
    var slideLength = "4:1"
    /// Head flags (b, x, f, w) armed for the next placed notes.
    var placementFlags: Set<Character> = []
    var pendingSlide: PendingSlide?
    var visualUndo: [VisualSnapshot] = []
    var visualRedo: [VisualSnapshot] = []
    var showSensorPattern = UserDefaults.standard.object(forKey: "showSensorPattern") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showSensorPattern, forKey: "showSensorPattern") }
    }
    var ffmpegPath = UserDefaults.standard.string(forKey: "ffmpegPath") ?? "/opt/homebrew/bin/ffmpeg"
    private var parseTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?
    private var audioRefreshTask: Task<Void, Never>?
    /// The chart changed after the current mix was rendered; the mix keeps playing until its replacement is ready.
    private(set) var audioStale = false
    private var timer: Timer?
    private var fileDate: Date?
    private var lastRecovery = Date.distantPast
    private var revision = 0
    private let audioOutputEnabled: Bool
    let recoveryDirectory: URL
    let cacheDirectory: URL
    // .app bundles resolve resourceURL to Contents/Resources (copied folder nested inside);
    // SwiftPM's flat test bundle already resolves to the copied Resources folder itself.
    static var resourceURL: URL {
        let base = Bundle.module.resourceURL!, nested = base.appendingPathComponent("Resources")
        return FileManager.default.fileExists(atPath: nested.appendingPathComponent("Original").path) ? nested : base
    }

    init(audioOutputEnabled: Bool = true) {
        self.audioOutputEnabled = audioOutputEnabled
        let fm = FileManager.default
        recoveryDirectory = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MajdataMac/Recovery")
        cacheDirectory = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MajdataMac")
        try? fm.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        source = document.chart(difficulty)
        chart = SimaiParser.parse(source)
        loadSkin(nil)
        outputMonitor = AudioOutputMonitor { [weak self] change in self?.refreshAudioOutput(change) }
        let updates = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(updates, forMode: .common); timer = updates
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkExternalChange() }
        }
    }
    var title: String { document.title.isEmpty ? "未命名谱面" : document.title }
    var stageStyle: StageStyle {
        StageStyle(noteSpeed: noteSpeed, touchSpeed: touchSpeed, dim: backgroundDim, center: centerDisplay, skin: skinImages, background: background, showSensors: showSensors, sensorLabels: showSensorLabels, sensorOpacity: sensorOpacity, recording: regionJudgement ? recording : nil, showFireworks: showFireworks, showHitEffects: showHitEffects, showHoldParticles: showHoldParticles, showSensorPresses: showSensorPresses)
    }
    /// Live previews add the zone pattern; exports keep using `stageStyle` so the video stays clean.
    var previewStageStyle: StageStyle { var style = stageStyle; style.sensorPattern = showSensorPattern; return style }
    func stepFrame(_ direction: Int) { pause(); seek(currentTime + Double(direction) / 60) }
    var rangeStart: Double { min(0, prepared?.startTime ?? (chart.notes.first?.time ?? 0) - 1) }
    var rangeEnd: Double {
        max(2, parsedDuration + 2, prepared.map { $0.startTime + $0.duration } ?? 0)
    }
    var duration: Double { rangeEnd - rangeStart }
    var combo: Int { (regionJudgement ? recording?.score(at: currentTime).combo : nil) ?? RenderTimeline.prepared(chart, speed: noteSpeed, touch: touchSpeed).score(at: currentTime).combo }
    var achievement: Double {
        if regionJudgement, let recording { return recording.score(at: currentTime).achievement }
        let timeline = RenderTimeline.prepared(chart, speed: noteSpeed, touch: touchSpeed)
        let score = timeline.score(at: currentTime)
        guard timeline.totalWeight > 0 else { return 0 }
        return floor((Double(score.weight) / Double(timeline.totalWeight) * 100 + (timeline.totalBreaks > 0 ? Double(score.breaks) / Double(timeline.totalBreaks) : 0)) * 10000) / 10000
    }
    var playbackTime: Double {
        guard isPlaying, let playback, playback.engineIsRunning, let audio = prepared else { return currentTime }
        return min(rangeEnd, max(rangeStart, playback.currentTime + audio.startTime))
    }
    func setRegionJudgement(_ value: Bool) {
        let resume = isPlaying || playWhenReady; judgementMode = value ? .experimentalRegions : .classic
        UserDefaults.standard.set(judgementMode.rawValue, forKey: "previewJudgementMode.v2")
        invalidateAudio(); prepareAudio(thenPlay: resume)
    }
    func setInputMode(_ value: AutomaticInputMode) {
        let resume = isPlaying; inputMode = value
        UserDefaults.standard.set(value.rawValue, forKey: "automaticInputMode")
        invalidateAudio(); prepareAudio(thenPlay: resume)
    }
    func setMetronome(_ value: Bool) {
        let resume = isPlaying
        mix.metronome = value; invalidateAudio(); prepareAudio(thenPlay: resume)
    }
    func saveMixDefault() { mix.save("audioMix.default.v3"); status = "已保存默认音量" }
    func restoreMixDefault() { let old = mix.metronome; mix = .load("audioMix.default.v3"); if old != mix.metronome { setMetronome(mix.metronome) } }
    func edited(_ text: String) {
        source = text; document.setChart(text, difficulty: difficulty); markDirty(); parse()
    }
    func markDirty() { isDirty = true; revision += 1; invalidateAnalysis(); audioEdited() }
    /// Edits do not stop the music: the old mix stays until a new one is rendered in the background and swapped in.
    private func audioEdited() {
        guard prepared != nil || isPreparing else { return }
        audioStale = true
        audioRefreshTask?.cancel()
        audioRefreshTask = Task { [weak self] in
            // Lets a burst of clicks or keystrokes settle, and the debounced parse finish, before rendering once.
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled, self.audioStale, !self.chart.hasErrors else { return }
            self.prepareAudio(thenPlay: self.playWhenReady, quiet: !self.isPreparing)
        }
    }
    func metadataChanged() { markDirty(); parse() }
    func invalidateAudio() {
        pause(); prepareTask?.cancel(); audioRefreshTask?.cancel(); audioStale = false
        isPreparing = false; playWhenReady = false; playback?.shutdown(); playback = nil
        audioOutputName = "尚未连接"
        if let prepared {
            try? FileManager.default.removeItem(at: prepared.url)
            try? FileManager.default.removeItem(at: prepared.url.deletingPathExtension().appendingPathExtension("stems"))
        }
        prepared = nil; recording = nil; waveform = []
    }
    func parse(immediate: Bool = false) {
        invalidateAnalysis()
        parseTask?.cancel()
        let source = source, offset = document.offset, expectedRevision = revision
        parseTask = Task {
            if !immediate { try? await Task.sleep(for: .milliseconds(220)) }
            if Task.isCancelled { return }
            let parsed = await Task.detached(priority: .userInitiated) { SimaiParser.parse(source, offset: offset) }.value
            guard !Task.isCancelled, expectedRevision == revision else { return }
            chart = parsed
            status = parsed.hasErrors ? "发现 \(parsed.diagnostics.count) 个语法问题" : "\(parsed.notes.count) 个音符 · \(String(format: "%.2f", parsed.duration)) 秒"
        }
    }
    func selectDifficulty(_ value: Int) {
        parseTask?.cancel(); invalidateAnalysis()
        document.setChart(source, difficulty: difficulty)
        difficulty = value; source = document.chart(value); selectedRange = NSRange(location: 0, length: 0); visualUndo = []; visualRedo = []; pendingSlide = nil
        revision += 1; invalidateAudio(); chart = SimaiParser.parse(source, offset: document.offset); currentTime = 0
    }
    func allowReplacing() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert(); alert.messageText = "保存当前谱面的修改？"
        alert.informativeText = "尚未保存的内容也会保留在本地恢复文件中。"
        alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "不保存")
        let result = alert.runModal()
        if result == .alertFirstButtonReturn { return save() }
        if result == .alertThirdButtonReturn { writeRecovery(); return true }
        return false
    }
    func openPanel() {
        guard allowReplacing() else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true
        panel.message = "选择 maidata.txt 或包含谱面的文件夹"
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }
    func load(_ url: URL) {
        do {
            var directory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            let file = directory.boolValue ? url.appendingPathComponent("maidata.txt") : url
            let text = try String(contentsOf: file, encoding: .utf8)
            pause(); parseTask?.cancel(); invalidateAnalysis(); revision += 1
            document = ChartDocument(text: text); fileURL = file
            difficulty = (0..<7).last(where: { !document.chart($0).isEmpty }) ?? 4
            source = document.chart(difficulty); chart = SimaiParser.parse(source, offset: document.offset); visualUndo = []; visualRedo = []; pendingSlide = nil
            currentTime = min(0, chart.notes.first?.time ?? 0); isDirty = false
            invalidateAudio(); loadMedia(file.deletingLastPathComponent())
            fileDate = modificationDate(file)
            recentFiles.removeAll { $0 == file.path }; recentFiles.insert(file.path, at: 0); recentFiles = Array(recentFiles.prefix(12))
            UserDefaults.standard.set(recentFiles, forKey: "recentCharts")
            status = "已打开 \(file.lastPathComponent) · \(chart.notes.count) 个音符"
            prepareAudio(thenPlay: false)
        } catch { report(error) }
    }
    func loadDemo() {
        guard allowReplacing() else { return }
        let demo = Self.resourceURL.appendingPathComponent("Demo")
        let dest = cacheDirectory.appendingPathComponent("Demo")
        if !FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.copyItem(at: demo, to: dest) }
        load(dest)
    }
    func newDocument() {
        guard allowReplacing() else { return }
        invalidateAnalysis()
        pause(); revision += 1; parseTask?.cancel(); document = .blank; source = document.chart(4); difficulty = 4; visualUndo = []; visualRedo = []; pendingSlide = nil
        fileURL = nil; musicURL = nil; videoURL = nil; videoPlayer = nil; background = nil; backgroundURL = nil
        invalidateAudio(); chart = SimaiParser.parse(source); currentTime = 0; isDirty = false
    }
    @discardableResult func save(as saveAs: Bool = false) -> Bool {
        document.setChart(source, difficulty: difficulty)
        var target = fileURL
        if saveAs || target == nil {
            let panel = NSSavePanel(); panel.nameFieldStringValue = "maidata.txt"; panel.allowedContentTypes = [.plainText]
            guard panel.runModal() == .OK, let url = panel.url else { return false }; target = url
        }
        guard let target else { return false }
        if !saveAs, target == fileURL, let old = fileDate, modificationDate(target) != old {
            let alert = NSAlert(); alert.messageText = "磁盘上的谱面已被其他程序修改"
            alert.informativeText = "请选择另存为以保留两个版本。"; alert.addButton(withTitle: "另存为"); alert.addButton(withTitle: "取消")
            return alert.runModal() == .alertFirstButtonReturn ? save(as: true) : false
        }
        do {
            try document.serialized.write(to: target, atomically: true, encoding: .utf8)
            fileURL = target; fileDate = modificationDate(target); isDirty = false; status = "已保存 · \(target.lastPathComponent)"; return true
        } catch { report(error); return false }
    }
    func loadMedia(_ folder: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        func find(_ names: [String]) -> URL? { names.lazy.compactMap { name in files.first { $0.lastPathComponent.lowercased() == name.lowercased() } }.first }
        musicURL = find(["track.mp3", "track.ogg", "track.wav", "track.m4a", "track.flac"])
        backgroundURL = find(["cover.png", "cover.jpg", "cover.jpeg", "bg.png", "bg.jpg", "bg.jpeg"])
        background = backgroundURL.flatMap { NSImage(contentsOf: $0) }
        videoURL = find(["pv.mp4", "mv.mp4", "bg.mp4", "pv.mov"])
        videoPlayer?.pause(); videoPlayer = videoURL.map(AVPlayer.init(url:)); videoPlayer?.isMuted = true
        videoPlayer?.actionAtItemEnd = .pause
    }
    func importMusic() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]; panel.message = "选择谱面音乐"
        if panel.runModal() == .OK, let url = panel.url { musicURL = url; invalidateAudio(); prepareAudio(thenPlay: false) }
    }
    /// `quiet` renders a replacement mix while the current one stays playable, without the preparing state.
    func prepareAudio(thenPlay: Bool, quiet: Bool = false) {
        guard !chart.hasErrors else { status = "请先修正语法错误后再播放"; return }
        prepareTask?.cancel(); playWhenReady = thenPlay
        if !quiet { isPreparing = true; status = thenPlay ? "正在准备音频，完成后播放…" : "正在准备音频…" }
        let chart = chart, music = musicURL, settings = mix, resources = Self.resourceURL, rev = revision, ffmpeg = ffmpegPath, regions = regionJudgement, inputMode = inputMode
        let destination = cacheDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        prepareTask = Task {
            do {
                let work = Task.detached(priority: .userInitiated) {
                    let recording = regions ? try RegionRecording.simulate(chart, inputMode: inputMode) : nil
                    let audio = try AudioRenderer.render(chart: chart, music: music, resources: resources, destination: destination, settings: settings, retainStems: true, ffmpeg: ffmpeg, recording: recording)
                    return (audio, recording)
                }
                let (audio, result) = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                guard !Task.isCancelled, rev == revision else {
                    try? FileManager.default.removeItem(at: destination)
                    try? FileManager.default.removeItem(at: destination.deletingPathExtension().appendingPathExtension("stems")); return
                }
                // Publish a complete playable state only after the graph is ready.
                let player = try AudioPlayback(audio, settings: mix, audioOutputEnabled: audioOutputEnabled, outputUID: audioOutputUID)
                // Replacing a mix that is still in use: carry the position and the play state across the swap.
                let resume = isPlaying
                if let old = prepared {
                    if resume { currentTime = playbackTime }
                    playback?.shutdown(); isPlaying = false
                    try? FileManager.default.removeItem(at: old.url)
                    try? FileManager.default.removeItem(at: old.url.deletingPathExtension().appendingPathExtension("stems"))
                }
                prepared = audio; recording = result; waveform = audio.waveform; connect(player); audioStale = false
                playback?.rate = Float(rate); isPreparing = false
                status = "音频已就绪 · 48 kHz · " + (regions ? "区域模拟（实验）" : "Classic 自动播放")
                let requested = playWhenReady || resume; playWhenReady = false
                if requested { play() }
            } catch {
                try? FileManager.default.removeItem(at: destination)
                try? FileManager.default.removeItem(at: destination.deletingPathExtension().appendingPathExtension("stems"))
                if !Task.isCancelled { isPreparing = false; playWhenReady = false; report(error) }
            }
        }
    }
    private func connect(_ player: AudioPlayback) {
        playback = player; audioOutputName = player.outputDevice?.name ?? "无法读取实际输出"
        audioTargetID = player.outputDeviceID ?? 0
        player.onConfigurationChange = { [weak self, weak player] in
            guard let self, let player, self.playback === player else { return }
            self.reconnectAudioOutput()
        }
    }
    private func refreshAudioOutput(_ change: AudioOutputChange, force: Bool = false) {
        let defaultID = AudioOutputRouting.defaultID
        if change != .verify || !audioOutputDevices.contains(where: { $0.id == defaultID }) || audioOutputUnavailable {
            let devices = AudioOutputRouting.devices
            if audioOutputDevices != devices { audioOutputDevices = devices }
        }
        let target = AudioOutputRouting.resolve(preferredUID: audioOutputUID, devices: audioOutputDevices,
                                                defaultID: defaultID)?.id ?? 0
        let changed = target != audioTargetID
        audioTargetID = target
        guard prepared != nil, !isPreparing || force else { return }
        let staleEngine = playback.map { $0.outputDeviceID != target || !$0.engineIsRunning } ?? false
        if force || change == .serviceRestart || changed || staleEngine { reconnectAudioOutput() }
    }
    func reconnectAudioOutput() {
        guard let audio = prepared else { return }
        let resume = isPlaying || playWhenReady
        let position = playback?.engineIsRunning == true ? playbackTime : currentTime
        pause(); playback?.shutdown(); playback = nil
        audioOutputName = "正在连接…"
        currentTime = position
        prepareTask?.cancel(); isPreparing = true; playWhenReady = resume
        status = "正在连接音频输出…"
        let expectedRevision = revision
        prepareTask = Task {
            do {
                // Coalesce device and graph notifications while CoreAudio changes format.
                try await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, expectedRevision == revision else { return }
                // Aggregate devices may be announced before their output stream is ready.
                var replacement: AudioPlayback?
                for attempt in 0..<4 {
                    try Task.checkCancellation()
                    do {
                        replacement = try AudioPlayback(audio, settings: mix, audioOutputEnabled: audioOutputEnabled, outputUID: audioOutputUID)
                        break
                    } catch {
                        if attempt == 3 { throw error }
                        try await Task.sleep(for: .milliseconds(250 * (attempt + 1)))
                    }
                }
                guard let player = replacement else { throw AudioOutputRouting.Failure.unavailable }
                try Task.checkCancellation()
                connect(player); player.rate = Float(rate); isPreparing = false
                let requested = playWhenReady; playWhenReady = false
                status = "输出已连接 · " + audioOutputName
                if requested { play() }
                else { try player.seek(currentTime - audio.startTime, playing: false) }
            } catch {
                guard !Task.isCancelled else { return }
                isPreparing = false; playWhenReady = false; audioOutputName = "连接失败"; report(error)
            }
        }
    }
    func togglePlayback() {
        if isPlaying { pause(); return }
        if isPreparing {
            playWhenReady.toggle()
            status = playWhenReady ? "正在准备音频，完成后播放…" : "正在准备音频，完成后保持暂停"
            return
        }
        // Parse the visible text before starting, including edits made within the debounce interval.
        parseTask?.cancel(); chart = SimaiParser.parse(source, offset: document.offset)
        guard !chart.hasErrors else { status = "请先修正语法错误后再播放"; return }
        if prepared == nil || playback == nil {
            if prepared != nil { invalidateAudio() }
            prepareAudio(thenPlay: true)
        } else if audioStale {
            // Starting playback right after an edit: wait for the new mix rather than play notes that are gone.
            audioRefreshTask?.cancel(); prepareAudio(thenPlay: true)
        } else { play() }
    }
    func play() {
        guard let playback, let audio = prepared else { return }
        guard let target = AudioOutputRouting.resolve(preferredUID: audioOutputUID, devices: AudioOutputRouting.devices,
                                                      defaultID: AudioOutputRouting.defaultID), playback.outputDeviceID == target.id else {
            playWhenReady = true; reconnectAudioOutput(); return
        }
        if currentTime >= rangeEnd - 0.02 { currentTime = rangeStart }
        playback.rate = Float(rate)
        do { try playback.play(at: currentTime - audio.startTime); isPlaying = true }
        catch { isPlaying = false; report(error) }
        syncVideo(play: isPlaying)
    }
    func pause() { playWhenReady = false; if isPlaying { currentTime = playbackTime }; playback?.pause(); videoPlayer?.pause(); isPlaying = false }
    func stop() { pause(); seek(rangeStart) }
    func seek(_ time: Double) {
        currentTime = min(rangeEnd, max(rangeStart, time))
        if let audio = prepared {
            do { try playback?.seek(currentTime - audio.startTime, playing: isPlaying) }
            catch { isPlaying = false; report(error) }
        }
        syncVideo(play: isPlaying)
    }
    func syncVideo(play: Bool) {
        guard let videoPlayer else { return }
        videoPlayer.pause()
        let requestedTime = max(0, currentTime), requestedRevision = revision
        videoPlayer.seek(to: CMTime(seconds: requestedTime, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, finished, requestedRevision == self.revision, play, self.isPlaying, self.currentTime >= 0 else { return }
                videoPlayer.rate = Float(self.rate)
            }
        }
    }
    func tick() {
        if isPlaying, let playback {
            if !playback.engineIsRunning { reconnectAudioOutput(); return }
            currentTime = playbackTime
            if loopEnabled, loopEnd > loopStart, currentTime >= loopEnd { seek(loopStart) }
            else if !playback.isPlaying { pause(); currentTime = rangeEnd }
            if let videoPlayer, currentTime >= 0, videoPlayer.rate == 0, currentTime < rangeEnd - 0.1 {
                if let item = videoPlayer.currentItem, item.duration.seconds.isFinite, currentTime < item.duration.seconds { syncVideo(play: true) }
            }
        }
        if isDirty && Date().timeIntervalSince(lastRecovery) > 15 { writeRecovery() }
    }
    func transform(_ transform: ChartTransform) {
        let ns = source as NSString, selected = selectedRange
        let valid = selected.length > 0 && NSMaxRange(selected) <= ns.length
        let text = valid ? ns.substring(with: selected) : source
        edited(valid ? ns.replacingCharacters(in: selected, with: transform.apply(to: text)) : transform.apply(to: text))
    }
    func subdivide() {
        let ns = source as NSString
        let valid = selectedRange.length > 0 && NSMaxRange(selectedRange) <= ns.length
        let text = valid ? ns.substring(with: selectedRange) : source
        edited(valid ? ns.replacingCharacters(in: selectedRange, with: ChartTransform.subdivide(text, factor: 2)) : ChartTransform.subdivide(text, factor: 2))
    }
    func findNext() {
        guard !findText.isEmpty else { return }
        let ns = source as NSString, start = min(ns.length, NSMaxRange(selectedRange))
        var range = ns.range(of: findText, range: NSRange(location: start, length: ns.length - start))
        if range.location == NSNotFound { range = ns.range(of: findText) }
        if range.location != NSNotFound { selectedRange = range }
    }
    func replaceAll() { guard !findText.isEmpty else { return }; edited(source.replacingOccurrences(of: findText, with: replacement)) }
    func locate(_ diagnostic: Diagnostic) {
        selectedRange = NSRange(location: diagnostic.location.offset, length: diagnostic.location.length)
        if let point = chart.timings.last(where: { $0.location.offset <= diagnostic.location.offset }) { seek(point.time) }
    }
    func locate(_ note: Note, at time: Double? = nil) {
        selectedRange = NSRange(location: note.location.offset, length: note.location.length)
        pause(); seek((time ?? note.time) - 0.4)
    }
    private func invalidateAnalysis() {
        analysisTask?.cancel(); analysisTask = nil; analysis = nil; isAnalyzing = false
    }
    func checkConflicts() {
        parseTask?.cancel(); invalidateAnalysis(); isAnalyzing = true
        let source = source, offset = document.offset, expectedRevision = revision
        analysisTask = Task {
            do {
                let worker = Task.detached(priority: .userInitiated) {
                    let parsed = SimaiParser.parse(source, offset: offset)
                    return (parsed, parsed.hasErrors ? nil : try ChartAnalysis.inspect(parsed))
                }
                let (parsed, report) = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                guard !Task.isCancelled, expectedRevision == revision else { return }
                chart = parsed; analysis = report; isAnalyzing = false
                status = parsed.hasErrors ? "请先修正语法错误，再检查输入冲突" : "谱面检查完成"
            } catch {
                guard !Task.isCancelled, expectedRevision == revision else { return }
                isAnalyzing = false; report(error)
            }
        }
    }
    func tapBPM() {
        let now = ProcessInfo.processInfo.systemUptime
        if let last = taps.last, now - last > 3 { taps = [] }
        taps.append(now); taps = Array(taps.suffix(12))
        if taps.count > 1 { tappedBPM = 60 * Double(taps.count - 1) / (taps.last! - taps.first!) }
    }
    func loadSkin(_ url: URL?) {
        skinDirectory = url
        let fallback = Self.resourceURL.appendingPathComponent("Skin")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: fallback.path)) ?? []).filter { $0.hasSuffix(".png") }
        skinImages = [:]
        for name in names {
            let custom = url.flatMap { NSImage(contentsOf: $0.appendingPathComponent(name)) }
            skinImages[String(name.dropLast(4))] = custom ?? NSImage(contentsOf: fallback.appendingPathComponent(name))
        }
    }
    func chooseSkin() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        if panel.runModal() == .OK { loadSkin(panel.url) }
    }
    func writeRecovery() {
        document.setChart(source, difficulty: difficulty); lastRecovery = Date()
        let name = fileURL?.path.data(using: .utf8)?.base64EncodedString().replacingOccurrences(of: "/", with: "_") ?? "untitled"
        let safeName = String(name.suffix(160)) + ".txt"
        do { try document.serialized.write(to: recoveryDirectory.appendingPathComponent(safeName), atomically: true, encoding: .utf8) }
        catch { status = "自动恢复文件写入失败：\(error.localizedDescription)" }
    }
    func recover() {
        let panel = NSOpenPanel(); panel.directoryURL = recoveryDirectory; panel.allowedContentTypes = [.plainText]
        guard allowReplacing(), panel.runModal() == .OK, let url = panel.url else { return }
        load(url); fileURL = nil; isDirty = true; status = "已恢复，请另存为 maidata.txt"
    }
    func checkExternalChange() {
        guard let fileURL, let fileDate, let newDate = modificationDate(fileURL), newDate != fileDate else { return }
        if !isDirty { load(fileURL) }
        else { status = "磁盘文件已变更；保存时将提示保留两个版本" }
    }
    func modificationDate(_ url: URL) -> Date? { (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
    func report(_ error: Error) { errorMessage = error.localizedDescription; status = "操作未完成" }
    static func timeLabel(_ value: Double) -> String { let v = abs(value); return String(format: "%@%02d:%06.3f", value < 0 ? "−" : "", Int(v) / 60, v.truncatingRemainder(dividingBy: 60)) }
}
