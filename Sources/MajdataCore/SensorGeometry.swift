import Foundation

public struct SensorPolygon: Codable, Sendable {
    public var id: Int
    public var name: String
    public var vertices: [Point]
    public var center: Point { Point(vertices.map(\.x).reduce(0, +) / Double(vertices.count), vertices.map(\.y).reduce(0, +) / Double(vertices.count)) }
    public func contains(_ point: Point, contactRadius: Double = 0) -> Bool {
        var inside = false
        for i in vertices.indices {
            let a = vertices[i], b = vertices[(i + 1) % vertices.count]
            let dx = b.x - a.x, dy = b.y - a.y
            let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / max(1e-12, dx * dx + dy * dy)))
            if point.distance(to: a.interpolated(to: b, at: t)) <= max(1e-9, contactRadius) { return true }
            if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
        }
        return inside
    }
}

public struct SensorRegion: Codable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var x: Double
    public var y: Double
    public var radius: Double
    public var center: Point { Point(x, y) }
    public var group: String { String(name.prefix(1)) }
    public func contains(_ point: Point, contactRadius: Double = 0) -> Bool {
        // Exact overlap formula used by upstream InputManager and SlideDrop.
        let dx = point.x - x, dy = point.y - y
        return dx * dx + dy * dy <= radius * radius + contactRadius * contactRadius
    }
}

public enum SensorGeometry {
    public static let starRadius = 0.763736616
    public static let polygons: [SensorPolygon] = {
        guard let url = Bundle.module.url(forResource: "sensor-polygons", withExtension: "json"),
              let data = try? Data(contentsOf: url), let result = try? JSONDecoder().decode([SensorPolygon].self, from: data) else { return [] }
        return result
    }()
    public static let regions: [SensorRegion] = {
        guard let url = Bundle.module.url(forResource: "sensors", withExtension: "json"),
              let data = try? Data(contentsOf: url), let result = try? JSONDecoder().decode([SensorRegion].self, from: data) else { return [] }
        return result
    }()
    private static let bounds: [(Double, Double, Double, Double)] = polygons.map { p in
        (p.vertices.map(\.x).min() ?? 0, p.vertices.map(\.x).max() ?? 0,
         p.vertices.map(\.y).min() ?? 0, p.vertices.map(\.y).max() ?? 0)
    }
    public static func contacts(at point: Point, slide: Bool = false, radius: Double = 0.4) -> Set<Int> {
        var result: Set<Int> = []
        for i in polygons.indices {
            let b = bounds[i]
            if point.x >= b.0 - radius && point.x <= b.1 + radius && point.y >= b.2 - radius && point.y <= b.3 + radius,
               polygons[i].contains(point, contactRadius: radius) { result.insert(polygons[i].id) }
        }
        return result
    }
    /// Shows ideal automatic contacts, without claiming to simulate full DJ Auto scoring.
    public static func active(notes: [Note], at time: Double) -> Set<Int> {
        var active: Set<Int> = []
        for note in notes {
            if note.kind == .slide {
                for segment in note.segments where time >= segment.startTime && time < segment.startTime + segment.duration {
                    let progress = (time - segment.startTime) / max(0.001, segment.duration)
                    for branch in segment.shape == "w" ? [-1, 0, 1] : [0] {
                        let position = SlideGeometry.position(on: SlideGeometry.points(for: segment, branch: branch), progress: progress)
                        active.formUnion(contacts(at: Point(position.x * 4.8, position.y * 4.8), slide: true))
                    }
                }
            } else {
                let sustained = note.kind == .hold || note.kind == .touchHold
                guard time >= note.time && time < (sustained ? max(note.time + 0.08, note.endTime) : note.time + 0.08) else { continue }
                let name = note.area == "C" ? "C" : (note.kind == .tap || note.kind == .hold ? "A" : note.area) + String(note.lane)
                if let sensor = regions.first(where: { $0.name == name }) { active.insert(sensor.id) }
            }
        }
        return active
    }
}
