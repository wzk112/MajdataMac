import SwiftUI
import MajdataCore

@MainActor enum StageDrawing {
    static func draw(context: inout GraphicsContext, size: CGSize, chart: ParsedChart, time: Double, style: StageStyle) {
        let unit = min(size.width, size.height) / 11.465929
        var world = context
        world.translateBy(x: size.width / 2, y: size.height / 2)
        world.scaleBy(x: unit, y: unit)
        StageRenderer(worldScale: unit, timeline: RenderTimeline.prepared(chart, speed: style.noteSpeed, touch: style.touchSpeed), painter: SpritePainter(context: world, skin: style.skin), chart: chart, time: time, style: style).draw()
    }
}

@MainActor private struct StageRenderer {
    let worldScale: Double
    let timeline: RenderTimeline
    let painter: SpritePainter
    let chart: ParsedChart
    let time: Double
    let style: StageStyle
    var noteVelocity: Double { NoteMotion.velocity(setting: style.noteSpeed) }
    var art: OriginalArt { painter.art }
    func lane(_ n: Int, _ radius: Double) -> Point { SlideGeometry.lane(n, radius: radius) }
    func suffix(_ n: Note) -> String { n.isBreak ? "_break" : (n.isEach ? "_each" : "") }
    func touchPoint(_ n: Note) -> Point {
        let p = SlideGeometry.touch(n.area, lane: n.lane); return Point(p.x * 4.8, p.y * 4.8)
    }
    func result(_ note: Note) -> JudgeResult? { style.recording?.results[note.id] }
    func finish(_ note: Note) -> Double { result(note)?.time ?? note.endTime }
    func grade(_ note: Note) -> JudgeGrade { result(note)?.grade ?? .critical }
    func draw() {
        painter.sprite("outline")
        let visible = timeline.visible(at: time)
        if style.showSensors { drawSensors(visible) }
        drawCenter()
        for note in visible.reversed() where note.kind == .slide { drawSlide(note) }
        drawGuides(visible)
        for note in visible.reversed() where note.kind != .slide {
            if note.kind == .touch || note.kind == .touchHold { drawTouch(note, visible: visible) }
            else { drawRingNote(note, visible: visible) }
        }
        for note in visible { drawJudgement(note) }
    }
    func drawSensors(_ visible: [Note]) {
        let active = style.recording?.highlightedSensors(at: time) ?? SensorGeometry.active(notes: visible, at: time)
        let buttons = style.recording?.highlightedButtons(at: time) ?? []
        for n in 1...8 {
            var context = painter.context
            context.rotate(by: .degrees(Double(n - 1) * 45 + 22.5))
            let key = Path(roundedRect: CGRect(x: -0.39, y: -5.45, width: 0.78, height: 0.24), cornerRadius: 0.09)
            context.fill(key, with: .color(.cyan.opacity(buttons.contains(n) ? 0.95 : style.sensorOpacity * 0.12)))
            context.stroke(key, with: .color(.cyan.opacity(buttons.contains(n) ? 1 : style.sensorOpacity)), lineWidth: 0.02)
        }
        let assets = SensorRenderCache.prepared(scale: worldScale, context: painter.context)
        for item in assets.items {
            let context = painter.context, on = active.contains(item.region.id), color = item.color
            context.fill(item.path, with: .color(color.opacity(style.sensorOpacity * (on ? 0.65 : 0.07))))
            context.stroke(item.path, with: .color(color.opacity(on ? 1 : style.sensorOpacity)), lineWidth: on ? 0.035 : 0.012)
            if style.sensorLabels {
                var labels = context
                labels.scaleBy(x: 1 / worldScale, y: 1 / worldScale)
                labels.draw(on ? item.on : item.off, at: item.center)
            }
        }
    }
    func drawGuides(_ visible: [Note]) {
        let heads = visible.filter { $0.kind == .tap || $0.kind == .hold }
        for note in heads where time < finish(note) {
            let distance = NoteMotion.distance(delta: time - note.time, speed: noteVelocity * note.speed)
            guard NoteMotion.scale(distance: distance) > 0.3 else { continue }
            painter.sprite(note.isBreak ? "Break" : (note.isEach ? "Each" : "Normal"), angle: Double(note.lane - 1) * 45 + 22.5,
                           sx: min(4.8, max(1.225, distance)) / 4.8)
        }
        let groups = Dictionary(grouping: heads.filter { $0.isEach && time < $0.time }, by: { $0.time })
        for group in groups.values where group.count > 1 {
            let a = group[0], b = group[1]
            var start = a.lane, length = (b.lane - a.lane + 8) % 8
            if length > 4 { start = b.lane; length = 8 - length }
            guard length > 0 else { continue }
            let distance = NoteMotion.distance(delta: time - a.time, speed: noteVelocity * a.speed)
            guard NoteMotion.scale(distance: distance) > 0.3 else { continue }
            painter.sprite("EachLine\(length)", angle: Double(start - 1) * 45, sx: max(1.225, distance) / 4.8)
        }
    }
    func drawRingNote(_ note: Note, visible: [Note]) {
        guard time < finish(note) else { return }
        let dt = time - note.time, speed = noteVelocity * note.speed
        let distance = NoteMotion.distance(delta: dt, speed: speed)
        let scale = NoteMotion.scale(distance: distance)
        guard scale > 0 else { return }
        let rotation = 22.5 + Double(note.lane - 1) * 45
        let brightness = note.isBreak ? NoteMotion.brightness(time: time) : 1
        let exColor: [Double] = note.isBreak || note.isEach ? [1, 0.995, 0.467, 1] : [1, 0.675, 0.883, 1]
        if note.kind == .hold {
            let head = min(4.8, max(1.225, distance))
            let tailDistance = NoteMotion.distance(delta: time - note.endTime, speed: speed)
            let tail = max(1.225, tailDistance)
            let h = distance < 1.225 ? 1.42 : head - tail + 1.4
            let p = lane(note.lane, (head + tail) / 2)
            let active = dt >= 0.1 && note.duration > 0.3
            let shine = active ? art.manifest.animations["HoldShine"]!.value(":material._Brightness", at: (dt - 0.1).truncatingRemainder(dividingBy: 0.26666668), default: 1) : brightness
            painter.sprite("hold" + suffix(note) + (active ? "_on" : ""), at: p, angle: rotation, sx: scale, brightness: shine, height: h)
            if note.isEX { painter.sprite("hold_ex", at: p, angle: rotation, sx: scale, color: exColor, height: h) }
            if tailDistance >= 1.225 { painter.sprite(note.isBreak ? "Hold_Break_End" : (note.isEach ? "Hold_Each_End" : "Hold_End"), at: lane(note.lane, tail - 0.0175), angle: rotation) }
            if dt >= 0 { drawSustain(at: lane(note.lane, 4.8), elapsed: dt) }
        } else {
            let slides = visible.filter { $0.kind == .slide && $0.time == note.time && $0.lane == note.lane }
            let doubled = note.isStar && slides.count > 1
            let p = lane(note.lane, min(4.8, max(1.225, distance)))
            var angle = 0.0
            if note.isStar {
                if note.starSpin == 2 { angle -= max(0, time - note.time + 6.075 / max(0.01, speed)) * 400 }
                else if let slide = slides.first {
                    let duration = slide.segments.reduce(0) { $0 + $1.duration }
                    angle += max(0, time - note.time + 6.075 / max(0.01, speed)) * 180 / max(0.01, duration)
                }
            }
            let base = note.isStar ? "star" : "tap"
            // A fan of slides with no other simultaneous note uses the blue double star.
            let each = doubled && !note.isBreak && visible.filter({ $0.time == note.time && $0.kind != .slide }).count == 1 ? "" : suffix(note)
            painter.sprite(base + each + (doubled ? "_double" : ""), at: p, angle: angle, sx: scale, brightness: brightness)
            if note.isEX { painter.sprite(base + "_ex" + (doubled ? "_double" : ""), at: p, angle: angle, sx: scale, color: exColor) }
        }
    }
    func drawTouch(_ note: Note, visible: [Note]) {
        guard time < finish(note) else { return }
        let dt = time - note.time, speed = style.touchSpeed * note.speed
        let whole = NoteMotion.touchDuration(speed: speed)
        guard dt >= -whole else { return }
        let alpha = min(1, max(0, (whole + dt) / (0.2 * whole)))
        let distance = 0.226 + NoteMotion.touchDistance(delta: dt, speed: speed)
        let p = touchPoint(note), isHold = note.kind == .touchHold
        let rotations: [Double] = isHold ? [135, 45, 315, 225] : [180, 90, 0, 270]
        for i in 0..<4 {
            let a = (isHold ? Double.pi / 4 : 0) + Double(i) * .pi / 2
            let pos = Point(p.x + distance * sin(a), p.y - distance * cos(a))
            painter.sprite(isHold ? "touchhold_\(i)" : "touch" + (note.isEach ? "_each" : ""), at: pos, angle: -rotations[i], opacity: alpha)
        }
        painter.sprite("touch_point" + (note.isEach && !isHold ? "_each" : ""), at: p, opacity: alpha)
        if isHold && dt > -0.8 * whole {
            var masked = painter.context
            masked.translateBy(x: p.x, y: p.y)
            // Original CircleMask alpha encodes the clockwise sweep; preserve its shape.
            masked.clipToLayer(options: .inverse) { mask in
                mask.addFilter(.alphaThreshold(min: min(1, max(0, 0.91 * dt / max(0.001, note.duration)))))
                SpritePainter(context: mask, skin: style.skin, resources: painter.resources).sprite("CircleMask")
            }
            SpritePainter(context: masked, skin: style.skin, resources: painter.resources).sprite("touchhold_border")
            if dt >= 0 { drawSustain(at: p, elapsed: dt) }
        } else if !isHold {
            let overlaps = visible.filter { $0.kind == .touch && $0.area == note.area && $0.lane == note.lane && $0.time > note.time && $0.time - time <= whole }.count
            if overlaps > 0 { painter.sprite("touch_border_\(min(3, overlaps + 1))" + (note.isEach ? "_each" : ""), at: p, opacity: alpha) }
            if dt > -0.02 { painter.sprite("touch_just", at: p) }
        }
    }
    func drawSustain(at p: Point, elapsed: Double) {
        guard style.showHoldParticles else { return }
        let particle = art.manifest.holdParticles
        let last = Int(elapsed * particle.rate)
        for index in max(0, last - Int(ceil(particle.lifetime * particle.rate)))...last {
            let age = elapsed - Double(index) / particle.rate
            guard age >= 0, age < particle.lifetime else { continue }
            let progress = age / particle.lifetime
            let keys = particle.alpha
            let i = min(keys.count - 2, keys.indices.dropLast().first(where: { progress <= keys[$0+1][0] }) ?? keys.count - 2)
            let u = (progress - keys[i][0]) / (keys[i+1][0] - keys[i][0])
            let alpha = keys[i][1] + (keys[i+1][1] - keys[i][1]) * u
            let size = particle.size * art.manifest.animations["HoldParticleSize"]!.value(":size", at: progress, default: 1)
            let width = art.manifest.textures["CircleMiss"]!.width / 100
            painter.sprite("CircleMiss", at: p, sx: size / width, opacity: alpha, color: [1, 0.93, 0.61, 1])
        }
    }

