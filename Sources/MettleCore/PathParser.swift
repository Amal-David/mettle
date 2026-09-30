import Foundation

/// Parses actual Figma/SVG path commands. No raster tracing, and no guessed geometry.
/// Figma emits M/L/Q/C/Z; H/V/S/T and relative forms are also accepted. Arcs are explicitly rejected.
public struct PathParser {
    public var tolerance: Double
    public var pointLimit: Int
    public init(tolerance: Double = 0.2, pointLimit: Int = 8192) { self.tolerance = max(0.001,tolerance); self.pointLimit = pointLimit }
    public func parse(_ source: String) throws -> [[Point]] {
        let regex = try NSRegularExpression(pattern: "[a-zA-Z]|[-+]?(?:[0-9]+\\.?[0-9]*|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?")
        let ns = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
        guard matches.count <= 200000 else { throw SceneError.invalid("Path token budget exceeded") }
        var tokens: [String] = []; var end = 0
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        for match in matches {
            let gap = ns.substring(with: NSRange(location:end,length:match.range.location-end))
            guard gap.unicodeScalars.allSatisfy({separators.contains($0)}) else { throw SceneError.invalid("Invalid path character") }
            tokens.append(ns.substring(with: match.range)); end = NSMaxRange(match.range)
        }
        guard ns.substring(from: end).unicodeScalars.allSatisfy({separators.contains($0)}) else { throw SceneError.invalid("Invalid trailing path data") }
        var i = 0, count = 0
        var command = "", previous = ""
        var p = Point(), start = Point(), control = Point()
        var contour: [Point] = [], contours: [[Point]] = []
        func isCommand(_ s: String) -> Bool { s.count == 1 && s.first!.isLetter }
        func number() throws -> Double {
            guard i < tokens.count, !isCommand(tokens[i]), let n = Double(tokens[i]), n.isFinite, abs(n) <= 1e9 else {
                throw SceneError.invalid("Missing or invalid path coordinate at token \(i)")
            }
            i += 1; return n
        }
        func point(relative: Bool) throws -> Point {
            let q = Point(try number(),try number()); return relative ? p+q : q
        }
        func append(_ q: Point) throws {
            count += 1
            guard count <= pointLimit else { throw SceneError.invalid("Flattened path exceeds \(pointLimit) points") }
            if contour.last != q { contour.append(q) }
        }
        func flush() {
            if contour.count > 1 { if contour.first == contour.last { contour.removeLast() }; contours.append(contour) }
            contour = []
        }
        func cubic(_ a: Point, _ b: Point, _ c: Point, _ d: Point, _ depth: Int = 0) throws {
            let chord = d-a
            let distance = max(abs((b-a).cross(chord)), abs((c-a).cross(chord))) / max(chord.length,1e-12)
            let polygon = (b-a).length + (c-b).length + (d-c).length
            if depth >= 16 || (distance <= tolerance && polygon-chord.length <= tolerance*2) {
                try append(d); return
            }
            let ab = (a+b)*0.5, bc = (b+c)*0.5, cd = (c+d)*0.5
            let abc = (ab+bc)*0.5, bcd = (bc+cd)*0.5, mid = (abc+bcd)*0.5
            try cubic(a,ab,abc,mid,depth+1); try cubic(mid,bcd,cd,d,depth+1)
        }
        while i < tokens.count {
            if isCommand(tokens[i]) { command = tokens[i]; i += 1 }
            guard !command.isEmpty else { throw SceneError.invalid("Path must begin with M") }
            let upper = command.uppercased(), relative = command != upper
            if contour.isEmpty && upper != "M" { throw SceneError.invalid("Subpath must begin with M") }
            switch upper {
            case "M":
                let q = try point(relative:relative); flush(); p = q; start = q; try append(q)
                command = relative ? "l" : "L"
            case "L": p = try point(relative:relative); try append(p)
            case "H": let x = try number(); p.x = relative ? p.x+x : x; try append(p)
            case "V": let y = try number(); p.y = relative ? p.y+y : y; try append(p)
            case "C":
                let b = try point(relative:relative), c = try point(relative:relative), d = try point(relative:relative)
                try cubic(p,b,c,d); p = d; control = c
            case "S":
                let b = ["C","S"].contains(previous) ? p*2-control : p
                let c = try point(relative:relative), d = try point(relative:relative)
                try cubic(p,b,c,d); p = d; control = c
            case "Q":
                let q = try point(relative:relative), d = try point(relative:relative)
                try cubic(p,p+(q-p)*(2.0/3),d+(q-d)*(2.0/3),d); p = d; control = q
            case "T":
                let q = ["Q","T"].contains(previous) ? p*2-control : p
                let d = try point(relative:relative)
                try cubic(p,p+(q-p)*(2.0/3),d+(q-d)*(2.0/3),d); p = d; control = q
            case "Z": p = start; flush(); command = ""
            case "A": throw SceneError.unsupported("SVG arc command A; export Figma fillGeometry cubic paths")
            default: throw SceneError.unsupported("Path command \(command)")
            }
            previous = upper
        }
        flush(); return contours
    }
}
