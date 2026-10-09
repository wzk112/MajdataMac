import SwiftUI
import MajdataCore

/// Serialized directly from the GPL MajdataView prefabs and AnimationClips.
struct ArtNode: Decodable {
    var name: String; var path: String; var parent: Int
    var x: Double; var y: Double; var sx: Double; var sy: Double; var angle: Double
    var sprite: String?; var color: [Double]; var enabled: Bool; var order: Int
}
struct ArtTexture: Decodable { var width: Double; var height: Double; var ppu: Double; var pivot: Point }
struct ArtAnimation: Decodable {
    var duration: Double
    var curves: [String: [[Double?]]]
    func value(_ property: String, at time: Double, default fallback: Double) -> Double {
        guard let keys = curves[property], let first = keys.first, let last = keys.last else { return fallback }
        if time <= first[0]! { return first[1]! }
        if time >= last[0]! { return last[1]! }
        guard let index = keys.indices.dropLast().first(where: { time < keys[$0 + 1][0]! }) else { return fallback }
        let a = keys[index], b = keys[index + 1], span = b[0]! - a[0]!
        guard let outSlope = a[3], let inSlope = b[2] else { return a[1]! }
        let t = (time - a[0]!) / span
        if Int(a[4]!) & 2 != 0 || Int(b[4]!) & 1 != 0 {
            // Unity's weighted tangents are cubic Bezier handles in time/value space.
            let ow = Int(a[4]!) & 2 != 0 ? a[6]! : 1 / 3.0
            let iw = Int(b[4]!) & 1 != 0 ? b[5]! : 1 / 3.0
            func bezier(_ u: Double, _ p: Double, _ q: Double, _ end: Double) -> Double {
                let v = 1 - u; return 3 * v * v * u * p + 3 * v * u * u * q + u * u * u * end
            }
            var lo = 0.0, hi = 1.0
            for _ in 0..<24 { let u = (lo + hi) / 2; if bezier(u, ow, 1 - iw, 1) < t { lo = u } else { hi = u } }
            return a[1]! + bezier((lo + hi) / 2, outSlope * span * ow, b[1]! - a[1]! - inSlope * span * iw, b[1]! - a[1]!)
        }
        let t2 = t * t, t3 = t2 * t
        return (2*t3 - 3*t2 + 1)*a[1]! + (t3 - 2*t2 + t)*span*outSlope
            + (-2*t3 + 3*t2)*b[1]! + (t3 - t2)*span*inSlope
    }
}
struct ArtManifest: Decodable {
    struct Particles: Decodable { var lifetime: Double; var rate: Double; var size: Double; var alpha: [[Double]] }
    var holdParticles: Particles
    var sourceCommit: String
    var textures: [String: ArtTexture]
    var prefabs: [String: [ArtNode]]
    var slides: [String: [ArtNode]]
    var animations: [String: ArtAnimation]
    var areaSteps: [String: [Int]]
}
@MainActor final class OriginalArt {
    static let shared = OriginalArt()
    let manifest: ArtManifest
    let images: [String: NSImage]
    let defaultSkin: [String: NSImage]
    let shaderLibrary: ShaderLibrary
    private init() {
        let root = StudioModel.resourceURL
        let folder = root.appendingPathComponent("Original")
        do { manifest = try JSONDecoder().decode(ArtManifest.self, from: Data(contentsOf: folder.appendingPathComponent("art.json"))) }
        catch { fatalError("Bundled Majdata artwork is invalid: \(error)") }
        images = manifest.textures.reduce(into: [:]) { $0[$1.key] = NSImage(contentsOf: folder.appendingPathComponent($1.key + ".png")) }
        let skin = root.appendingPathComponent("Skin")
        defaultSkin = ((try? FileManager.default.contentsOfDirectory(atPath: skin.path)) ?? []).reduce(into: [:]) {
            if $1.hasSuffix(".png") { $0[String($1.dropLast(4))] = NSImage(contentsOf: skin.appendingPathComponent($1)) }
        }
        shaderLibrary = ShaderLibrary(url: root.appendingPathComponent("MajdataShaders.metallib"))
    }
}

/// Pure equations from TapBase, HoldDrop, TouchDrop and BreakShineController.
enum NoteMotion {
    static func velocity(setting: Double) -> Double { 107.25 / (71.4184491 * pow(max(0.01, setting + 0.9975), -0.985558604)) }
    static func distance(delta: Double, speed: Double) -> Double { delta * max(0.01, speed) + 4.8 }
    static func scale(distance: Double) -> Double { min(1, max(0, distance * 0.4 + 0.51)) }
    static func touchDuration(speed: Double) -> Double { 3.209385682 * pow(max(0.01, speed), -0.9549621752) }
    static func touchDistance(delta: Double, speed: Double) -> Double {
        min(0.4, max(0, -exp(8 * (min(0, delta) * 0.4 / (0.8 * touchDuration(speed: speed))) - 0.85) + 0.42))
    }
    static func brightness(time: Double) -> Double { 0.95 + max(sin(time * 60 * 0.17) * 0.5, 0) }
    static func hiddenBars(progress: Double, steps: [Int]) -> Int {
        guard !steps.isEmpty else { return 0 }
        return steps[Int(min(1, max(0, progress)) * Double(steps.count - 1))]
    }
}