    func drawSlide(_ note: Note) {
        let dt = time - note.time, speed = max(0.01, noteVelocity * note.speed)
        let fadeStart = -3.926913 / speed, fadeLength = min(0.2, -fadeStart)
        guard dt >= fadeStart else { return }
        let fade = min(1, max(0, (dt - fadeStart) / fadeLength))
        let opacity = dt >= -0.05 ? 1 : fade * fade * (3 - 2 * fade) * 0.55
        for (segmentIndex, segment) in note.segments.enumerated() {
            guard let key = SlideGeometry.key(for: segment), let nodes = art.manifest.slides[key.name] else { continue }
            let progress = min(1, max(0, (time - segment.startTime) / max(0.001, segment.duration)))
            let isWifi = key.name == "wifi"
            let hidden = style.recording?.hiddenBars(note: note.id, segment: segmentIndex, at: time) ?? NoteMotion.hiddenBars(progress: progress, steps: art.manifest.areaSteps[key.name] ?? [])
            let worldAngle = Double(segment.start - (key.mirror ? 0 : 1)) * 45
            func position(_ n: ArtNode) -> Point {
                SlideGeometry.rotated(Point(key.mirror ? -n.x : n.x, -n.y), angle: worldAngle * .pi/180)
            }
            if style.recording != nil ? time < finish(note) : progress < 1 {
                for (index, node) in nodes.dropLast().enumerated().reversed() where index >= hidden {
                    let name = isWifi ? "wifi" + suffix(note) + "_\(index)" : "slide" + suffix(note)
                    // Mirroring reflects geometry, while Unity's world rotation keeps the original bar angle.
                    painter.sprite(name, at: position(node), angle: worldAngle + (key.mirror ? node.angle : -node.angle),
                                   sx: node.sx * (key.mirror ? -1 : 1), sy: node.sy,
                                   opacity: isWifi && dt < -0.05 ? opacity / 0.55 : opacity,
                                   brightness: note.isBreak ? NoteMotion.brightness(time: time) : 1)
                }
                let waiting = time < segment.startTime
                let alpha = waiting ? (segmentIndex == 0 ? min(1, max(0, dt / max(0.001, segment.startTime - note.time))) : 0) : 1
                let scale = waiting ? alpha + 0.5 : 1.5
                if progress < 1 && hidden < nodes.count - 1 {
                if isWifi {
                    for i in 0..<3 {
                        let end = (segment.end - 2 + i + 8) % 8 + 1
                        let pos = lane(segment.start, 4.8).interpolated(to: lane(end, 4.8), at: progress)
                        painter.sprite("star" + suffix(note), at: pos, angle: 22.5 * Double(8 + i + 2 * (segment.start - 1)), sx: scale, opacity: alpha,
                                       brightness: note.isBreak ? NoteMotion.brightness(time: time) : 1)
                    }
                } else {
                    let points = [lane(segment.start, 4.8)] + nodes.dropLast().map(position) + [lane(segment.end, 4.8)]
                    let pos = SlideGeometry.position(on: points, progress: progress)
                    var rawAngles = nodes.dropLast().map { worldAngle - $0.angle - 18 }
                    if nodes.count >= 3 {
                        let lastPoint = points[points.count - 2], end = points[points.count - 1]
                        let cosine = (lastPoint.x * end.x + lastPoint.y * end.y) / max(0.00001, hypot(lastPoint.x, lastPoint.y) * hypot(end.x, end.y))
                        var delta = acos(min(1, max(-1, cosine))) * 180 / .pi
                        func unityAngle(_ n: ArtNode) -> Double { (n.angle - worldAngle + 1080).truncatingRemainder(dividingBy: 360) }
                        if unityAngle(nodes[nodes.count - 2]) - unityAngle(nodes[nodes.count - 3]) < 0 { delta = -delta }
                        rawAngles.append(rawAngles.last! - delta)
                    }
                    let ip = Double(points.count - 1) * progress
                    let i = min(rawAngles.count - 1, Int(ip)), j = min(rawAngles.count - 1, i + 1)
                    var delta = (rawAngles[j] - rawAngles[i]).truncatingRemainder(dividingBy: 360)
                    if delta > 180 { delta -= 360 }; if delta < -180 { delta += 360 }
                    let relative = Int(key.name.dropFirst(2)) ?? 0
                    let flip = key.name.hasPrefix("pq") ? key.mirror == (relative == 7 || relative == 8) : key.mirror
                    let angle = rawAngles[i] + delta * (ip - floor(ip)) + (flip ? 180 : 0)
                    painter.sprite("star" + suffix(note), at: pos, angle: angle, sx: scale, opacity: alpha,
                                   brightness: note.isBreak ? NoteMotion.brightness(time: time) : 1)
                }
                }
            } else if segmentIndex == note.segments.count - 1, let judge = nodes.last {
                let elapsed = time - finish(note)
                guard let clip = art.manifest.animations[note.isBreak ? "JudgeBreakShine" : "StarOver"], elapsed <= clip.duration else { continue }
                let right: Bool
                if [">", "<", "^"].contains(segment.shape) { right = !key.mirror }
                else if isWifi { right = [1, 2, 7, 8].contains(segment.end) }
                else { right = (1...4).contains(segment.end) }
                let base = isWifi ? "just_wifi_" : (judge.name.contains("curv") ? "just_curv_" : "just_str_")
                var name = base + (isWifi ? (right ? "u" : "d") : (right ? "r" : "l"))
                let grade = grade(note)
                if grade == .miss { name = name.replacingOccurrences(of: "just_", with: "miss_") }
                else if grade.rawValue >= JudgeGrade.great1.rawValue {
                    name += (result(note)?.difference ?? 0) < 0 ? "_fast_" : "_late_"
                    name += grade == .good ? "gd" : "gr"
                }
                var angle = worldAngle + (key.mirror ? judge.angle : -judge.angle), pos = position(judge)
                if isWifi && !right { angle += 180 }
                if base == "just_str_" && right == key.mirror {
                    angle += 180
                    pos.x -= sin(angle * .pi/180) * 0.27; pos.y += cos(angle * .pi/180) * 0.27
                }
                painter.sprite(name, at: pos, angle: angle,
                               opacity: clip.value(":m_Color.a", at: elapsed, default: 1),
                               brightness: clip.value(":material._Brightness", at: elapsed, default: 1))
            }
        }
    }
    func drawJudgement(_ note: Note) {
        guard note.kind != .slide else { return }
        let elapsed = time - finish(note)
        guard elapsed >= 0, elapsed < 1.4 else { return }
        let touch = note.kind == .touch || note.kind == .touchHold
        let p = touch ? touchPoint(note) : lane(note.lane, 4.8)
        if style.showHitEffects && grade(note) != .miss {
        if note.kind == .touch {
            painter.effect("TouchEffect", animation: "touch", elapsed: elapsed, at: p)
        } else {
            painter.effect("Tap_Effect", animation: note.isBreak ? "breakEffect" : "tapEffect", elapsed: elapsed * (note.isBreak ? 0.9 : 1), at: p,
                           angle: touch ? -90 : 22.5 + Double(note.lane - 1) * 45, replace: ["Tap_Effect": "Hex", "Hex": "Hex"])
        }
        }
        let clipName = touch ? "TouchJudge" : (note.isBreak ? "JudgeBreak" : "JudgePerfect")
        if let clip = art.manifest.animations[clipName], elapsed <= clip.duration {
            let r = hypot(p.x, p.y)
            let textPoint = touch ? (r < 0.01 ? Point(0, 0.6) : Point(p.x * (r - 0.46) / r, p.y * (r - 0.46) / r)) : lane(note.lane, 3.92)
            let angle = touch && r < 0.01 ? 0 : atan2(p.x, -p.y) * 180 / .pi
            let scale = clip.value("JudgeObject:m_LocalScale.x", at: elapsed, default: 1)
            let path = note.isBreak && !touch ? "JudgeObject/JudgeCPBreak" : "JudgeObject/JudgeCPNormal"
            let alpha = clip.value(path + ":m_Color.a", at: elapsed, default: 1)
            let name: String
            switch grade(note) {
            case .critical: name = note.isBreak ? "judge_text_break" : "judge_text_cPerfect"
            case .perfect1, .perfect2: name = "judge_text_perfect"
            case .great1, .great2, .great3: name = "judge_text_great"
            case .good: name = "judge_text_good"
            case .miss: name = "judge_text_miss"
            }
            painter.sprite(name, at: textPoint, angle: angle, sx: scale, opacity: alpha)
        }
        if style.showFireworks && note.isFirework && grade(note) != .miss { painter.effect("Firework", animation: "fire", elapsed: elapsed, at: p, absoluteTime: time) }
    }
    func drawCenter() {
        guard style.center != "NONE" else { return }
        let completed = timeline.score(at: time)
        var value = "\(completed.combo)"
        if style.center == "DX SCORE" { value = "\(completed.combo * 3)" }
        if style.center == "ACHIEVEMENT" {
            let normal = timeline.totalWeight > 0 ? Double(completed.weight) / Double(timeline.totalWeight) * 100 : 0
            let bonus = timeline.totalBreaks > 0 ? Double(completed.breaks) / Double(timeline.totalBreaks) : 0
            value = String(format: "%.4f%%", floor((normal + bonus) * 10000) / 10000)
        }
        if let score = style.recording?.score(at: time) {
            if style.center == "COMBO" { value = "\(score.combo)" }
            else if style.center == "DX SCORE" { value = "\(score.dx)" }
            else if style.center == "ACHIEVEMENT" { value = String(format: "%.4f%%", floor((score.achievement + 1e-10) * 10000) / 10000) }
        }
        var text = painter.context
        text.scaleBy(x: 1 / worldScale, y: 1 / worldScale)
        text.draw(Text(style.center).font(.system(size: 0.23 * worldScale, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.6)), at: CGPoint(x: 0, y: -0.5 * worldScale))
        text.draw(Text(value).font(.system(size: (style.center == "ACHIEVEMENT" ? 0.56 : 0.9) * worldScale, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.9)), at: CGPoint(x: 0, y: 0.12 * worldScale))
    }
}

