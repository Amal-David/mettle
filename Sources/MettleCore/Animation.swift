import Foundation

public struct Easing: Codable, Equatable, Sendable {
    public var kind: String
    public var control: [Double]
    public init(_ kind: String = "linear", control: [Double] = []) { self.kind = kind; self.control = control }
    public func sample(_ progress: Double) -> Double {
        let t = min(1,max(0,progress))
        if kind == "hold" { return t >= 1 ? 1 : 0 }
        guard kind == "cubic", control.count == 4 else { return t }
        if t == 0 || t == 1 { return t }
        func cubic(_ u: Double, _ p1: Double, _ p2: Double) -> Double {
            3*(1-u)*(1-u)*u*p1 + 3*(1-u)*u*u*p2 + u*u*u
        }
        // Solve x(u)=time, THEN evaluate y(u). Using y(time) directly is incorrect.
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let mid = (lo+hi)/2
            if cubic(mid,control[0],control[2]) < t { lo = mid } else { hi = mid }
        }
        return cubic((lo+hi)/2,control[1],control[3])
    }
    public func validate() throws {
        guard ["linear","hold","cubic"].contains(kind) else { throw SceneError.unsupported("Easing \(kind)") }
        if kind == "cubic" {
            guard control.count == 4, control.allSatisfy(\.isFinite),
                  (0...1).contains(control[0]), (0...1).contains(control[2]) else {
                throw SceneError.invalid("Cubic easing requires four finite values and x in 0...1")
            }
        }
    }
}
public struct Keyframe: Codable, Equatable, Sendable {
    public var time: Double
    public var value: [Double]
    /// Easing belongs to the segment LEAVING this keyframe.
    public var easing: Easing
    public init(_ time: Double, _ value: [Double], easing: Easing = Easing()) {
        self.time = time; self.value = value; self.easing = easing
    }
}
public struct Track: Codable, Equatable, Sendable {
    public var operation: String
    public var keyframes: [Keyframe]
    /// Placement of a style-local timeline in seconds. Nil means legacy global keys.
    public var timelineOffset: Double?
    public init(_ keyframes: [Keyframe], operation: String = "set", timelineOffset: Double? = nil) {
        self.keyframes = keyframes; self.operation = operation; self.timelineOffset = timelineOffset
    }
    public func sample(_ time: Double) -> [Double]? {
        let time = time - (timelineOffset ?? 0)
        guard time.isFinite else { return nil }
        guard let first = keyframes.first, let last = keyframes.last else { return nil }
        if time <= first.time { return first.value }
        if time >= last.time { return last.value }
        var lo = 0, hi = keyframes.count-1
        while hi-lo > 1 {
            let mid = (lo+hi)/2
            if keyframes[mid].time <= time { lo = mid } else { hi = mid }
        }
        let a = keyframes[lo], b = keyframes[hi]
        let t = a.easing.sample((time-a.time)/(b.time-a.time))
        return zip(a.value,b.value).map { $0 + ($1-$0)*t }
    }
}
public struct Binding: Codable, Equatable, Sendable {
    public var field: String
    public var base: [Double]
    public var tracks: [Track]
    public init(_ field: String, base: [Double], tracks: [Track]) { self.field = field; self.base = base; self.tracks = tracks }
    public func sample(_ time: Double) -> [Double] {
        var value = base
        for track in tracks {
            guard let sampled = track.sample(time), sampled.count == value.count else { continue }
            switch track.operation {
            case "offset": value = zip(value,sampled).map(+)
            case "scale": value = zip(value,sampled).map(*)
            default: value = sampled
            }
        }
        return value
    }
    public func validate() throws {
        let scalar = ["translationX","translationY","rotation","scaleX","scaleY","opacity"].contains(field)
        let color = field.hasPrefix("fills:") || field.hasPrefix("strokes:")
        guard scalar || color, base.count == (color ? 4 : 1), base.allSatisfy(\.isFinite), tracks.count <= 64 else {
            throw SceneError.unsupported("Binding field or dimensions: \(field)")
        }
        if color {
            guard let index = Int(field.split(separator: ":").last ?? ""), index >= 0 else {
                throw SceneError.invalid("Paint index in \(field)")
            }
        }
        if field == "scaleX" || field == "scaleY" {
            guard abs(base[0]) > 1e-12 else { throw SceneError.invalid("Cannot normalize scale from zero") }
        }
        for track in tracks {
            let offset = track.timelineOffset ?? 0
            guard offset.isFinite, offset >= 0, offset <= 86400 else {
                throw SceneError.invalid("Style timeline offset must be finite and in 0...86400")
            }
            guard ["set","offset","scale"].contains(track.operation), !track.keyframes.isEmpty,
                  track.keyframes.count <= 100000 else { throw SceneError.invalid("Track operation or keyframe count") }
            var previous = -Double.infinity
            for key in track.keyframes {
                guard key.time.isFinite, key.time >= 0, key.time + offset <= 86400, key.time > previous,
                      key.value.count == base.count, key.value.allSatisfy(\.isFinite) else {
                    throw SceneError.invalid("Unsorted, duplicate, or invalid keyframes for \(field)")
                }
                previous = key.time; try key.easing.validate()
            }
        }
    }
}
public struct NodeState: Sendable {
    public var transform: Affine
    public var opacity: Double
    public var colors: [String: RGBA]
}
public extension Node {
    func evaluate(at time: Double) -> NodeState {
        var matrix = transform
        var alpha = opacity
        var rotation = 0.0, scaleX = 1.0, scaleY = 1.0
        var colors: [String:RGBA] = [:]
        for binding in bindings {
            let v = binding.sample(time)
            switch binding.field {
            case "translationX": matrix.tx += v[0]-binding.base[0]
            case "translationY": matrix.ty += v[0]-binding.base[0]
            case "rotation": rotation = -(v[0]-binding.base[0]) * .pi/180 // Figma positive = counter-clockwise.
            case "scaleX": scaleX = v[0]/binding.base[0]
            case "scaleY": scaleY = v[0]/binding.base[0]
            case "opacity": alpha = min(1,max(0,v[0]))
            default:
                if v.count == 4 { colors[binding.field] = RGBA(min(1,max(0,v[0])),min(1,max(0,v[1])),min(1,max(0,v[2])),min(1,max(0,v[3]))) }
            }
        }
        let aroundOrigin = Affine.translation(origin.x,origin.y) * .rotation(rotation) * .scale(scaleX,scaleY) * .translation(-origin.x,-origin.y)
        return NodeState(transform: matrix * aroundOrigin, opacity: alpha, colors: colors)
    }
}
