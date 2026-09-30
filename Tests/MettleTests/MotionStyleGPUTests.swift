import XCTest
import Mettle
#if canImport(Metal)
final class MotionStyleGPUTests: XCTestCase {
    private func makeRenderer() throws -> MetalRenderer {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let doc = try SceneDocument.load(url: root.appendingPathComponent("fixtures/motion-2026/styles.figmetal.json"))
        return try MetalRenderer(scene: doc.scenes[0])
    }
    private func pixel(_ data: Data, _ x: Int, _ y: Int) -> [UInt8] {
        let i = (y * 600 + x) * 4
        return Array(data[i..<(i + 4)])
    }
    private func near(_ actual: [UInt8], _ expected: [UInt8], file: StaticString = #filePath, line: UInt = #line) {
        for (a, b) in zip(actual, expected) { XCTAssertLessThanOrEqual(abs(Int(a) - Int(b)), 1, file: file, line: line) }
    }
    func testDelayedStyleOpacityActuallyReachesMetal() throws {
        let r = try makeRenderer()
        // Figma's independent CSS: opacity 0 through .2s, .5 at .6s, 1 at 1s.
        for (t, expected) in [(0.0, [20,15,13,255]), (0.2, [20,15,13,255]), (0.6, [138,59,70,255]), (1.0, [255,102,128,255])] {
            let data = try r.pixels(width: 600, height: 320, time: t)
            near(pixel(data, 70, 70), expected.map(UInt8.init))
        }
    }
    func testIndependentExitPlacementMovesTheRenderedCard() throws {
        let r = try makeRenderer()
        // Figma CSS gives x=40 at 1.2s and x=64 at 1.9s, after the 1.5s exit delay.
        let middle = try r.pixels(width: 600, height: 320, time: 1.2)
        let end = try r.pixels(width: 600, height: 320, time: 1.9)
        near(pixel(middle,45,70), [255,102,128,255])
        near(pixel(middle,150,70), [20,15,13,255])
        near(pixel(end,45,70), [20,15,13,255])
        near(pixel(end,150,70), [255,102,128,255])
    }
    func testComposedStylesReplayIdenticallyAfterSeeking() throws {
        let r = try makeRenderer()
        let first = try r.pixels(width: 600, height: 320, time: 0.6)
        _ = try r.pixels(width: 600, height: 320, time: 1.9)
        _ = try r.pixels(width: 600, height: 320, time: 0)
        XCTAssertEqual(first, try r.pixels(width: 600, height: 320, time: 0.6))
    }
}
#endif
