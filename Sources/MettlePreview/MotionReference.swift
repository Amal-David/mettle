#if os(macOS)
import AppKit
import Foundation

/// Inspiration is a separate collection, never passed to the Metal renderer.
/// Thumbnail attribution and licensing: Resources/References/ATTRIBUTION.md.
public struct MotionReference: Identifiable {
    public let id: String
    public let title: String
    public let creator: String
    public let category: String
    public let lesson: String
    public let limitation: String
    public let source: URL
    public var thumbnail: NSImage? {
        guard let url = Bundle.module.url(forResource: id, withExtension: "png", subdirectory: "References") else { return nil }
        return NSImage(contentsOf: url)
    }
    public func openOriginal() { NSWorkspace.shared.open(source) }
    public static let curated: [MotionReference] = [
        .init(id: "fintech", title: "Fintech feature cards", creator: "Hubert4", category: "PRODUCT STORYTELLING",
              lesson: "Small, purposeful movements explain a product without a wall of text.",
              limitation: "Reference only. Interactive states and complete card flows are not imported by Mettle.",
              source: URL(string: "https://rive.app/marketplace/27520-52011-fintech-feature-cards/")!),
        .init(id: "infisical", title: "Animated feature cards", creator: "_davecsko", category: "DIAGRAMS IN MOTION",
              lesson: "Quiet pacing makes a complex system feel understandable.",
              limitation: "Reference only. Path effects, connections and state logic are not a verified Mettle export.",
              source: URL(string: "https://rive.app/marketplace/23017-43043-animated-feature-cards/")!),
        .init(id: "peekaboo", title: "Peekaboo Avatar", creator: "jacquelinea", category: "A LITTLE PERSONALITY",
              lesson: "One expressive gesture is more memorable than a screen full of effects.",
              limitation: "Reference only. Hover behavior and the original character have not been ported to Metal.",
              source: URL(string: "https://rive.app/marketplace/21505-40452-peekaboo-avatar-animation/")!),
        .init(id: "switch", title: "Light / Dark Mode Switch", creator: "daviddoesburg", category: "MEANINGFUL TRANSITIONS",
              lesson: "The motion tells you what changed, not just that something moved.",
              limitation: "Reference only. This switch is not an interactive Mettle control.",
              source: URL(string: "https://rive.app/marketplace/23613-44152-light-dark-mode-switch/")!)
    ]
}
#endif
