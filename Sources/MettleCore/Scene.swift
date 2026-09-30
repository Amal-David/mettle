import Foundation

public struct Diagnostic: Codable, Sendable {
    public var severity: String
    public var code: String
    public var nodeID: String
    public var message: String
}
public struct VectorPath: Codable, Equatable, Sendable {
    public var data: String
    public var windingRule: String
    public init(_ data: String, windingRule: String = "NONZERO") {
        self.data = data; self.windingRule = windingRule
    }
}
public struct GradientStop: Codable, Equatable, Sendable {
    public var position: Double
    public var color: RGBA
    public init(_ position: Double, _ color: RGBA) { self.position = position; self.color = color }
}
public struct Paint: Codable, Equatable, Sendable {
    public var kind: String
    public var color: RGBA
    public var opacity: Double
    public var transform: Affine
    public var stops: [GradientStop]
    public init(color: RGBA = .white, kind: String = "solid", opacity: Double = 1,
                transform: Affine = .identity, stops: [GradientStop] = []) {
        self.kind = kind; self.color = color; self.opacity = opacity
        self.transform = transform; self.stops = stops
    }
}
public struct Draw: Codable, Equatable, Sendable {
    public var paths: [VectorPath]
    public var paint: Paint
    public var transform: Affine
    public var size: Point
    /// Original paint index, NOT draw order. Used for source-bound color animation.
    public var paintIndex: Int
    public var role: String
    public init(paths: [VectorPath], paint: Paint, size: Point,
                transform: Affine = .identity, paintIndex: Int = 0, role: String = "fills") {
        self.paths = paths; self.paint = paint; self.size = size; self.transform = transform
        self.paintIndex = paintIndex; self.role = role
    }
}
public struct Node: Codable, Sendable {
    public var id: String
    public var name: String
    public var transform: Affine
    public var size: Point
    public var opacity: Double
    public var origin: Point
    public var draws: [Draw]
    public var clip: [VectorPath]
    public var bindings: [Binding]
    public var children: [Node]
    public init(id: String, name: String = "", transform: Affine = .identity,
                size: Point = Point(100,100), opacity: Double = 1, origin: Point = Point(),
                draws: [Draw] = [], clip: [VectorPath] = [], bindings: [Binding] = [], children: [Node] = []) {
        self.id = id; self.name = name; self.transform = transform; self.size = size; self.opacity = opacity
        self.origin = origin; self.draws = draws; self.clip = clip; self.bindings = bindings; self.children = children
    }
}
public struct Scene: Codable, Sendable {
    public var name: String
    public var width: Double
    public var height: Double
    public var duration: Double
    public var loop: String
    public var root: Node
    public init(name: String = "Scene", width: Double, height: Double, duration: Double = 0,
                loop: String = "once", root: Node) {
        self.name = name; self.width = width; self.height = height
        self.duration = duration; self.loop = loop; self.root = root
    }
    public func localTime(_ time: Double) -> Double {
        guard duration > 0, time.isFinite else { return 0 }
        let t = max(0,time)
        if loop == "loop" { return t.truncatingRemainder(dividingBy: duration) }
        if loop == "pingPong" {
            let p = t.truncatingRemainder(dividingBy: duration * 2)
            return p <= duration ? p : duration*2-p
        }
        return min(t,duration)
    }
}
public struct SceneDocument: Codable, Sendable {
    public var format: String
    public var version: Int
    public var scenes: [Scene]
    public var diagnostics: [Diagnostic]
    public init(scenes: [Scene], diagnostics: [Diagnostic] = []) {
        self.format = "figma-metal"; self.version = 2; self.scenes = scenes; self.diagnostics = diagnostics
    }
    public static func load(url: URL, allowPartial: Bool = false) throws -> SceneDocument {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= 32*1024*1024 else { throw SceneError.invalid("File exceeds 32 MiB") }
        return try decode(Data(contentsOf: url), allowPartial: allowPartial)
    }
    public static func decode(_ data: Data, allowPartial: Bool = false) throws -> SceneDocument {
        guard data.count <= 32*1024*1024 else { throw SceneError.invalid("File exceeds 32 MiB") }
        if data.starts(with: [0x50, 0x4b, 0x03, 0x04]) {
            throw SceneError.unsupported("Compressed archives, including dotLottie, are not Mettle scenes. Use the Mettle Figma exporter and open its .figmetal.json file.")
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["format"] == nil, object["layers"] is [Any], object["fr"] != nil {
            throw SceneError.unsupported("This is a Lottie export, not a Mettle scene. Use Mettle — Experimental Metal Export in Figma. Lottie is not used as an intermediate format.")
        }
        let document = try JSONDecoder().decode(Self.self, from: data)
        try document.validate(allowPartial: allowPartial)
        return document
    }
    public func validate(allowPartial: Bool = false) throws {
        guard format == "figma-metal", [1, 2].contains(version) else { throw SceneError.unsupported("Document format/version") }
        guard !scenes.isEmpty, scenes.count <= 64 else { throw SceneError.invalid("Expected 1...64 scenes") }
        if !allowPartial, let issue = diagnostics.first(where: {$0.severity == "error"}) {
            throw SceneError.unsupported("\(issue.code) at \(issue.nodeID): \(issue.message)")
        }
        for scene in scenes {
            guard scene.width.isFinite, scene.height.isFinite, scene.width > 0, scene.height > 0,
                  scene.width <= 16384, scene.height <= 16384,
                  scene.duration.isFinite, scene.duration >= 0, scene.duration <= 86400,
                  ["once", "loop", "pingPong"].contains(scene.loop) else {
                throw SceneError.invalid("Dimensions, duration, or loop mode")
            }
            var ids = Set<String>(); var count = 0
            try validateNode(scene.root, depth: 0, ids: &ids, count: &count)
        }
    }
    private func validateNode(_ node: Node, depth: Int, ids: inout Set<String>, count: inout Int) throws {
        count += 1
        guard depth <= 64, count <= 10000, ids.insert(node.id).inserted else {
            throw SceneError.invalid("Duplicate ID, excessive depth, or node count at \(node.id)")
        }
        guard node.transform.isFinite, node.size.x.isFinite, node.size.y.isFinite,
              node.size.x >= 0, node.size.y >= 0, node.opacity.isFinite,
              (0...1).contains(node.opacity), node.origin.x.isFinite, node.origin.y.isFinite else {
            throw SceneError.invalid("Node properties at \(node.id)")
        }
        for path in node.clip { try validatePath(path) }
        for draw in node.draws {
            guard draw.transform.isFinite, draw.size.x.isFinite, draw.size.y.isFinite,
                  draw.size.x >= 0, draw.size.y >= 0,
                  ["solid","linear","radial"].contains(draw.paint.kind),
                  draw.paint.transform.isFinite, draw.paint.opacity.isFinite,
                  (0...1).contains(draw.paint.opacity), draw.paint.stops.count <= 64 else {
                throw SceneError.invalid("Draw/paint at \(node.id)")
            }
            try validateColor(draw.paint.color)
            if draw.paint.kind != "solid", draw.paint.stops.count < 2 { throw SceneError.invalid("Gradient needs at least 2 stops") }
            var previous = -Double.infinity
            for stop in draw.paint.stops {
                guard stop.position.isFinite, (0...1).contains(stop.position), stop.position >= previous else {
                    throw SceneError.invalid("Gradient stop order")
                }
                previous = stop.position; try validateColor(stop.color)
            }
            for path in draw.paths { try validatePath(path) }
        }
        for binding in node.bindings {
            if version == 1, binding.tracks.contains(where: { ($0.timelineOffset ?? 0) != 0 }) {
                throw SceneError.invalid("Style-local timing requires scene format version 2")
            }
            try binding.validate()
        }
        for child in node.children { try validateNode(child, depth: depth+1, ids: &ids, count: &count) }
    }
    private func validateColor(_ color: RGBA) throws {
        guard [color.r,color.g,color.b,color.a].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw SceneError.invalid("RGBA outside 0...1")
        }
    }
    private func validatePath(_ path: VectorPath) throws {
        guard ["NONZERO","EVENODD"].contains(path.windingRule), path.data.utf8.count <= 2_000_000 else {
            throw SceneError.invalid("Path winding or length")
        }
    }
}
