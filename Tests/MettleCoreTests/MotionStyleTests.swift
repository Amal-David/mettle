import XCTest
@testable import MettleCore

final class MotionStyleTests: XCTestCase {
    func testLiveFigmaStylesMatchIndependentCSSKeyTimes() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let doc=try SceneDocument.load(url:root.appendingPathComponent("fixtures/motion-2026/styles.figmetal.json"))
        let node=try XCTUnwrap(doc.scenes[0].root.children.first(where:{$0.id=="13:3"}))
        // Independent Figma get_motion_context CSS: translate -24 at 0/10%,
        // 0 at 50/75%, +24 at 95/100%; opacity 0 at 0/10%, 1 at 50/100%.
        for (time,x,alpha) in [(0.0,16.0,0.0),(0.2,16.0,0.0),(1.0,40.0,1.0),(1.5,40.0,1.0),(1.9,64.0,1.0),(2.0,64.0,1.0)] {
            let state=node.evaluate(at:time)
            XCTAssertEqual(state.transform.tx,x,accuracy:1e-6)
            XCTAssertEqual(state.opacity,alpha,accuracy:1e-6)
        }
    }
    func testPlacedTrackHoldsBeforeDelayAndAfterEnd() {
        let track=Track([Keyframe(0,[-24]),Keyframe(0.8,[0])],operation:"offset",timelineOffset:0.2)
        XCTAssertEqual(track.sample(0)!,[-24]);XCTAssertEqual(track.sample(0.2)!,[-24])
        XCTAssertEqual(track.sample(0.6)![0],-12,accuracy:1e-10)
        XCTAssertEqual(track.sample(1)!,[0]);XCTAssertEqual(track.sample(4)!,[0])
    }
    func testComposedEntranceAndExitDoNotLoseEitherStyle() {
        let enter=Track([Keyframe(0,[-24]),Keyframe(0.8,[0])],operation:"offset",timelineOffset:0.2)
        let exit=Track([Keyframe(0,[0]),Keyframe(0.4,[24])],operation:"offset",timelineOffset:1.5)
        var node=Node(id:"card",transform:.translation(40,40))
        node.bindings=[Binding("translationX",base:[0],tracks:[enter,exit])]
        for (time,x) in [(0.0,16.0),(0.6,28.0),(1.2,40.0),(1.7,52.0),(2.0,64.0)] {
            XCTAssertEqual(node.evaluate(at:time).transform.tx,x,accuracy:1e-9)
        }
    }
    func testPlacedOpacityScaleComposesWithSourceOpacity() {
        let track=Track([Keyframe(0,[0]),Keyframe(1,[1])],operation:"scale",timelineOffset:0.4)
        let binding=Binding("opacity",base:[0.8],tracks:[track])
        XCTAssertEqual(binding.sample(0),[0]);XCTAssertEqual(binding.sample(0.9)[0],0.4,accuracy:1e-10)
    }
    func testBackEasingOvershootsWithoutClampingGeometry() {
        let e=Easing("cubic",control:[0.45,1.45,0.8,1])
        XCTAssertGreaterThan(e.sample(0.7),1)
        let t=Track([Keyframe(0,[-24],easing:e),Keyframe(1,[0])],operation:"offset",timelineOffset:0.2)
        XCTAssertGreaterThan(t.sample(0.9)![0],0)
    }
    func testLegacyTrackDecodesWithNoOffset() throws {
        let data=Data(#"{"operation":"set","keyframes":[{"time":0,"value":[0],"easing":{"kind":"linear","control":[]}},{"time":1,"value":[10],"easing":{"kind":"linear","control":[]}}]}"#.utf8)
        let t=try JSONDecoder().decode(Track.self,from:data)
        XCTAssertNil(t.timelineOffset);XCTAssertEqual(t.sample(0.5),[5])
    }
    func testVersionTwoRoundTripsPlacedTracksAndVersionOneStillLoads() throws {
        var n=Node(id:"x");n.bindings=[Binding("opacity",base:[1],tracks:[Track([Keyframe(0,[1])],timelineOffset:0.2)])]
        var d=SceneDocument(scenes:[Scene(width:100,height:100,duration:1,root:n)])
        XCTAssertEqual(d.version,2);let round=try SceneDocument.decode(JSONEncoder().encode(d));XCTAssertEqual(round.scenes[0].root.bindings[0].tracks[0].timelineOffset,0.2)
        d.version=1;XCTAssertThrowsError(try d.validate())
        d.scenes[0].root.bindings[0].tracks[0].timelineOffset=nil;XCTAssertNoThrow(try SceneDocument.decode(JSONEncoder().encode(d)))
    }
    func testInvalidStyleOffsetsAndOutOfRangeEndpointsAreRejected() {
        for offset in [-1.0,Double.infinity,Double.nan,86401.0] {
            XCTAssertThrowsError(try Binding("opacity",base:[1],tracks:[Track([Keyframe(0,[1])],timelineOffset:offset)]).validate())
        }
        XCTAssertThrowsError(try Binding("opacity",base:[1],tracks:[Track([Keyframe(10,[1])],timelineOffset:86400)]).validate())
    }
    func testNonfiniteSampleIsNotUsed() {
        XCTAssertNil(Track([Keyframe(0,[1])],timelineOffset:0.2).sample(.nan))
    }
    func testLottieGetsActionableWrongFormatError() {
        XCTAssertThrowsError(try SceneDocument.decode(Data(#"{"v":"5.7","fr":30,"layers":[]}"#.utf8))) { error in
            XCTAssertTrue(String(describing:error).contains("Lottie export"));XCTAssertTrue(String(describing:error).contains("Mettle"))
        }
        XCTAssertThrowsError(try SceneDocument.decode(Data([0x50,0x4b,0x03,0x04]))) { error in
            XCTAssertTrue(String(describing:error).contains("dotLottie"))
        }
    }
    func testStyleSeekingRemainsDeterministic() {
        let track=Track([Keyframe(0,[0]),Keyframe(1,[10])],timelineOffset:0.7)
        let first=track.sample(1.1)
        _=track.sample(2.5);_=track.sample(0.1);XCTAssertEqual(track.sample(1.1),first)
    }
    func testChatBubbleOvershootPreservesItsBottomLeftAnchor() {
        // Contract case using Figma's documented chat-bubble scale curve and
        // bottom-left anchor, not a captured Community animation reference:
        // https://help.figma.com/hc/en-us/articles/41837837143831
        let scale = Track([Keyframe(0, [0], easing: Easing("cubic", control: [0, 0, 0.3, 1.4])),
                           Keyframe(0.25, [1])])
        let bubble = Node(id: "bubble", transform: .translation(24, 12), size: Point(60, 40),
                          origin: Point(0, 40), bindings: [
                            Binding("scaleX", base: [1], tracks: [scale]),
                            Binding("scaleY", base: [1], tracks: [scale])
                          ])
        for time in [0.0, 0.08, 0.17, 0.25] {
            let anchor = bubble.evaluate(at: time).transform.apply(Point(0, 40))
            XCTAssertEqual(anchor.x, 24, accuracy: 1e-9)
            XCTAssertEqual(anchor.y, 52, accuracy: 1e-9)
        }
        XCTAssertEqual(bubble.evaluate(at: 0).transform.apply(Point(60, 0)), Point(24, 52))
        let overshoot = bubble.evaluate(at: 0.17).transform.apply(Point(60, 0))
        XCTAssertGreaterThan(overshoot.x, 84)
        XCTAssertLessThan(overshoot.y, 12)
        XCTAssertEqual(bubble.evaluate(at: 0.25).transform.apply(Point(60, 0)), Point(84, 12))
    }
}
