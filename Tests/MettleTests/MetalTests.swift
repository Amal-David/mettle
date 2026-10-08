import XCTest
import Mettle
#if canImport(Metal)
import Metal

final class MetalTests: XCTestCase {
    func rectangle(_ id:String,_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ color:RGBA)->Node {
        Node(id:id,transform:.translation(x,y),size:Point(w,h),draws:[Draw(paths:[VectorPath("M0 0 H\(w) V\(h) H0 Z")],paint:Paint(color:color),size:Point(w,h))])
    }
    func render(_ root:Node,time:Double=0)->[UInt8] {
        do {
            let renderer=try MetalRenderer(scene:Scene(width:64,height:64,duration:1,root:root))
            return Array(try renderer.pixels(width:64,height:64,time:time))
        } catch { XCTFail("\(error)");return [] }
    }
    func pixel(_ bytes:[UInt8],_ x:Int,_ y:Int)->[UInt8] {
        let i=(y*64+x)*4
        guard bytes.count>=i+4 else {return [0,0,0,0]};return Array(bytes[i..<i+4])
    }
    func testRealMetalDevice() throws { XCTAssertNotNil(MTLCreateSystemDefaultDevice()) }
    func testSolidBGRAAndTransparentBackground() {
        let bytes=render(rectangle("red",8,8,16,16,RGBA(1,0,0)))
        XCTAssertEqual(pixel(bytes,12,12),[0,0,255,255]);XCTAssertEqual(pixel(bytes,40,40),[0,0,0,0])
    }
    func testGroupOpacityIsIsolatedNotMultipliedIntoChildren() {
        var root=Node(id:"group",children:[rectangle("a",0,0,32,32,RGBA(1,0,0)),rectangle("b",16,0,32,32,RGBA(1,0,0))])
        root.opacity=0.5
        let bytes=render(root)
        XCTAssertEqual(pixel(bytes,8,8),pixel(bytes,24,8))
        XCTAssertEqual(Int(pixel(bytes,24,8)[3]),128,accuracy:1)
    }
    func testNativeClipMasksChildren() {
        var root=Node(id:"clip",size:Point(16,16),children:[rectangle("child",0,0,50,50,RGBA(0,1,0))])
        root.clip=[VectorPath("M0 0 H16 V16 H0 Z")]
        let bytes=render(root)
        XCTAssertEqual(pixel(bytes,8,8),[0,255,0,255]);XCTAssertEqual(pixel(bytes,24,24),[0,0,0,0])
    }
    func testZeroAreaClipDoesNotBecomeAnUnclippedGroup() {
        let root = Node(id: "zero-width-frame", size: Point(0, 16),
                        clip: [VectorPath("M0 0 H0 V16 H0 Z")],
                        children: [rectangle("child", 0, 0, 50, 50, RGBA(0, 1, 0))])
        let bytes = render(root)
        XCTAssertEqual(pixel(bytes, 8, 8), [0, 0, 0, 0])
        XCTAssertEqual(pixel(bytes, 24, 24), [0, 0, 0, 0])
    }
    func testEvenOddHoleIsActuallyTransparentOnGPU() {
        var n=rectangle("hole",0,0,48,48,RGBA(0,0,1))
        n.draws[0].paths=[VectorPath("M0 0 H48 V48 H0 Z M16 16 H32 V32 H16 Z",windingRule:"EVENODD")]
        let bytes=render(n)
        XCTAssertEqual(pixel(bytes,8,8),[255,0,0,255]);XCTAssertEqual(pixel(bytes,24,24),[0,0,0,0])
    }
    func testTimelineMovesSourceGeometry() {
        var n=rectangle("moving",0,0,16,16,RGBA(1,0,0))
        n.bindings=[Binding("translationX",base:[0],tracks:[Track([Keyframe(0,[0]),Keyframe(1,[32])])])]
        let start=render(n,time:0),end=render(n,time:1)
        XCTAssertEqual(pixel(start,8,8),[0,0,255,255]);XCTAssertEqual(pixel(end,8,8),[0,0,0,0]);XCTAssertEqual(pixel(end,40,8),[0,0,255,255])
    }
    func testNativeGradientEndpoints() {
        var n=rectangle("gradient",0,0,64,64,RGBA(1,0,0))
        n.draws[0].paint=Paint(kind:"linear",stops:[GradientStop(0,RGBA(1,0,0)),GradientStop(1,RGBA(0,0,1))])
        let bytes=render(n)
        XCTAssertGreaterThan(pixel(bytes,2,32)[2],240);XCTAssertGreaterThan(pixel(bytes,61,32)[0],240)
    }
    func testNestedTransformsAndRotatedClip() {
        var clip=Node(id:"clip",transform:.translation(32,8) * .rotation(.pi/2),size:Point(16,16),children:[rectangle("child",0,0,32,32,RGBA(0,1,0))])
        clip.clip=[VectorPath("M0 0 H16 V16 H0 Z")]
        let bytes=render(Node(id:"root",children:[clip]))
        XCTAssertEqual(pixel(bytes,24,16),[0,255,0,255]);XCTAssertEqual(pixel(bytes,8,16),[0,0,0,0])
    }
    func testRepeatedFrameResourceReuseIsStable() throws {
        let renderer=try MetalRenderer(scene:Scene(width:64,height:64,root:rectangle("r",0,0,32,32,RGBA(1,0,0))))
        let first=try renderer.pixels(width:64,height:64,time:0)
        for _ in 0..<5 { XCTAssertEqual(try renderer.pixels(width:64,height:64,time:0),first) }
    }
    func testSingleSampleRenderingReusesOffscreenSurfacesAfterBothSlotsWarm() throws {
        var group = rectangle("card", 0, 0, 32, 32, RGBA(1, 0, 0))
        group.opacity = 0.5
        let renderer = try MetalRenderer(scene: Scene(width: 64, height: 64, root: group), sampleCount: 1)
        let first = try renderer.pixels(width: 64, height: 64, time: 0)
        XCTAssertEqual(renderer.lastStatistics.surfaceAllocations, 1)
        XCTAssertEqual(try renderer.pixels(width: 64, height: 64, time: 0), first)
        XCTAssertEqual(renderer.lastStatistics.surfaceAllocations, 1)
        for _ in 0..<4 {
            XCTAssertEqual(try renderer.pixels(width: 64, height: 64, time: 0), first)
            XCTAssertEqual(renderer.lastStatistics.surfaceAllocations, 0)
        }
        _ = try renderer.pixels(width: 32, height: 32, time: 0)
        XCTAssertEqual(renderer.lastStatistics.surfaceAllocations, 1, "A resized target needs new surfaces")
    }
    func testSupersampleResolvePreservesOutputSizeAndPremultipliedCoverage() throws {
        let shape = rectangle("subpixel", 2.1, 3.1, 0.4, 0.4, RGBA(1, 0, 0, 0.5))
        let renderer = try MetalRenderer(scene: Scene(width: 64, height: 64, root: shape),
                                         sampleCount: 1, rasterScale: 2)
        let bytes = Array(try renderer.pixels(width: 64, height: 64, time: 0))
        XCTAssertEqual(bytes.count, 64*64*4)
        XCTAssertEqual(renderer.rasterScale, 2)
        // One of four internal pixels is half-opaque red: both color and alpha
        // resolve to 1/8. Averaging straight RGB would leave a bright fringe.
        XCTAssertEqual(Int(pixel(bytes, 2, 3)[2]), 32, accuracy: 1)
        XCTAssertEqual(Int(pixel(bytes, 2, 3)[3]), 32, accuracy: 1)
        XCTAssertEqual(pixel(bytes, 3, 3), [0, 0, 0, 0])
    }
    func testSupersampledClipOpacityAndFrameSlotsSurviveReuseAndResize() throws {
        var group = Node(id: "group", size: Point(16, 16),
                         clip: [VectorPath("M0 0 H16 V16 H0 Z")],
                         children: [rectangle("first", 0, 0, 32, 32, RGBA(1, 0, 0)),
                                    rectangle("overlap", 8, 0, 32, 32, RGBA(1, 0, 0))])
        group.opacity = 0.5
        let renderer = try MetalRenderer(scene: Scene(width: 64, height: 64, root: group), rasterScale: 2)
        let first = try renderer.pixels(width: 64, height: 64, time: 0)
        XCTAssertEqual(Int(pixel(Array(first), 12, 8)[3]), 128, accuracy: 1)
        XCTAssertEqual(pixel(Array(first), 24, 8), [0, 0, 0, 0])
        _ = try renderer.pixels(width: 64, height: 64, time: 0) // Warm the second independent slot.
        for _ in 0..<4 {
            XCTAssertEqual(try renderer.pixels(width: 64, height: 64, time: 0), first)
            XCTAssertEqual(renderer.lastStatistics.surfaceAllocations, 0)
        }
        let resized = try renderer.pixels(width: 32, height: 32, time: 0)
        XCTAssertEqual(resized.count, 32*32*4)
        XCTAssertEqual(try renderer.pixels(width: 64, height: 64, time: 0), first)
    }
    func testSupersampleLimitsApplyToInternalTargetsBeforeAllocation() throws {
        let scene = Scene(width: 64, height: 64, root: Node(id: "root"))
        let renderer = try MetalRenderer(scene: scene, rasterScale: 2)
        XCTAssertThrowsError(try renderer.makeTarget(width: 4097, height: 1))
        XCTAssertThrowsError(try renderer.makeTarget(width: 2048, height: 1025))
        for scale in [0, 3, Int.max] { XCTAssertThrowsError(try MetalRenderer(scene: scene, rasterScale: scale)) }
        XCTAssertNoThrow(try renderer.pixels(width: 64, height: 64, time: 0))
    }
    func testColorMotionUsesTheOriginalPaintIndexAndEffectiveAlpha() {
        var node = rectangle("multi-fill", 0, 0, 16, 16, RGBA(1, 0, 0))
        node.draws[0].paintIndex = 2
        node.draws.append(Draw(paths: [VectorPath("M16 0 H32 V16 H16 Z")],
                               paint: Paint(color: RGBA(0, 0, 1), opacity: 0.25),
                               size: Point(32, 16), paintIndex: 7))
        node.bindings = [Binding("fills:7", base: [0, 0, 1, 0.25], tracks: [
            Track([Keyframe(0, [0, 0, 1, 0.25]), Keyframe(1, [0, 1, 0, 0.5])])
        ])]
        let bytes = render(node, time: 1)
        XCTAssertEqual(pixel(bytes, 8, 8), [0, 0, 255, 255])
        let animated = pixel(bytes, 24, 8)
        XCTAssertEqual(animated[0], 0); XCTAssertEqual(animated[2], 0)
        XCTAssertEqual(Int(animated[1]), 128, accuracy: 1)
        XCTAssertEqual(Int(animated[3]), 128, accuracy: 1)
    }
    func testRenderRejectsNonRenderTargetsBeforeEncoding() throws {
        let renderer = try MetalRenderer(scene: Scene(width: 64, height: 64, root: Node(id: "root")))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
        descriptor.usage = .shaderRead
        let texture = try XCTUnwrap(renderer.device.makeTexture(descriptor: descriptor))
        XCTAssertThrowsError(try renderer.render(to: texture, time: 0))
        // Invalid input must not consume a frame slot or poison later rendering.
        XCTAssertNoThrow(try renderer.pixels(width: 64, height: 64, time: 0))
    }
    func testInvalidTessellationConfigurationFailsBeforeGPUPreparation() {
        let scene = Scene(width: 64, height: 64, root: Node(id: "root"))
        for tolerance in [0.0, -1.0, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try MetalRenderer(scene: scene, curveTolerance: tolerance))
        }
        XCTAssertThrowsError(try MetalRenderer(scene: scene, sampleCount: 0))
    }
}
#else
final class MetalPlatformTests: XCTestCase {
    func testMetalUnavailableOnThisPlatform() throws { throw XCTSkip("GPU tests require Apple Metal; run swift test on a Mac.") }
}
#endif
