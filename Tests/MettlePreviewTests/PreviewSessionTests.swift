#if os(macOS)
import XCTest
import Mettle
@testable import MettlePreview

final class PreviewSessionTests: XCTestCase {
    func fixture(_ scenes: [Scene]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".figmetal.json")
        try JSONEncoder().encode(SceneDocument(scenes: scenes)).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func scene(_ name: String = "First", duration: Double = 2, loop: String = "loop") -> Scene {
        var node = Node(id: "shape", size: Point(16,16), draws: [Draw(paths: [VectorPath("M0 0 H16 V16 H0 Z")], paint: Paint(color: RGBA(1,0,0)), size: Point(16,16))])
        node.bindings = [Binding("translationX", base: [0], tracks: [Track([Keyframe(0,[0]), Keyframe(duration,[16])])])]
        return Scene(name: name, width: 48, height: 32, duration: duration, loop: loop, root: node)
    }
    func testWelcomeDoesNotAutoLoadTestArtwork() {
        let s = PreviewSession(examples: []); XCTAssertNil(s.renderer); XCTAssertNil(s.document)
    }
    func testOpenPreparesPausedDocumentAndPreservesEndpoint() throws {
        let s = PreviewSession(examples: []); try s.loadSynchronously(url: fixture([scene()]), initialTime: 2)
        XCTAssertFalse(s.playback.isPlaying); XCTAssertEqual(s.playback.position, 2)
        XCTAssertEqual(s.renderer?.scene.loop, "once"); XCTAssertTrue(s.repeatEnabled)
        let bytes = try XCTUnwrap(s.renderer).pixels(width: 48, height: 32, time: 2)
        XCTAssertEqual(Array(bytes)[(8*48+24)*4+2], 255)
        XCTAssertEqual(Array(bytes)[(8*48+8)*4+3], 0)
    }
    func testBadFileLeavesExistingDocumentIntact() throws {
        let s = PreviewSession(examples: []); try s.loadSynchronously(url: fixture([scene()]))
        let previous = s.renderer
        XCTAssertThrowsError(try s.loadSynchronously(url: URL(fileURLWithPath: "/missing/invalid.json")))
        XCTAssertTrue(previous === s.renderer); XCTAssertEqual(s.scene?.name, "First")
    }
    func testMultiSceneSelectionAndBounds() throws {
        let s = PreviewSession(examples: []); let url = try fixture([scene(), scene("Second")])
        try s.loadSynchronously(url: url, sceneIndex: 1); XCTAssertEqual(s.scene?.name, "Second")
        XCTAssertThrowsError(try s.loadSynchronously(url: url, sceneIndex: 2)); XCTAssertEqual(s.selectedScene, 1)
    }
    func testStaticSceneHasNoPlayableTimeline() throws {
        let s = PreviewSession(examples: [])
        try s.loadSynchronously(url: fixture([Scene(width: 48, height: 32, root: Node(id: "static"))]))
        XCTAssertFalse(s.hasMotion); s.togglePlayback(); XCTAssertFalse(s.playback.isPlaying)
    }
    func testCloseReturnsToWelcome() throws {
        let s = PreviewSession(examples: []); try s.loadSynchronously(url: fixture([scene()]))
        s.close(); XCTAssertNil(s.document); XCTAssertNil(s.renderer); XCTAssertEqual(s.duration, 0)
    }
    func testExportWritesActualPNG() throws {
        let s = PreviewSession(examples: []); try s.loadSynchronously(url: fixture([scene()]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try PreviewSession.exportFrame(renderer: XCTUnwrap(s.renderer), time: 1, url: url)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(8)), [137,80,78,71,13,10,26,10])
    }
    func testReducedMotionPreventsAutoplay() throws {
        let s = PreviewSession(examples: []); try s.loadSynchronously(url: fixture([scene()]))
        s.reduceMotion = true; s.togglePlayback(); XCTAssertFalse(s.playback.isPlaying)
    }
}
#endif
