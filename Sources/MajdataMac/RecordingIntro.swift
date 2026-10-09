import SwiftUI
import CoreText
import MajdataCore

/// Recording alone adds the upstream five-second OP. Chart/PV timestamps stay unchanged.
struct RecordingOpening: Sendable {
    let startTime: Double
    let clockTimes: [Double]
    var endTime: Double { startTime + 5 }

    init(chart: ParsedChart, clockCount: String) {
        // Preserve existing pre-roll for charts whose first note is already at/before zero.
        startTime = min(0, (chart.notes.first?.time ?? 0) - 1) - 5
        let bpm = chart.timings.first?.bpm ?? 120
        let count = max(0, min(4096, Int(clockCount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0))
        clockTimes = bpm.isFinite && bpm > 0 ? (0..<count).map { Double($0) * 60 / bpm }.filter { $0 < chart.duration + 2 } : []
    }
}

struct RecordingIntro {
    let opening: RecordingOpening
    let info: StageChartInfo
}

struct RecordingIntroManifest: Decodable {
    struct Node: Decodable {
        var name: String; var path: String; var parent: Int
        var x: Double; var y: Double; var width: Double; var height: Double
        var sx: Double; var sy: Double; var color: [Double]
        var texture: String?; var field: String?; var fontSize: Double; var alignment: Int
        var rotate: Double; var wx: Double; var wy: Double; var shadow: Bool
    }
    var nodes: [Node]
    var animations: [String: ArtAnimation]
    var colors: [[Double]]
}

@MainActor final class RecordingIntroAssets {
    static let shared = RecordingIntroAssets()
    let manifest: RecordingIntroManifest
    let images: [String: NSImage]
    let fontName: String
    private init() {
        let root = StudioModel.resourceURL.appendingPathComponent("RecordingIntro")
        do { manifest = try JSONDecoder().decode(RecordingIntroManifest.self, from: Data(contentsOf: root.appendingPathComponent("intro.json"))) }
        catch { fatalError("Bundled recording intro is invalid: \(error)") }
        images = ["color", "1080Circle_Shaped", "JacketInfo", "bg_dummy"].reduce(into: [:]) {
            $0[$1] = NSImage(contentsOf: root.appendingPathComponent($1 + ($1 == "bg_dummy" ? ".jpg" : ".png")))
        }
        let fontURL = root.appendingPathComponent("Minimoon.ttf") as CFURL
        CTFontManagerRegisterFontsForURL(fontURL, .process, nil)
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL) as? [CTFontDescriptor]
        fontName = descriptors?.first.flatMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String } ?? "Helvetica-Bold"
    }
}

