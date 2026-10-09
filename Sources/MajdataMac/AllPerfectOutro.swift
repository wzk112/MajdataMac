import SwiftUI
import MajdataCore

/// MajdataEdit GetAllPerfectStartTime: finish the last note, including Hold/Slide tails.
/// The E marker and the BGM duration do not decide when this animation starts.
struct AllPerfectOutro: Sendable {
    let startTime: Double
    var endTime: Double { startTime + 4 } // Upstream reserves four seconds for the AP and its sound.
    init?(chart: ParsedChart, recording: RegionRecording? = nil) {
        guard !chart.hasErrors, let last = chart.notes.map(\.endTime).max() else { return nil }
        if let recording {
            guard chart.notes.allSatisfy({ note in
                recording.results[note.id].map { $0.grade.rawValue <= JudgeGrade.perfect2.rawValue } ?? false
            }) else { return nil }
            startTime = max(last, recording.results.values.map(\.time).max() ?? last)
        } else { startTime = last }
    }
}

struct AllPerfectManifest: Decodable {
    struct Node: Decodable {
        let name: String, path: String
        let parent: Int
        let x: Double, y: Double, width: Double, height: Double, stretch: Double, sx: Double, sy: Double
        let color: [Double]
        let texture: String?
    }
    struct Glyph: Decodable {
        let width: Double, height: Double, x: Double, y: Double, advance: Double
    }
    let sourceCommit: String
    let nodes: [Node]
    let animation: ArtAnimation
    let glyphs: [String: Glyph]
    let fontSize: Double, pointSize: Double, lineHeight: Double
    let material: [String: Double]
    let colors: [String: [Double]]
}

@MainActor final class AllPerfectAssets {
    static let shared = AllPerfectAssets()
    let manifest: AllPerfectManifest
    let images: [String: NSImage]
    private init() {
        let root = StudioModel.resourceURL.appendingPathComponent("AllPerfect")
        do { manifest = try JSONDecoder().decode(AllPerfectManifest.self, from: Data(contentsOf: root.appendingPathComponent("outro.json"))) }
        catch { fatalError("Bundled All Perfect artwork is invalid: \(error)") }
        let names = Set(manifest.nodes.compactMap(\.texture)).union(manifest.glyphs.keys)
        images = names.reduce(into: [:]) { $0[$1] = NSImage(contentsOf: root.appendingPathComponent($1 + ".png")) }
    }
}

@MainActor enum AllPerfectDrawing {
    private struct Key: Equatable { let chart: UUID; let recording: UUID? }
    private static var cache: [(Key, AllPerfectOutro?)] = []
    static func timing(_ chart: ParsedChart, recording: RegionRecording?) -> AllPerfectOutro? {
        let key = Key(chart: chart.renderRevision, recording: recording?.revision)
        if let hit = cache.first(where: { $0.0 == key }) { return hit.1 }
        let value = AllPerfectOutro(chart: chart, recording: recording)
        cache.append((key, value)); if cache.count > 3 { cache.removeFirst() }
        return value
    }

