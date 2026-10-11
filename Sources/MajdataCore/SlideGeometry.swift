import Foundation

public struct Point: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public func distance(to p: Point) -> Double { hypot(x - p.x, y - p.y) }
    public func interpolated(to p: Point, at t: Double) -> Point { Point(x + (p.x - x) * t, y + (p.y - y) * t) }
}
public enum SlideGeometry {
    static let paths: [String: [[Double]]] = {
        guard let url = Bundle.majdataCore.url(forResource: "slide-paths", withExtension: "json"),
              let data = try? Data(contentsOf: url), let paths = try? JSONDecoder().decode([String: [[Double]]].self, from: data) else { return [:] }
        return paths
    }()
    public static func lane(_ n: Int, radius: Double = 1) -> Point {
        let a = (Double(n) * 45 - 112.5) * .pi / 180
        return Point(cos(a) * radius, sin(a) * radius)
    }
    public static func touch(_ area: String, lane n: Int) -> Point {
        if area == "C" { return Point(0, 0) }
        let r: Double = area == "B" ? 2.3 / 4.8 : (area == "E" ? 3.0 / 4.8 : 4.1 / 4.8)
        let p = lane(n, radius: r)
        if area == "D" || area == "E" { return rotated(p, angle: -.pi / 8) }
        return p
    }
    public static func rotated(_ p: Point, angle: Double) -> Point {
        Point(p.x * cos(angle) - p.y * sin(angle), p.x * sin(angle) + p.y * cos(angle))
    }
    public static func key(for s: SlideSegment) -> (name: String, mirror: Bool)? {
        let relative = (s.end - s.start + 8) % 8 + 1
        let mirrored = (9 - relative) % 8 + 1
        let upper = [1, 2, 7, 8].contains(s.start)
        switch s.shape {
        case "-": return (3...7).contains(relative) ? ("line\(relative)", false) : nil
        case "^": return relative != 1 && relative != 5 ? ("circle\(relative < 5 ? relative : mirrored)", relative > 5) : nil
        case ">", "<":
            let clockwise = s.shape == ">" ? upper : !upper
            return ("circle\(clockwise ? relative : mirrored)", !clockwise)
        case "v": return relative != 5 ? ("v\(relative)", false) : nil
        case "p", "pp": return ("\(s.shape == "p" ? "pq" : "ppqq")\(relative)", false)
        case "q", "qq": return ("\(s.shape == "q" ? "pq" : "ppqq")\(mirrored)", true)
        case "s", "z": return relative == 5 ? ("s", s.shape == "z") : nil
        case "w": return relative == 5 ? ("wifi", false) : nil
        case "V":
            guard let turn = s.turn else { return nil }
            let r = (turn - s.start + 8) % 8 + 1
            if r == 7 && (2...5).contains(relative) { return ("L\(relative)", false) }
            if r == 3 && relative >= 5 { return ("L\(mirrored)", true) }
            return nil
        default: return nil
        }
    }
    public static func barCount(for s: SlideSegment) -> Int {
        guard let key = key(for: s) else { return 0 }
        return key.name == "wifi" ? 11 : max(0, (paths[key.name]?.count ?? 1) - 1)
    }
    public static func points(for s: SlideSegment, branch: Int = 0) -> [Point] {
        guard let key = key(for: s) else { return [] }
        if key.name == "wifi" {
            let end = (s.end - 1 + branch + 8) % 8 + 1
            let a = lane(s.start), b = lane(end)
            return (0...32).map { a.interpolated(to: b, at: Double($0) / 32) }
        }
        // Last child in Unity is the judgement text, not a path bar.
        let raw = (paths[key.name] ?? []).dropLast()
        let angle = Double(s.start - (key.mirror ? 0 : 1)) * .pi / 4
        let transformed = raw.map { p -> Point in
            rotated(Point(key.mirror ? -p[0] : p[0], p[1]), angle: angle)
        }
        return [lane(s.start)] + transformed + [lane(s.end)]
    }
    public static func position(on points: [Point], progress: Double) -> Point {
        guard let first = points.first else { return Point(0, 0) }
        if points.count == 1 { return first }
        let p = min(1, max(0, progress)) * Double(points.count - 1)
        let i = min(points.count - 2, Int(p))
        return points[i].interpolated(to: points[i + 1], at: p - Double(i))
    }
}