/// ResolvedText still invokes SwiftUI's text drawing/layout on every frame.
/// Rasterize the static sensor labels once per stage size, keeping active labels separate.
@MainActor private final class SensorRenderCache {
    struct Item {
        var region: SensorPolygon
        var color: Color
        var path: Path
        var center: CGPoint
        var on: GraphicsContext.ResolvedImage
        var off: GraphicsContext.ResolvedImage
    }
    let items: [Item]
    private static var cache: [(Double, SensorRenderCache)] = []
    static func prepared(scale: Double, context: GraphicsContext) -> SensorRenderCache {
        if let hit = cache.first(where: { $0.0 == scale }) { return hit.1 }
        let value = SensorRenderCache(scale: scale, context: context)
        cache.append((scale, value)); if cache.count > 3 { cache.removeFirst() }; return value
    }
    init(scale: Double, context: GraphicsContext) {
        let colors: [String: Color] = ["A": .cyan, "B": .green, "C": .yellow, "D": .orange, "E": .purple]
        func label(_ name: String, color: Color, weight: Font.Weight) -> GraphicsContext.ResolvedImage {
            let renderer = ImageRenderer(content: Text(name).font(.system(size: 0.20 * scale, weight: weight, design: .monospaced)).foregroundStyle(color).fixedSize().padding(1))
            renderer.scale = 2
            if let image = renderer.cgImage { return context.resolve(Image(decorative: image, scale: 2)) }
            return context.resolve(Image(nsImage: NSImage(size: NSSize(width: 1, height: 1))))
        }
        items = SensorGeometry.polygons.map { region in
            let color = colors[String(region.name.prefix(1))] ?? .white
            let path = Path { p in
                guard let first = region.vertices.first else { return }
                p.move(to: CGPoint(x: first.x, y: first.y))
                for point in region.vertices.dropFirst() { p.addLine(to: CGPoint(x: point.x, y: point.y)) }
                p.closeSubpath()
            }
            return Item(region: region, color: color, path: path,
                center: CGPoint(x: region.center.x * scale, y: region.center.y * scale),
                on: label(region.name, color: .white, weight: .bold),
                off: label(region.name, color: color.opacity(0.8), weight: .medium))
        }
    }
}
