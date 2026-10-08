import XCTest
@testable import MettleCore

final class RuntimeValidationTests: XCTestCase {
    private func draw(index: Int = 0, role: String = "fills", kind: String = "solid") -> Draw {
        Draw(paths: [VectorPath("M0 0 H10 V10 H0 Z")],
             paint: Paint(kind: kind, stops: kind == "solid" ? [] : [GradientStop(0, .white), GradientStop(1, .white)]),
             size: Point(10, 10), paintIndex: index, role: role)
    }

    private func validate(_ node: Node) throws {
        try SceneDocument(scenes: [Scene(width: 10, height: 10, duration: 1, root: node)]).validate()
    }

    func testDuplicateFieldsCannotSilentlyOverrideOrDoubleApplyMotion() {
        let track = Track([Keyframe(0, [0]), Keyframe(1, [10])])
        let node = Node(id: "card", bindings: [
            Binding("translationX", base: [0], tracks: [track]),
            Binding("translationX", base: [0], tracks: [track])
        ])
        XCTAssertThrowsError(try validate(node))
    }

    func testPaintBindingRequiresCanonicalIndex() {
        for field in ["fills:01", "fills:+1", "fills:-1", "fills:1:2", "fills:", "strokes: 1"] {
            XCTAssertThrowsError(try Binding(field, base: [1, 0, 0, 1], tracks: []).validate(), field)
        }
        XCTAssertNoThrow(try Binding("fills:12", base: [1, 0, 0, 1], tracks: []).validate())
    }

    func testUnknownDrawRoleAndNegativePaintIndexCannotDisappearSilently() {
        XCTAssertThrowsError(try validate(Node(id: "card", draws: [draw(role: "fill")])))
        XCTAssertThrowsError(try validate(Node(id: "card", draws: [draw(index: -1)])))
    }

    func testColorBindingMustReachMatchingOriginalSolidPaint() {
        let binding = Binding("fills:7", base: [1, 0, 0, 1], tracks: [])
        // Original paint indices can be sparse when earlier source paints are hidden.
        XCTAssertNoThrow(try validate(Node(id: "card", draws: [draw(index: 7)], bindings: [binding])))
        XCTAssertThrowsError(try validate(Node(id: "card", draws: [draw(index: 0)], bindings: [binding])))
        XCTAssertThrowsError(try validate(Node(id: "card", draws: [draw(index: 7, role: "strokes")], bindings: [binding])))
        XCTAssertThrowsError(try validate(Node(id: "card", draws: [draw(index: 7, kind: "linear")], bindings: [binding])))
    }

    func testSeveralPathsMayShareTheSameSourcePaintBinding() {
        let binding = Binding("fills:7", base: [1, 0, 0, 1], tracks: [])
        XCTAssertNoThrow(try validate(Node(id: "outlined-text", draws: [draw(index: 7), draw(index: 7)], bindings: [binding])))
    }

    func testMalformedBindingIsRejectedBeforePaintLookup() {
        for field in ["fills:bad", "fills:", "fills:2:7"] {
            XCTAssertThrowsError(try validate(Node(id: "card", draws: [draw()], bindings: [
                Binding(field, base: [1, 0, 0, 1], tracks: [])
            ])))
        }
    }
}
