import XCTest
@testable import MettleCore

final class CoreTests: XCTestCase {
    let rect = "M0 0 H10 V10 H0 Z"
    func area(_ p:[Point])->Double {
        var total = 0.0
        for i in stride(from:0,to:p.count,by:3) {
            let a = p[i+1] - p[i], b = p[i+2] - p[i]
            total += abs(a.cross(b))/2
        }
        return total
    }
    func shape(id:String="a") -> Node {
        Node(id:id,size:Point(10,10),draws:[Draw(paths:[VectorPath(rect)],paint:Paint(),size:Point(10,10))])
    }
    func document(_ root:Node?=nil)->SceneDocument { SceneDocument(scenes:[Scene(width:100,height:100,root:root ?? shape())]) }

    func testAffineCompositionIsParentTimesChild() {
        let m = Affine.translation(10,20) * .scale(2,3)
        XCTAssertEqual(m.apply(Point(4,5)),Point(18,35))
    }
    func testAffineInverse() throws {
        let m = Affine.translation(7,-3) * .rotation(0.7) * .scale(2,0.3)
        let p = try m.inverted().apply(m.apply(Point(100,-60)))
        XCTAssertEqual(p.x,100,accuracy:1e-8);XCTAssertEqual(p.y,-60,accuracy:1e-8)
    }
    func testSingularInverseFails() { XCTAssertThrowsError(try Affine.scale(0,1).inverted()) }
    func testLinearAndHoldEasing() {
        XCTAssertEqual(Easing().sample(0.3),0.3)
        XCTAssertEqual(Easing("hold").sample(0.999),0)
        XCTAssertEqual(Easing("hold").sample(1),1)
    }
    func testCubicSolvesXNotOnlyY() {
        let ease = Easing("cubic",control:[0.42,0,1,1])
        XCTAssertEqual(ease.sample(0.5),0.3153568,accuracy:1e-6)
        XCTAssertEqual(ease.sample(0),0);XCTAssertEqual(ease.sample(1),1)
    }
    func testCubicOvershootNotClamped() {
        XCTAssertGreaterThan(Easing("cubic",control:[0.2,2,0.8,2]).sample(0.5),1)
    }
    func testOutgoingHoldKeyframe() {
        let t = Track([Keyframe(0,[2],easing:Easing("hold")),Keyframe(1,[8]),Keyframe(2,[12])])
        XCTAssertEqual(t.sample(0.999),[2]);XCTAssertEqual(t.sample(1),[8]);XCTAssertEqual(t.sample(1.5),[10])
    }
    func testTrackEndpointClamping() {
        let t = Track([Keyframe(1,[2]),Keyframe(2,[4])])
        XCTAssertEqual(t.sample(-1),[2]);XCTAssertEqual(t.sample(4),[4])
    }
    func testTrackOperationsStayInSourceOrder() throws {
        let b = Binding("translationX",base:[1],tracks:[Track([Keyframe(0,[3])]),Track([Keyframe(0,[2])],operation:"offset"),Track([Keyframe(0,[4])],operation:"scale")])
        try b.validate();XCTAssertEqual(b.sample(0),[20])
    }
    func testLoopAndPingPongTime() {
        var scene = Scene(width:10,height:10,duration:2,loop:"loop",root:shape())
        XCTAssertEqual(scene.localTime(2),0);XCTAssertEqual(scene.localTime(2.5),0.5);XCTAssertEqual(scene.localTime(-1),0)
        scene.loop = "pingPong";XCTAssertEqual(scene.localTime(2),2);XCTAssertEqual(scene.localTime(3),1);XCTAssertEqual(scene.localTime(4),0)
        scene.loop = "once";XCTAssertEqual(scene.localTime(9),2)
    }
    func testSourceTranslationDoesNotDoubleApplyBase() {
        var n = shape();n.transform = .translation(100,40)
        n.bindings = [Binding("translationX",base:[100],tracks:[Track([Keyframe(0,[100]),Keyframe(1,[140])])])]
        XCTAssertEqual(n.evaluate(at:0).transform.tx,100)
        XCTAssertEqual(n.evaluate(at:0.5).transform.tx,120)
    }
    func testRotationPreservesExplicitPivot() {
        var n = shape();n.origin = Point(5,5)
        n.bindings = [Binding("rotation",base:[0],tracks:[Track([Keyframe(0,[0]),Keyframe(1,[90])])])]
        let state = n.evaluate(at:1)
        let center = state.transform.apply(Point(5,5)), corner = state.transform.apply(Point(10,5))
        XCTAssertEqual(center.x,5,accuracy:1e-9);XCTAssertEqual(center.y,5,accuracy:1e-9)
        XCTAssertEqual(corner.x,5,accuracy:1e-9);XCTAssertEqual(corner.y,0,accuracy:1e-9)
    }
    func testSeekIsDeterministic() {
        var n = shape();n.bindings = [Binding("opacity",base:[1],tracks:[Track([Keyframe(0,[0]),Keyframe(1,[1])])])]
        let first=n.evaluate(at:0.25);_ = n.evaluate(at:0.99);_ = n.evaluate(at:0)
        XCTAssertEqual(first.opacity,n.evaluate(at:0.25).opacity)
    }
    func testRelativePathAndRepeatedCommands() throws {
        let p = try PathParser().parse("m 2 3 10 0 v10 h-10 z")
        XCTAssertEqual(p,[[Point(2,3),Point(12,3),Point(12,13),Point(2,13)]])
    }
    func testCubicAndQuadraticFlattening() throws {
        let p=try PathParser(tolerance:0.01).parse("M0 0 C0 10 10 10 10 0 Q5 -10 0 0 Z")
        XCTAssertGreaterThan(p[0].count,20)
        XCTAssertTrue(p[0].contains(where:{$0.y>7}));XCTAssertTrue(p[0].contains(where:{$0.y < -4}))
    }
    func testScientificNotation() throws {
        let p=try PathParser().parse("M1e1,-2E0 L20 -2 L20 8 Z")
        XCTAssertEqual(p[0][0],Point(10,-2))
    }
    func testInvalidPathAndArcAreRejected() {
        for s in ["M0 0 L1", "M0 0 ? L1 1", "M0 0 A5 5 0 0 0 10 10", "L10 10", "M0 0 Z 2 3"] {
            XCTAssertThrowsError(try PathParser().parse(s),s)
        }
    }
    func testPathPointBudget() {
        XCTAssertThrowsError(try PathParser(tolerance:0.001,pointLimit:5).parse("M0 0 C0 100 100 100 100 0 Z"))
    }
    func testRectangleArea() throws { XCTAssertEqual(try area(Tessellator().tessellate(paths:[VectorPath(rect)])),100,accuracy:1e-9) }
    func testConcavePolygonArea() throws {
        let p=try Tessellator().tessellate(paths:[VectorPath("M0 0 H10 V5 H5 V10 H0 Z")])
        XCTAssertEqual(area(p),75,accuracy:1e-9)
    }
    func testEvenOddHole() throws {
        let p=try Tessellator().tessellate(paths:[VectorPath(rect+" M3 3 H7 V7 H3 Z",windingRule:"EVENODD")])
        XCTAssertEqual(area(p),84,accuracy:1e-9)
    }
    func testNonzeroSameWindingDoesNotCutHole() throws {
        let p=try Tessellator().tessellate(paths:[VectorPath(rect+" M3 3 H7 V7 H3 Z")])
        XCTAssertEqual(area(p),100,accuracy:1e-9)
    }
    func testNonzeroReversedHole() throws {
        let p=try Tessellator().tessellate(paths:[VectorPath(rect+" M3 3 V7 H7 V3 Z")])
        XCTAssertEqual(area(p),84,accuracy:1e-9)
    }
    func testSelfIntersectingBowTie() throws {
        let p=try Tessellator().tessellate(paths:[VectorPath("M0 0 L10 10 L0 10 L10 0 Z",windingRule:"EVENODD")])
        XCTAssertEqual(area(p),50,accuracy:1e-9)
    }
    func testDocumentRoundTrip() throws {
        let d=try SceneDocument.decode(JSONEncoder().encode(document()))
        XCTAssertEqual(d.scenes.first?.root.id,"a")
    }
    func testUnsupportedVersionAndDuplicateIDs() {
        var d=document();d.version=2;XCTAssertThrowsError(try d.validate())
        d=document(Node(id:"a",children:[shape()]));XCTAssertThrowsError(try d.validate())
    }
    func testInvalidDimensionsAndGradientStopOrder() {
        var d=document();d.scenes[0].width = -1;XCTAssertThrowsError(try d.validate())
        d=document();d.scenes[0].root.draws[0].paint = Paint(kind:"linear",stops:[GradientStop(1,.white),GradientStop(0,.white)])
        XCTAssertThrowsError(try d.validate())
    }
    func testDiagnosticBlocksPartialDocument() throws {
        var d=document();d.diagnostics=[Diagnostic(severity:"error",code:"TEST",nodeID:"a",message:"Unsupported")]
        XCTAssertThrowsError(try d.validate());try d.validate(allowPartial:true)
    }
    func testUnknownMotionFieldAndDuplicateTimes() {
        XCTAssertThrowsError(try Binding("width",base:[1],tracks:[]).validate())
        XCTAssertThrowsError(try Binding("opacity",base:[1],tracks:[Track([Keyframe(0,[0]),Keyframe(0,[1])])]).validate())
    }
}
