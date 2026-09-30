#if os(macOS) && canImport(MetalKit)
import XCTest
import MetalKit
@testable import Mettle

private final class RedrawProbeView: MTKView {
    var onDraw: (() -> Void)?
    override func draw() { onDraw?() }
}

final class HostTests: XCTestCase {
    func testPausedPreviewRedrawsAfterInitialDrawableResize() throws {
        let renderer = try MetalRenderer(scene: Scene(width: 32, height: 32, root: Node(id: "root")))
        let coordinator = MettleView.Coordinator(renderer, onError: { XCTFail("\($0)") })
        let view = RedrawProbeView(frame: .zero, device: renderer.device)
        view.isPaused = true
        let redraw = expectation(description: "First controlled frame is drawn after layout")
        view.onDraw = { redraw.fulfill() }
        coordinator.mtkView(view, drawableSizeWillChange: CGSize(width: 32, height: 32))
        wait(for: [redraw], timeout: 2)
    }
}
#endif
