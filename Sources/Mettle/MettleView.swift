#if canImport(SwiftUI) && canImport(MetalKit)
import SwiftUI
import MetalKit
import QuartzCore

/// Native SwiftUI host. Pass a fixed `time` to seek/scrub, or nil for clock-driven playback.
/// Reduced Motion and inactive scene phases pause playback. Own accessibility/navigation in SwiftUI.
public struct MettleView {
    public let renderer: MetalRenderer
    public var time: Double?
    public var isPlaying: Bool
    public var onError: (Error) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    public init(renderer: MetalRenderer, time: Double? = nil, isPlaying: Bool = true,
                onError: @escaping (Error) -> Void = { error in NSLog("Mettle: %@",String(describing:error)) }) {
        self.renderer = renderer; self.time = time; self.isPlaying = isPlaying; self.onError = onError
    }
    public final class Coordinator: NSObject, MTKViewDelegate {
        var renderer: MetalRenderer
        var elapsed = 0.0
        var lastHostTime: Double?
        var controlledTime: Double?
        private var requestedTime: Double?
        var running = false
        var onError: (Error)->Void
        init(_ renderer:MetalRenderer,onError:@escaping(Error)->Void) { self.renderer = renderer; self.onError = onError }
        /// Keep the user's seek position separate from Reduced Motion's display
        /// override, and never carry a previous scene's seek into a new renderer.
        func updatePlayback(renderer nextRenderer: MetalRenderer, time: Double?, isPlaying: Bool,
                            reduceMotion: Bool, sceneIsActive: Bool) {
            if renderer !== nextRenderer {
                renderer = nextRenderer; elapsed = 0; lastHostTime = nil
            } else if let previous = requestedTime, time == nil {
                elapsed = previous.isFinite ? max(0, previous) : 0; lastHostTime = nil
            }
            requestedTime = time
            controlledTime = reduceMotion ? 0 : time
            running = isPlaying && time == nil && !reduceMotion && sceneIsActive
            if !running { lastHostTime = nil }
        }
        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // A controlled/paused view can be configured before it has a drawable.
            // Redraw after layout instead of leaving the first paused frame blank.
            if view.isPaused {
                DispatchQueue.main.async { [weak view] in view?.draw() }
            }
        }
        public func draw(in view: MTKView) {
            guard view.drawableSize.width > 0, view.drawableSize.height > 0, let drawable = view.currentDrawable else { return }
            let now = CACurrentMediaTime()
            if running { if let previous = lastHostTime { elapsed += max(0,now-previous) }; lastHostTime = now }
            else { lastHostTime = nil }
            do { try renderer.render(to:drawable.texture,time:controlledTime ?? elapsed,present:drawable) }
            catch { view.isPaused = true; onError(error) }
        }
    }
    public func makeCoordinator() -> Coordinator { Coordinator(renderer,onError:onError) }
    private func create(context: Context) -> MTKView {
        let view = MTKView(frame:.zero,device:renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0,0,0,0)
        view.framebufferOnly = false
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.delegate = context.coordinator
        #if os(macOS)
        view.wantsLayer = true; view.layer?.isOpaque = false
        #else
        view.isOpaque = false; view.backgroundColor = .clear
        #endif
        configure(view,context:context); return view
    }
    private func configure(_ view:MTKView,context:Context) {
        let c = context.coordinator
        if view.device?.registryID != renderer.device.registryID { view.device = renderer.device }
        c.updatePlayback(renderer: renderer, time: time, isPlaying: isPlaying,
                         reduceMotion: reduceMotion, sceneIsActive: scenePhase == .active)
        c.onError = onError
        view.isPaused = !c.running
        view.enableSetNeedsDisplay = !c.running
        if view.isPaused {
            #if os(macOS)
            view.needsDisplay = true
            #else
            view.setNeedsDisplay()
            #endif
            view.draw()
        }
    }
}
#if os(macOS)
extension MettleView: NSViewRepresentable {
    public func makeNSView(context: Context) -> MTKView { create(context:context) }
    public func updateNSView(_ nsView: MTKView, context: Context) { configure(nsView,context:context) }
}
#else
extension MettleView: UIViewRepresentable {
    public func makeUIView(context: Context) -> MTKView { create(context:context) }
    public func updateUIView(_ uiView: MTKView, context: Context) { configure(uiView,context:context) }
}
#endif
#endif
