#if os(macOS)
import XCTest
import Mettle
import Combine
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
    func waitForLoad(_ session: PreviewSession, when ready: @escaping () -> Bool = { true },
                     action: () -> Void) {
        let finished = expectation(description: "Preview renderer prepared")
        let observer = session.$isLoading.dropFirst().sink { loading in
            if !loading && ready() { finished.fulfill() }
        }
        action()
        wait(for: [finished], timeout: 30)
        withExtendedLifetime(observer) {}
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
    func testQualityDefaultsToStandardAndApplicationCanSelectHighBeforeOpening() {
        XCTAssertEqual(PreviewSession(examples: []).rasterScale, 1)
        XCTAssertEqual(PreviewApplication(examples: []).session.rasterScale, 1)
        let app = PreviewApplication(examples: [], initialRasterScale: 2)
        XCTAssertEqual(app.session.rasterScale, 2); XCTAssertNil(app.session.renderer)
        app.session.setRasterScale(3)
        XCTAssertEqual(app.session.rasterScale, 2); XCTAssertNotNil(app.session.issue)
    }
    func testChangingQualityKeepsLoadedSceneTransportAndExportDimensions() throws {
        let s = PreviewSession(examples: [])
        let url = try fixture([scene(), scene("Second", loop: "pingPong")])
        try s.loadSynchronously(url: url, sceneIndex: 1, exampleID: "test", initialTime: 1.25)
        s.toggleRepeat(); s.setSpeed(2); s.zoom = "100%"
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let sourceDocument = try encoder.encode(XCTUnwrap(s.document))
        let previous = s.renderer
        // A quality switch must use the loaded document, not silently reload a
        // source file that the user has since edited or replaced.
        try Data("changed source file".utf8).write(to: url)
        waitForLoad(s) { s.setRasterScale(2) }
        let renderer = try XCTUnwrap(s.renderer)
        XCTAssertFalse(previous === renderer); XCTAssertEqual(renderer.rasterScale, 2)
        XCTAssertEqual(s.rasterScale, 2); XCTAssertEqual(renderer.scene.loop, "once")
        XCTAssertEqual(s.selectedScene, 1); XCTAssertEqual(s.scene?.name, "Second")
        XCTAssertEqual(s.sourceURL, url); XCTAssertEqual(s.exampleID, "test")
        XCTAssertEqual(try encoder.encode(XCTUnwrap(s.document)), sourceDocument)
        XCTAssertEqual(s.playback.position, 1.25); XCTAssertEqual(s.playback.repetition, .once)
        XCTAssertEqual(s.playback.speed, 2); XCTAssertFalse(s.playback.isPlaying)
        XCTAssertEqual(s.zoom, "100%")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: output) }
        try PreviewSession.exportFrame(renderer: renderer, time: s.playback.position, url: output)
        let bytes = Array(try Data(contentsOf: output))
        XCTAssertEqual(Array(bytes.prefix(8)), [137,80,78,71,13,10,26,10])
        func dimension(_ offset: Int) -> Int { (0..<4).reduce(0) { $0*256 + Int(bytes[offset+$1]) } }
        XCTAssertEqual(dimension(16), 48); XCTAssertEqual(dimension(20), 32)
        waitForLoad(s) { s.setRasterScale(1) }
        XCTAssertEqual(s.renderer?.rasterScale, 1); XCTAssertEqual(s.playback.position, 1.25)
        XCTAssertEqual(s.playback.repetition, .once); XCTAssertEqual(s.selectedScene, 1)
        s.toggleRepeat(); XCTAssertEqual(s.playback.repetition, .pingPong)
    }
    func testQualityAndSceneControlsCannotReplaceAnInFlightLoad() throws {
        let s = PreviewSession(examples: [])
        let url = try fixture([scene(), scene("Second")])
        try s.loadSynchronously(url: url, sceneIndex: 1)
        waitForLoad(s) {
            s.setRasterScale(2)
            XCTAssertTrue(s.isLoading)
            s.setRasterScale(1); s.chooseScene(0)
        }
        XCTAssertEqual(s.rasterScale, 2); XCTAssertEqual(s.selectedScene, 1)
        XCTAssertEqual(s.scene?.name, "Second")
    }
    func testNewOpenSupersedesPendingQualityBuild() throws {
        let s = PreviewSession(examples: [])
        try s.loadSynchronously(url: fixture([scene()]), initialTime: 1.25)
        let next = try fixture([scene("Latest", duration: 4, loop: "pingPong")])
        waitForLoad(s, when: { s.sourceURL == next }) {
            s.setRasterScale(2)
            s.open(next, initialTime: 3)
        }
        XCTAssertEqual(s.scene?.name, "Latest"); XCTAssertEqual(s.playback.position, 3)
        XCTAssertEqual(s.playback.repetition, .pingPong)
        XCTAssertEqual(s.rasterScale, 1); XCTAssertEqual(s.renderer?.rasterScale, 1)
    }
    func testHighQualityLimitFailureIsActionableAndNeverFallsBackOrRepeatsPublications() throws {
        let s = PreviewSession(examples: []); s.setRasterScale(2)
        try s.loadSynchronously(url: fixture([Scene(width: 5000, height: 1, root: Node(id: "wide"))]))
        let renderer = try XCTUnwrap(s.renderer)
        var limitError: Error?
        do { _ = try renderer.makeTarget(width: 5000, height: 1); XCTFail("High quality must enforce its internal size limit") }
        catch { limitError = error }
        let error = try XCTUnwrap(limitError)
        var publications = 0
        let observer = s.objectWillChange.sink { publications += 1 }
        s.renderFailed(error)
        let firstCount = publications, issue = try XCTUnwrap(s.issue)
        XCTAssertGreaterThan(firstCount, 0)
        XCTAssertTrue(issue.message.contains("Standard")); XCTAssertTrue(issue.message.contains("zoom"))
        XCTAssertTrue(issue.message.contains("8192"))
        s.renderFailed(error)
        XCTAssertEqual(publications, firstCount); XCTAssertEqual(s.issue?.id, issue.id)
        XCTAssertEqual(s.rasterScale, 2); XCTAssertTrue(s.renderer === renderer)
        withExtendedLifetime(observer) {}
    }
}
#endif
