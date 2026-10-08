import Foundation
#if canImport(Metal)
import Metal
let device = MTLCreateSystemDefaultDevice()
let capability: [String: Any] = ["format": "mettle-metal-capability", "version": 1,
    "available": device != nil, "device": device?.name ?? "",
    "supportedSampleCounts": [1, 2, 4, 8, 16].filter { device?.supportsTextureSampleCount($0) == true },
    "note": device == nil ? "No Metal device. Native pixel comparisons have not run." : "Device detected. Availability alone is not a fidelity result."]
#else
let capability: [String: Any] = ["format": "mettle-metal-capability", "version": 1,
    "available": false, "device": "", "note": "Metal is unavailable on this platform. Native pixel comparisons have not run."]
#endif
let data = try JSONSerialization.data(withJSONObject: capability, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
exit(capability["available"] as? Bool == true ? 0 : 2)
