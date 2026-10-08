#if os(macOS) && canImport(MetalKit)
import XCTest
import MetalKit
@testable import Mettle

private final class RedrawProbeView: MTKView {
    var onDraw: (() -> Void)?
    override func draw() { onDraw?() }
}

final class HostTests: XCTestCase {
    private func renderer() throws -> MetalRenderer {
        try MetalRenderer(scene: Scene(width: 32, height: 32, duration: 10, root: Node(id: "root")))
    }
    func testSwitchingScenesDoesNotResumeThePreviousScenesSeekPosition() throws {
        let first = try renderer(), second = try renderer()
        let coordinator = MettleView.Coordinator(first, onError: { XCTFail("\($0)") })
        coordinator.updatePlayback(renderer: first, time: 8, isPlaying: false, reduceMotion: false, sceneIsActive: true)
        coordinator.updatePlayback(renderer: second, time: nil, isPlaying: true, reduceMotion: false, sceneIsActive: true)
        XCTAssertTrue(coordinator.renderer === second)
        XCTAssertEqual(coordinator.elapsed, 0)
        XCTAssertNil(coordinator.controlledTime)
        XCTAssertNil(coordinator.lastHostTime)
        XCTAssertTrue(coordinator.running)
    }
    func testResumingTheSameSceneStartsFromItsControlledPosition() throws {
        let renderer = try self.renderer()
        let coordinator = MettleView.Coordinator(renderer, onError: { XCTFail("\($0)") })
        coordinator.updatePlayback(renderer: renderer, time: 3.25, isPlaying: false, reduceMotion: false, sceneIsActive: true)
        coordinator.updatePlayback(renderer: renderer, time: nil, isPlaying: true, reduceMotion: false, sceneIsActive: true)
        XCTAssertEqual(coordinator.elapsed, 3.25)
        XCTAssertTrue(coordinator.running)
        XCTAssertNil(coordinator.lastHostTime)
    }
    func testReducedMotionDoesNotEraseThePlaybackPositionOnResume() throws {
        let renderer = try self.renderer()
        let coordinator = MettleView.Coordinator(renderer, onError: { XCTFail("\($0)") })
        coordinator.updatePlayback(renderer: renderer, time: nil, isPlaying: true, reduceMotion: false, sceneIsActive: true)
        coordinator.elapsed = 3.25; coordinator.lastHostTime = 100
        coordinator.updatePlayback(renderer: renderer, time: nil, isPlaying: true, reduceMotion: true, sceneIsActive: true)
        XCTAssertFalse(coordinator.running)
        XCTAssertEqual(coordinator.controlledTime, 0)
        XCTAssertNil(coordinator.lastHostTime)
        coordinator.updatePlayback(renderer: renderer, time: nil, isPlaying: true, reduceMotion: false, sceneIsActive: true)
        XCTAssertEqual(coordinator.elapsed, 3.25)
        XCTAssertNil(coordinator.controlledTime)
        XCTAssertTrue(coordinator.running)
    }
    func testInactiveSceneDoesNotAccumulateAClockGap() throws {
        let renderer = try self.renderer()
        let coordinator = MettleView.Coordinator(renderer, onError: { XCTFail("\($0)") })
        coordinator.elapsed = 2; coordinator.lastHostTime = 100
        coordinator.updatePlayback(renderer: renderer, time: nil, isPlaying: true, reduceMotion: false, sceneIsActive: false)
        XCTAssertFalse(coordinator.running); XCTAssertNil(coordinator.lastHostTime)
        coordinator.updatePlayback(renderer: renderer, time: nil, isPlaying: true, reduceMotion: false, sceneIsActive: true)
        XCTAssertEqual(coordinator.elapsed, 2); XCTAssertNil(coordinator.lastHostTime)
    }
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
