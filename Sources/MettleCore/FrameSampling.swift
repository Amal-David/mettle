import Foundation

/// Deterministic sample times for native sequence exports and source comparisons.
/// Explicit timestamps preserve source precision, including the final endpoint.
public enum FrameSampling {
    public static func explicit(_ csv: String) throws -> [Double] {
        let fields = csv.split(separator: ",", omittingEmptySubsequences: false)
        guard (1...3600).contains(fields.count) else {
            throw SceneError.invalid("Provide 1...3600 explicit frame times")
        }
        var times: [Double] = []
        for field in fields {
            guard let value = Double(field.trimmingCharacters(in: .whitespacesAndNewlines)),
                  value.isFinite, (0...86400).contains(value),
                  times.last.map({ value > $0 }) ?? true else {
                throw SceneError.invalid("Frame times must be finite, nonnegative, strictly increasing seconds, at most 86400")
            }
            times.append(value)
        }
        return times
    }

    public static func regular(fps: Double, start: Double, duration: Double, count: Int? = nil) throws -> [Double] {
        guard fps.isFinite, (1...120).contains(fps), start.isFinite, (0...86400).contains(start),
              duration.isFinite, (0...86400).contains(duration) else {
            throw SceneError.invalid("FPS must be 1...120 and time/duration must be finite seconds in 0...86400")
        }
        let total = count ?? max(1, Int(ceil(max(0, duration - start) * fps)))
        guard (1...3600).contains(total), start + Double(total - 1) / fps <= 86400 else {
            throw SceneError.invalid("Sequence must contain 1...3600 frames within 86400 seconds")
        }
        return (0..<total).map { start + Double($0) / fps }
    }
}