/// Original CanvasSongDetail coordinates (108 units high), textures and Hermite curves.
/// Animation follows the export clock, never wall time or SwiftUI implicit animations.
struct RecordingIntroView: View {
    let intro: RecordingIntro
    let cover: NSImage?
    let time: Double
    var body: some View {
        Canvas { context, size in
            let elapsed = time - intro.opening.startTime
            guard elapsed >= 0, elapsed < 5 else { return }
            let assets = RecordingIntroAssets.shared, manifest = assets.manifest
            let entry = manifest.animations["Entry"]!, showing = manifest.animations["Showing"]!
            let exitStart = entry.duration + showing.duration
            let clip = elapsed < entry.duration ? entry : (elapsed < exitStart ? showing : manifest.animations["Exit"]!)
            let local = elapsed < entry.duration ? elapsed : (elapsed < exitStart ? elapsed - entry.duration : elapsed - exitStart)
            guard clip.value(":ifDestroy", at: local, default: 0) < 0.5 else { return }
            var base = context
            base.translateBy(x: size.width / 2, y: size.height / 2)
            base.scaleBy(x: size.height / 108, y: size.height / 108)
            var transforms: [CGAffineTransform] = [], visible: [Bool] = []
            for n in manifest.nodes {
                func value(_ key: String, _ fallback: Double) -> Double { clip.value(n.path + ":" + key, at: local, default: fallback) }
                let parent = n.parent < 0 ? CGAffineTransform.identity : transforms[n.parent]
                let transform = parent.translatedBy(x: n.x + sin(elapsed * n.wx), y: -n.y - sin(elapsed * n.wy))
                    .rotated(by: -n.rotate * elapsed * 60 * .pi / 180)
                    .scaledBy(x: value("m_LocalScale.x", n.sx), y: value("m_LocalScale.y", n.sy))
                transforms.append(transform)
                let active = (n.parent < 0 || visible[n.parent]) && value("m_IsActive", 1) > 0.5
                visible.append(active)
                guard active, abs(transform.determinant) > 0.000001 else { continue }
                var c = base; c.concatenate(transform)
                if let texture = n.texture, let image = n.name == "Jacket" ? (cover ?? assets.images[texture]) : assets.images[texture] {
                    let color = n.name == "SongDetail" ? manifest.colors[min(6, max(0, intro.info.difficulty))] : n.color
                    c.opacity = value("m_Color.a", color[3])
                    var matrix = ColorMatrix(); matrix.r1 = Float(color[0]); matrix.g2 = Float(color[1]); matrix.b3 = Float(color[2])
                    c.addFilter(.colorMatrix(matrix))
                    c.draw(Image(nsImage: image), in: CGRect(x: -n.width/2, y: -n.height/2, width: n.width, height: n.height))
                }
                if let field = n.field {
                    let text: String
                    switch field {
                    case "level": text = intro.info.level.isEmpty ? "—" : intro.info.level
                    case "difficulty": text = intro.info.difficultyName
                    case "title": text = intro.info.title
                    case "artist": text = intro.info.artist
                    case "designer": text = intro.info.designer
                    default: text = field
                    }
                    // Unity's BestFit and CoreText have different font metrics. Keep long
                    // difficulty names clear of the adjacent LV. label and fit levels in the badge.
                    let fontSize = field == "level" ? min(3.6, n.fontSize) : n.fontSize
                    let textWidth = field == "level" ? min(7.6, n.width) : (field == "difficulty" ? min(14.8, n.width) : n.width)
                    var resolved = c.resolve(Text(text).font(.custom(assets.fontName, size: fontSize * 10)).foregroundStyle(.white))
                    let measured = resolved.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
                    if field == "title", measured.width > textWidth * 10 {
                        // Long titles use the card's full two-line area before shrinking.
                        // Measure every candidate at the final width so CJK/emoji wrap safely.
                        var lower = 0.01, upper = fontSize
                        for _ in 0..<12 {
                            let candidate = (lower + upper) / 2
                            let value = c.resolve(Text(text).font(.custom(assets.fontName, size: candidate * 10)).foregroundStyle(.white))
                            let size = value.measure(in: CGSize(width: textWidth * 10, height: .infinity))
                            if size.height <= n.height * 10 { lower = candidate } else { upper = candidate }
                        }
                        resolved = c.resolve(Text(text).font(.custom(assets.fontName, size: lower * 10)).foregroundStyle(.white))
                        c.scaleBy(x: 0.1, y: 0.1)
                        c.draw(resolved, in: CGRect(x: -textWidth * 5, y: -n.height * 5, width: textWidth * 10, height: n.height * 10))
                        continue
                    }
                    let fit = min(1, textWidth * 10 / max(0.001, measured.width), n.height * 10 / max(0.001, measured.height))
                    resolved = c.resolve(Text(text).font(.custom(assets.fontName, size: fontSize * fit * 10)).foregroundStyle(.white))
                    let horizontal = n.alignment % 3, vertical = n.alignment / 3
                    let anchor = UnitPoint(x: Double(horizontal)/2, y: Double(vertical)/2)
                    if field == "level" { c.translateBy(x: 0.74, y: 0) }
                    c.scaleBy(x: 0.1, y: 0.1)
                    if n.shadow { c.addFilter(.shadow(color: .black, radius: 0, x: 2, y: -2)) }
                    c.draw(resolved, at: CGPoint(x: (anchor.x - 0.5)*n.width*10, y: (anchor.y - 0.5)*n.height*10), anchor: anchor)
                }
            }
            // Keep the original circular wipe, with the requested black surround.
            do {
                let diameter = 10.8 * clip.value("Mask:m_LocalScale.x", at: local, default: 10)
                var mask = Path(CGRect(x: -54, y: -54, width: 108, height: 108))
                mask.addEllipse(in: CGRect(x: -diameter/2, y: -diameter/2, width: diameter, height: diameter))
                base.fill(mask, with: .color(.black), style: FillStyle(eoFill: true))
            }
        }.allowsHitTesting(false).accessibilityLabel("录制开场 · \(intro.info.difficultyName) · \(intro.info.title)")
    }
}

private extension CGAffineTransform {
    var determinant: CGFloat { a * d - b * c }
}
