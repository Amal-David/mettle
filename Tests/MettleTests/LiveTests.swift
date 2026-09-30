import XCTest
import Mettle
#if canImport(Metal)
import Metal

final class LiveTests: XCTestCase {
    func renderer(_ name:String) throws -> MetalRenderer {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let doc=try SceneDocument.load(url:root.appendingPathComponent("fixtures/live/\(name).figmetal.json"))
        return try MetalRenderer(scene:doc.scenes[0])
    }
    func pixel(_ data:Data,_ width:Int,_ x:Int,_ y:Int)->[UInt8] {
        let index=(y*width+x)*4
        return Array(data[index..<(index+4)])
    }
    func near(_ actual:[UInt8],_ expected:[UInt8],file:StaticString=#filePath,line:UInt=#line) {
        for (a,b) in zip(actual,expected) {XCTAssertLessThanOrEqual(abs(Int(a)-Int(b)),1,file:file,line:line)}
    }
    func testRepeatedLiveRenderIsDeterministic() throws {
        let r=try renderer("motion")
        let first=try r.pixels(width:320,height:180,time:0.75)
        _ = try r.pixels(width:320,height:180,time:1.5)
        let replay=try r.pixels(width:320,height:180,time:0.75)
        XCTAssertEqual(first,replay)
    }
    func testLiveFillStackLastPaintIsOnTop() throws {
        let r=try renderer("conformance"),data=try r.pixels(width:600,height:420,time:0)
        near(pixel(data,600,400,50),[230,51,26,255])
    }
    func testLiveMotionAddsSourceOffsetToStaticPosition() throws {
        let r=try renderer("motion")
        let a=try r.pixels(width:320,height:180,time:0)
        near(pixel(a,320,80,80),[178,204,51,255])
        near(pixel(a,320,24,80),[28,18,13,255])
        let b=try r.pixels(width:320,height:180,time:1)
        near(pixel(b,320,280,80),[66,64,22,255])
        near(pixel(b,320,80,80),[28,18,13,255])
    }
    func testLiveGlyphCountersStayOpen() throws {
        let r=try renderer("conformance"),data=try r.pixels(width:600,height:420,time:0)
        near(pixel(data,600,62,306),[28,18,13,255])
        near(pixel(data,600,62,314),[28,18,13,255])
    }
    func testLiveStrokeOutlineOffsetIsNotLost() throws {
        let r=try renderer("conformance"),data=try r.pixels(width:600,height:420,time:0)
        near(pixel(data,600,406,197),[51,191,229,255])
        near(pixel(data,600,396,197),[28,18,13,255])
    }
}
#endif
