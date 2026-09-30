import Foundation

public struct Point: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double = 0, _ y: Double = 0) { self.x = x; self.y = y }
    public static func +(a: Point, b: Point) -> Point { Point(a.x + b.x, a.y + b.y) }
    public static func -(a: Point, b: Point) -> Point { Point(a.x - b.x, a.y - b.y) }
    public static func *(a: Point, b: Double) -> Point { Point(a.x * b, a.y * b) }
    public var length: Double { hypot(x, y) }
    public func cross(_ b: Point) -> Double { x * b.y - y * b.x }
}

/// Column-vector affine transform: [a c tx; b d ty; 0 0 1].
public struct Affine: Codable, Equatable, Sendable {
    public var a, b, c, d, tx, ty: Double
    public init(a: Double = 1, b: Double = 0, c: Double = 0, d: Double = 1,
                tx: Double = 0, ty: Double = 0) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    public static let identity = Affine()
    public static func translation(_ x: Double, _ y: Double) -> Affine { Affine(tx: x, ty: y) }
    public static func scale(_ x: Double, _ y: Double) -> Affine { Affine(a: x, d: y) }
    public static func rotation(_ radians: Double) -> Affine {
        Affine(a: cos(radians), b: sin(radians), c: -sin(radians), d: cos(radians))
    }
    public func apply(_ p: Point) -> Point { Point(a*p.x + c*p.y + tx, b*p.x + d*p.y + ty) }
    /// A * B applies B first, then A. Parent * child preserves Figma hierarchy.
    public static func *(l: Affine, r: Affine) -> Affine {
        Affine(a: l.a*r.a + l.c*r.b, b: l.b*r.a + l.d*r.b,
               c: l.a*r.c + l.c*r.d, d: l.b*r.c + l.d*r.d,
               tx: l.a*r.tx + l.c*r.ty + l.tx, ty: l.b*r.tx + l.d*r.ty + l.ty)
    }
    public func inverted() throws -> Affine {
        let det = a*d-b*c
        guard det.isFinite, abs(det) > 1e-12 else { throw SceneError.invalid("Singular transform") }
        return Affine(a: d/det, b: -b/det, c: -c/det, d: a/det,
                      tx: (c*ty-d*tx)/det, ty: (b*tx-a*ty)/det)
    }
    public var isFinite: Bool { [a,b,c,d,tx,ty].allSatisfy(\.isFinite) }
}

public struct RGBA: Codable, Equatable, Sendable {
    public var r, g, b, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public static let white = RGBA(1,1,1)
}

public enum SceneError: Error, CustomStringConvertible {
    case invalid(String)
    case unsupported(String)
    case gpu(String)
    public var description: String {
        switch self { case .invalid(let s): return "Invalid scene: \(s)"
        case .unsupported(let s): return "Unsupported feature: \(s)"
        case .gpu(let s): return "Metal: \(s)" }
    }
}
