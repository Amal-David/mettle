import Foundation

/// Scan-band tessellation supports holes, concavity, and self-intersections.
/// Crossing y-values subdivide bands so edge order cannot swap inside a trapezoid.
/// Geometry is prepared once per scene, not every animation frame.
public struct Tessellator {
    public var maxEdges: Int
    public var maxVertices: Int
    public init(maxEdges: Int = 4096, maxVertices: Int = 1_000_000) {
        self.maxEdges = maxEdges; self.maxVertices = maxVertices
    }
    private struct Edge {
        let a: Point, b: Point
        var minY: Double { min(a.y,b.y) }
        var maxY: Double { max(a.y,b.y) }
        var direction: Int { b.y > a.y ? 1 : -1 }
        func x(_ y: Double) -> Double { a.x + (y-a.y)*(b.x-a.x)/(b.y-a.y) }
    }
    public func tessellate(_ contours: [[Point]], windingRule: String = "NONZERO") throws -> [Point] {
        guard ["NONZERO","EVENODD"].contains(windingRule) else { throw SceneError.invalid("Winding rule") }
        var edges: [Edge] = []
        var levels: [Double] = []
        for points in contours where points.count >= 3 {
            for i in points.indices {
                let a = points[i], b = points[(i+1)%points.count]
                guard a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite else { throw SceneError.invalid("Non-finite contour") }
                levels.append(a.y)
                if abs(a.y-b.y) > 1e-10 { edges.append(Edge(a:a,b:b)) }
            }
        }
        guard edges.count <= maxEdges else { throw SceneError.invalid("Path exceeds tessellation edge budget \(maxEdges)") }
        if edges.isEmpty { return [] }
        for i in edges.indices {
            for j in (i+1)..<edges.count {
                let e = edges[i], f = edges[j]
                if e.maxY <= f.minY || f.maxY <= e.minY { continue }
                let u = e.b-e.a, v = f.b-f.a, den = u.cross(v)
                if abs(den) < 1e-12 { continue }
                let t = (f.a-e.a).cross(v)/den, s = (f.a-e.a).cross(u)/den
                if t > 1e-10 && t < 1-1e-10 && s > 1e-10 && s < 1-1e-10 {
                    levels.append(e.a.y+t*u.y)
                }
            }
        }
        levels.sort()
        var ys: [Double] = []
        for y in levels { if ys.last.map({abs(y-$0)>1e-9}) ?? true { ys.append(y) } }
        if ys.count < 2 { return [] }
        var vertices: [Point] = []
        for k in 0..<(ys.count-1) {
            let y0 = ys[k], y1 = ys[k+1], ym = (y0+y1)/2
            let active = edges.filter {$0.minY < ym && $0.maxY > ym}.sorted {
                let a = $0.x(ym), b = $1.x(ym)
                return abs(a-b) < 1e-12 ? $0.direction < $1.direction : a < b
            }
            if active.count < 2 { continue }
            var winding = 0
            for n in 0..<(active.count-1) {
                winding += active[n].direction
                let inside = windingRule == "EVENODD" ? abs(winding)%2 == 1 : winding != 0
                if !inside || active[n+1].x(ym)-active[n].x(ym) <= 1e-10 { continue }
                let a = Point(active[n].x(y0),y0), b = Point(active[n+1].x(y0),y0)
                let c = Point(active[n+1].x(y1),y1), d = Point(active[n].x(y1),y1)
                if abs((b-a).cross(c-a)) > 1e-12 { vertices += [a,b,c] }
                if abs((c-a).cross(d-a)) > 1e-12 { vertices += [a,c,d] }
                guard vertices.count <= maxVertices else { throw SceneError.invalid("Tessellation vertex budget exceeded") }
            }
        }
        return vertices
    }
    public func tessellate(paths: [VectorPath], tolerance: Double = 0.2) throws -> [Point] {
        var output: [Point] = []
        for path in paths {
            let contours = try PathParser(tolerance: tolerance).parse(path.data)
            output += try tessellate(contours,windingRule:path.windingRule)
            guard output.count <= maxVertices else { throw SceneError.invalid("Combined vertex budget exceeded") }
        }
        return output
    }
}