/// All sizes below use original Unity world units (100 sprite pixels per unit).
@MainActor final class SpriteFrameResources {
    private var images: [ObjectIdentifier: GraphicsContext.ResolvedImage] = [:]
    func resolve(_ image: NSImage, in context: GraphicsContext) -> GraphicsContext.ResolvedImage {
        let key = ObjectIdentifier(image)
        if let resolved = images[key] { return resolved }
        let resolved = context.resolve(Image(nsImage: image))
        images[key] = resolved
        return resolved
    }
}

@MainActor struct SpritePainter {
    var context: GraphicsContext
    let skin: [String: NSImage]
    var resources = SpriteFrameResources()
    let art = OriginalArt.shared

    func sprite(_ name: String, at p: Point = Point(0, 0), angle: Double = 0,
                sx: Double = 1, sy: Double? = nil, opacity: Double = 1,
                color: [Double] = [1,1,1,1], brightness: Double = 1,
                height: Double? = nil, shader: Shader? = nil) {
        guard opacity > 0.001, abs(sx) > 0.0001, let image = skin[name] ?? art.defaultSkin[name] ?? art.images[name] else { return }
        let original = art.manifest.textures[name]
        let ppu = original?.ppu ?? 100
        // PNG DPI metadata affects NSImage.size. Unity sizes sprites by pixels, never points.
        let pixelWidth = original?.width ?? Double(image.representations.first?.pixelsWide ?? 122)
        let pixelHeight = original?.height ?? Double(image.representations.first?.pixelsHigh ?? 122)
        let w = pixelWidth / ppu, h = height ?? pixelHeight / ppu
        var c = context
        c.translateBy(x: p.x, y: p.y); c.rotate(by: .degrees(angle)); c.scaleBy(x: sx, y: sy ?? sx)
        c.opacity *= opacity * color[3]
        if brightness != 1 || color[0...2].contains(where: { $0 != 1 }) {
            var matrix = ColorMatrix()
            matrix.r1 = Float(color[0] * brightness); matrix.g2 = Float(color[1] * brightness); matrix.b3 = Float(color[2] * brightness)
            c.addFilter(.colorMatrix(matrix))
        }
        if let shader { c.addFilter(.colorShader(shader)) }
        // Resolve each texture once per frame, shared by arrows, particles and masks.
        // Keeping this frame-local also respects skin/environment changes immediately.
        let drawImage = resources.resolve(image, in: context)
        if let height, name.hasPrefix("hold"), pixelHeight > 116 {
            // 58 px endcaps stay intact while only the middle of a Hold stretches.
            let cap = min(0.58, height / 2), sourceH = pixelHeight / ppu
            for (sourceY, sourceSize, targetY, targetSize) in [(0.0, 0.58, -h/2, cap), (0.58, sourceH-1.16, -h/2+cap, h-2*cap), (sourceH-0.58, 0.58, h/2-cap, cap)] {
                guard targetSize > 0 else { continue }
                var slice = c
                slice.clip(to: Path(CGRect(x: -w/2, y: targetY, width: w, height: targetSize)))
                let factor = targetSize / sourceSize
                slice.draw(drawImage, in: CGRect(x: -w/2, y: targetY-sourceY*factor, width: w, height: sourceH*factor))
            }
        } else {
            c.draw(drawImage, in: CGRect(x: -w/2, y: -h/2, width: w, height: h))
        }
    }

    func effect(_ prefab: String, animation: String, elapsed: Double, at p: Point,
                angle: Double = 0, replace: [String: String] = [:], absoluteTime: Double = 0) {
        guard let nodes = art.manifest.prefabs[prefab], let clip = art.manifest.animations[animation],
              elapsed >= 0, elapsed <= clip.duration else { return }
        var base = context; base.translateBy(x: p.x, y: p.y); base.rotate(by: .degrees(angle))
        var transforms: [CGAffineTransform] = []
        for (index, n) in nodes.enumerated() {
            func val(_ key: String, _ fallback: Double) -> Double { clip.value(n.path + ":" + key, at: elapsed, default: fallback) }
            // Caller supplies the scene's root placement; local child hierarchy is retained.
            let x = val("m_LocalPosition.x", index == 0 ? 0 : n.x)
            let y = val("m_LocalPosition.y", index == 0 ? 0 : n.y)
            let rotation = val("localEulerAnglesRaw.z", index == 0 ? 0 : n.angle)
            let sx = val("m_LocalScale.x", n.sx), sy = val("m_LocalScale.y", n.sy)
            let parent = n.parent >= 0 ? transforms[n.parent] : .identity
            let transform = parent.translatedBy(x: x, y: -y).rotated(by: -rotation * .pi/180).scaledBy(x: sx, y: sy)
            transforms.append(transform)
            guard val("m_Enabled", n.enabled ? 1 : 0) > 0.5, let name = replace[n.name] ?? n.sprite else { continue }
            var c = base; c.concatenate(transform)
            let color = [val("m_Color.r", n.color[0]), val("m_Color.g", n.color[1]), val("m_Color.b", n.color[2]), val("m_Color.a", n.color[3])]
            var shader: Shader?
            if name == "Firework_new" {
                shader = art.shaderLibrary.hanabi(.float2(10.8, 10.8), .float(absoluteTime), .float(val("material._Alpha", 0.589)))
            }
            SpritePainter(context: c, skin: skin, resources: resources).sprite(name, color: color,
                brightness: val("material._Brightness", 1), shader: shader)
        }
    }
}