    /// The same absolute chart clock is used for live playback, scrubbing and offline export.
    static func draw(context: inout GraphicsContext, size: CGSize, chart: ParsedChart, recording: RegionRecording?, time: Double) {
        guard let outro = timing(chart, recording: recording), time >= outro.startTime, time < outro.endTime else { return }
        let elapsed = time - outro.startTime
        let assets = AllPerfectAssets.shared, manifest = assets.manifest, clip = manifest.animation
        guard clip.value(":ifDestroy", at: elapsed, default: 0) < 0.5 else { return }
        let unit = min(size.width, size.height) / 123
        var base = context
        base.translateBy(x: size.width / 2, y: size.height / 2); base.scaleBy(x: unit, y: unit)
        var transforms: [CGAffineTransform] = []
        for n in manifest.nodes {
            func value(_ key: String, _ fallback: Double) -> Double { clip.value(n.path + ":" + key, at: elapsed, default: fallback) }
            let parent = n.parent < 0 ? CGAffineTransform.identity : transforms[n.parent]
            let sx = value("m_LocalScale.x", n.sx), sy = value("m_LocalScale.y", n.sy)
            let transform = parent.translatedBy(x: value("m_AnchoredPosition.x", n.x), y: -value("m_AnchoredPosition.y", n.y))
                .rotated(by: -value("localEulerAnglesRaw.z", 0) * .pi / 180).scaledBy(x: sx, y: sy)
            transforms.append(transform)
            guard abs(sx * sy) > 0.000001 else { continue }
            var c = base; c.concatenate(transform)
            if n.name == "APTEXT" { drawText(context: c, manifest: manifest, images: assets.images, elapsed: elapsed, scale: unit * sx) }
            else if let texture = n.texture, let image = assets.images[texture] {
                let width = n.width + n.stretch * 123, height = value("m_SizeDelta.y", n.height)
                guard width > 0, height > 0 else { continue }
                c.opacity = min(1, max(0, value("m_Color.a", n.color[3])))
                var matrix = ColorMatrix(); matrix.r1 = Float(n.color[0]); matrix.g2 = Float(n.color[1]); matrix.b3 = Float(n.color[2])
                c.addFilter(.colorMatrix(matrix))
                c.draw(Image(nsImage: image), in: CGRect(x: -width/2, y: -height/2, width: width, height: height))
            }
        }
    }

    private static func drawText(context: GraphicsContext, manifest: AllPerfectManifest, images: [String: NSImage], elapsed: Double, scale: Double) {
        let clip = manifest.animation, f = manifest.fontSize / manifest.pointSize
        func value(_ key: String, _ fallback: Double) -> Double { clip.value("APTEXT:" + key, at: elapsed, default: fallback) }
        let spacing = value("m_characterSpacing", 0) * manifest.fontSize / 100
        let line = manifest.lineHeight * f + value("m_paragraphSpacing", 0) * manifest.fontSize / 100
        let alpha = value("m_fontColor.a", 1)
        func corner(_ name: String) -> Shader.Argument {
            let rgba = ["r", "g", "b", "a"].map { value("m_fontColorGradient." + name + "." + $0, 1) }
            return .float4(Float(rgba[0]), Float(rgba[1]), Float(rgba[2]), Float(rgba[3] * alpha))
        }
        let material = manifest.material
        let outline = manifest.colors["_OutlineColor"]!
        for (row, word) in ["ALL", "PERFECT"].enumerated() {
            let glyphs = word.map { (String($0), manifest.glyphs[String($0)]!) }
            let width = glyphs.reduce(0) { $0 + $1.1.advance * f } + Double(glyphs.count - 1) * spacing
            var cursor = -width/2
            for (letter, glyph) in glyphs {
                defer { cursor += glyph.advance * f + spacing }
                guard let image = images[letter] else { continue }
                let w = glyph.width * f, h = glyph.height * f
                var c = context
                // Middle alignment around the two lines' cap-height bounds, as in the source canvas.
                c.translateBy(x: cursor + glyph.x * f, y: Double(row) * line - line/2 + 86*f/2 - glyph.y*f)
                c.addFilter(.colorShader(OriginalArt.shared.shaderLibrary.allPerfectGlyph(
                    .float2(w, h), .float(max(1, 20 * f * scale)),
                    corner("topLeft"), corner("topRight"), corner("bottomLeft"), corner("bottomRight"),
                    .float4(Float(outline[0]), Float(outline[1]), Float(outline[2]), Float(outline[3])),
                    .float(material["_OutlineWidth"]! * material["_ScaleRatioA"]!),
                    .float4(Float(material["_GlowOffset"]! * material["_ScaleRatioB"]!), Float(material["_GlowInner"]!),
                            Float(material["_GlowOuter"]! * material["_ScaleRatioB"]!), Float(material["_GlowPower"]!)))))
                c.draw(Image(nsImage: image), in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
    }
}
