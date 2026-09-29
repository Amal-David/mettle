@_exported import FigmaMetalCore
#if canImport(Metal)
import Foundation
import Metal
import simd

public struct RenderStatistics: Sendable {
    public var vertices: Int = 0
    public var drawCalls: Int = 0
    public var surfaceCount: Int = 0
    public var gpuMilliseconds: Double = 0
}
private struct Uniforms {
    var transform: simd_float4x4
    var viewportAndSize: SIMD4<Float>
    var color: SIMD4<Float>
    var gradientRow0: SIMD4<Float>
    var gradientRow1: SIMD4<Float>
    var paintInfo: SIMD4<Float>
}
private struct GPUStop { var color: SIMD4<Float>; var info: SIMD4<Float> }
private struct Mesh {
    let buffer: MTLBuffer
    let count: Int
}
private struct PreparedDraw { let source: Draw; let mesh: Mesh }
private final class PreparedNode {
    let source: Node
    let draws: [PreparedDraw]
    let clip: Mesh?
    let children: [PreparedNode]
    init(_ source: Node, device: MTLDevice, vertices: inout Int, tolerance: Double) throws {
        self.source = source
        func makeMesh(_ paths: [VectorPath]) throws -> Mesh? {
            let points = try Tessellator().tessellate(paths: paths,tolerance:tolerance)
            if points.isEmpty { return nil }
            vertices += points.count
            guard vertices <= 4_000_000 else { throw SceneError.invalid("Scene exceeds 4 million vertices") }
            let data = points.map {SIMD2<Float>(Float($0.x),Float($0.y))}
            guard let buffer = device.makeBuffer(bytes: data, length: data.count*MemoryLayout<SIMD2<Float>>.stride,
                                                 options: .storageModeShared) else { throw SceneError.gpu("Vertex buffer allocation failed") }
            return Mesh(buffer:buffer,count:data.count)
        }
        var draws: [PreparedDraw] = []
        for draw in source.draws { if let mesh = try makeMesh(draw.paths) { draws.append(PreparedDraw(source:draw,mesh:mesh)) } }
        self.draws = draws
        self.clip = try makeMesh(source.clip)
        self.children = try source.children.map { try PreparedNode($0,device:device,vertices:&vertices,tolerance:tolerance) }
    }
}
private final class Surface {
    var color: MTLTexture
    let multisample: MTLTexture?
    var initialized = false
    var inUse = false
    init(color: MTLTexture, multisample: MTLTexture?) { self.color = color; self.multisample = multisample }
}
private final class FrameResources {
    var surfaces: [Surface] = []
    var rootMSAA: MTLTexture?
}

/// All geometry and compositing are rendered with Metal. No CoreGraphics drawing,
/// Core Animation playback, browser, Skia, Rive, Lottie, or frame-video intermediary.
/// Call from ONE thread. SwiftUI integration uses the main thread.
public final class MetalRenderer {
    public let device: MTLDevice
    public let scene: Scene
    public let sampleCount: Int
    public let vertexCount: Int
    public private(set) var lastStatistics = RenderStatistics()
    private let root: PreparedNode
    private let queue: MTLCommandQueue
    private let paintPipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let slots = [FrameResources(),FrameResources()]
    private let semaphore = DispatchSemaphore(value:2)
    private var nextSlot = 0
    private let surfaceBudget = 256*1024*1024

    public init(scene: Scene, device: MTLDevice? = MTLCreateSystemDefaultDevice(),
                sampleCount requestedSamples: Int = 4, curveTolerance: Double = 0.2) throws {
        try SceneDocument(scenes:[scene]).validate()
        guard let device, let queue = device.makeCommandQueue() else { throw SceneError.gpu("No Metal device/queue") }
        self.device = device; self.queue = queue; self.scene = scene
        let samples = device.supportsTextureSampleCount(requestedSamples) ? requestedSamples : 1
        self.sampleCount = samples
        guard let url = Bundle.module.url(forResource:"FigmaMetal",withExtension:"metal",subdirectory:"Shaders") else {
            throw SceneError.gpu("Packaged Metal shader source is missing")
        }
        let library = try device.makeLibrary(source:String(contentsOf:url,encoding:.utf8),options:nil)
        func pipeline(_ vertex: String,_ fragment: String) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name:vertex); d.fragmentFunction = library.makeFunction(name:fragment)
            d.rasterSampleCount = samples
            let c = d.colorAttachments[0]!
            c.pixelFormat = .bgra8Unorm; c.isBlendingEnabled = true
            c.sourceRGBBlendFactor = .one; c.destinationRGBBlendFactor = .oneMinusSourceAlpha
            c.sourceAlphaBlendFactor = .one; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor:d)
        }
        self.paintPipeline = try pipeline("fm_vertex","fm_fragment")
        self.compositePipeline = try pipeline("fm_fullscreen","fm_composite")
        var vertices = 0
        self.root = try PreparedNode(scene.root,device:device,vertices:&vertices,tolerance:curveTolerance)
        self.vertexCount = vertices
    }

    public func makeTarget(width: Int, height: Int) throws -> MTLTexture {
        guard width > 0, height > 0, width <= 8192, height <= 8192, width*height <= 8_388_608 else {
            throw SceneError.invalid("Render target exceeds 8 megapixels or 8192 on one axis")
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:width,height:height,mipmapped:false)
        d.usage = [.renderTarget,.shaderRead]; d.storageMode = .private
        guard let t = device.makeTexture(descriptor:d) else { throw SceneError.gpu("Target allocation failed") }
        return t
    }
    private func makeMSAA(width:Int,height:Int) throws -> MTLTexture? {
        if sampleCount == 1 { return nil }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:width,height:height,mipmapped:false)
        d.textureType = .type2DMultisample; d.sampleCount = sampleCount
        d.usage = [.renderTarget]; d.storageMode = .private
        guard let t = device.makeTexture(descriptor:d) else { throw SceneError.gpu("MSAA allocation failed") }
        return t
    }
    private func acquire(_ frame: FrameResources, width:Int,height:Int) throws -> Surface {
        if let s = frame.surfaces.first(where:{ !$0.inUse && $0.color.width == width && $0.color.height == height }) {
            s.inUse = true; s.initialized = false; return s
        }
        let bytes = width*height*4*(sampleCount+1)
        guard (frame.surfaces.count+2)*bytes <= surfaceBudget else {
            throw SceneError.gpu("Offscreen surface budget exceeded. Reduce render size or nested isolation/clips.")
        }
        let s = Surface(color:try makeTarget(width:width,height:height),multisample:try makeMSAA(width:width,height:height))
        s.inUse = true; frame.surfaces.append(s); return s
    }
    private func encoder(_ surface: Surface, _ command: MTLCommandBuffer) throws -> MTLRenderCommandEncoder {
        let d = MTLRenderPassDescriptor()
        let c = d.colorAttachments[0]!
        // Keep multisample contents across incremental passes.
        c.texture = surface.multisample ?? surface.color
        c.loadAction = surface.initialized ? .load : .clear
        c.clearColor = MTLClearColorMake(0,0,0,0)
        if surface.multisample != nil { c.resolveTexture = surface.color; c.storeAction = .storeAndMultisampleResolve }
        else { c.storeAction = .store }
        guard let e = command.makeRenderCommandEncoder(descriptor:d) else { throw SceneError.gpu("Render encoder creation failed") }
        surface.initialized = true; e.setCullMode(.none)
        return e
    }
    private func draw(_ mesh: Mesh, paint: Paint, size: Point, world: Affine,
                      into surface:Surface, command:MTLCommandBuffer, stats:inout RenderStatistics) throws {
        let e = try encoder(surface,command)
        e.setRenderPipelineState(paintPipeline)
        let m = simd_float4x4(columns:(SIMD4(Float(world.a),Float(world.b),0,0),
                                      SIMD4(Float(world.c),Float(world.d),0,0), SIMD4(0,0,1,0),
                                      SIMD4(Float(world.tx),Float(world.ty),0,1)))
        let p = paint.transform
        var u = Uniforms(transform:m,viewportAndSize:SIMD4(Float(surface.color.width),Float(surface.color.height),Float(size.x),Float(size.y)),
                         color:SIMD4(Float(paint.color.r),Float(paint.color.g),Float(paint.color.b),Float(paint.color.a)),
                         gradientRow0:SIMD4(Float(p.a),Float(p.c),Float(p.tx),0),gradientRow1:SIMD4(Float(p.b),Float(p.d),Float(p.ty),0),
                         paintInfo:SIMD4(paint.kind == "linear" ? 1 : paint.kind == "radial" ? 2 : 0,Float(paint.stops.count),Float(paint.opacity),0))
        var stops = paint.stops.map { GPUStop(color:SIMD4(Float($0.color.r),Float($0.color.g),Float($0.color.b),Float($0.color.a)),info:SIMD4(Float($0.position),0,0,0)) }
        if stops.isEmpty { stops = [GPUStop(color:SIMD4(1,1,1,1),info:.zero)] }
        e.setVertexBuffer(mesh.buffer,offset:0,index:0)
        e.setVertexBytes(&u,length:MemoryLayout<Uniforms>.stride,index:1)
        e.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:0)
        e.setFragmentBytes(stops,length:stops.count*MemoryLayout<GPUStop>.stride,index:1)
        e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:mesh.count)
        e.endEncoding(); stats.drawCalls += 1
    }
    private func composite(_ source:Surface, mask:Surface? = nil, alpha:Double = 1,
                           into target:Surface, command:MTLCommandBuffer, stats:inout RenderStatistics) throws {
        if !source.initialized { let e = try encoder(source,command); e.endEncoding() }
        let e = try encoder(target,command)
        e.setRenderPipelineState(compositePipeline)
        e.setFragmentTexture(source.color,index:0); e.setFragmentTexture(mask?.color ?? source.color,index:1)
        var options = SIMD4<Float>(Float(alpha),mask == nil ? 0 : 1,0,0)
        e.setFragmentBytes(&options,length:MemoryLayout<SIMD4<Float>>.stride,index:0)
        e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3); e.endEncoding(); stats.drawCalls += 1
    }
    private func renderNode(_ node:PreparedNode, parent:Affine, time:Double, target:Surface,
                            frame:FrameResources, command:MTLCommandBuffer, stats:inout RenderStatistics) throws {
        let state = node.source.evaluate(at:time)
        if state.opacity <= 0 { return }
        let world = parent * state.transform
        let isolated = state.opacity < 1
        let surface = isolated ? try acquire(frame,width:target.color.width,height:target.color.height) : target
        func drawRole(_ role:String) throws {
            for item in node.draws where item.source.role == role {
                var paint = item.source.paint
                if let color = state.colors["\(role):\(item.source.paintIndex)"] { paint.color = color; paint.opacity = 1 }
                try draw(item.mesh,paint:paint,size:item.source.size,world:world*item.source.transform,
                         into:surface,command:command,stats:&stats)
            }
        }
        try drawRole("fills")
        if let clip = node.clip, !node.children.isEmpty {
            let children = try acquire(frame,width:target.color.width,height:target.color.height)
            for child in node.children { try renderNode(child,parent:world,time:time,target:children,frame:frame,command:command,stats:&stats) }
            let mask = try acquire(frame,width:target.color.width,height:target.color.height)
            try draw(clip,paint:Paint(),size:node.source.size,world:world,into:mask,command:command,stats:&stats)
            try composite(children,mask:mask,into:surface,command:command,stats:&stats)
            children.inUse = false; mask.inUse = false
        } else {
            for child in node.children { try renderNode(child,parent:world,time:time,target:surface,frame:frame,command:command,stats:&stats) }
        }
        // Frame strokes remain above children and are not clipped away by clipsContent.
        try drawRole("strokes")
        if isolated { try composite(surface,alpha:state.opacity,into:target,command:command,stats:&stats); surface.inUse = false }
    }

    /// Aspect-fit rendering into a BGRA8 target. Explicit time makes seeking and tests deterministic.
    /// `present` is used by MTKView; omit for offscreen testing. Wait mode reports GPU failures.
    @discardableResult
    public func render(to texture: MTLTexture, time: Double, present: MTLDrawable? = nil,
                       waitUntilCompleted: Bool = false) throws -> MTLCommandBuffer {
        guard texture.pixelFormat == .bgra8Unorm, texture.sampleCount == 1,
              texture.width > 0, texture.height > 0, texture.width*texture.height <= 8_388_608 else {
            throw SceneError.invalid("Expected a BGRA8 single-sample target up to 8 megapixels")
        }
        semaphore.wait()
        let frame = slots[nextSlot]; nextSlot = (nextSlot+1)%slots.count
        var submitted = false
        defer { if !submitted { semaphore.signal() } }
        if frame.rootMSAA?.width != texture.width || frame.rootMSAA?.height != texture.height {
            frame.rootMSAA = try makeMSAA(width:texture.width,height:texture.height)
            frame.surfaces.removeAll()
        }
        for surface in frame.surfaces { surface.inUse = false }
        let surface = Surface(color:texture,multisample:frame.rootMSAA)
        guard let command = queue.makeCommandBuffer() else { throw SceneError.gpu("Command buffer creation failed") }
        command.label = "FigmaMetal frame \(time)"
        var stats = RenderStatistics(); stats.vertices = vertexCount
        let scale = min(Double(texture.width)/scene.width,Double(texture.height)/scene.height)
        let base = Affine.translation((Double(texture.width)-scene.width*scale)/2,(Double(texture.height)-scene.height*scale)/2) * .scale(scale,scale)
        // Always clear even for an empty or fully transparent scene.
        let clear = try encoder(surface,command); clear.endEncoding()
        try renderNode(root,parent:base,time:scene.localTime(time),target:surface,frame:frame,command:command,stats:&stats)
        stats.surfaceCount = frame.surfaces.count+1
        if let present { command.present(present) }
        let signal = semaphore
        command.addCompletedHandler { _ in signal.signal() }
        submitted = true; command.commit()
        if waitUntilCompleted {
            command.waitUntilCompleted()
            if let error = command.error { throw SceneError.gpu(error.localizedDescription) }
            stats.gpuMilliseconds = (command.gpuEndTime-command.gpuStartTime)*1000
        }
        lastStatistics = stats
        return command
    }

    /// Copies actual GPU-rendered BGRA pixels, including alpha. No screenshot reconstruction.
    public func pixels(width:Int,height:Int,time:Double) throws -> Data {
        let texture = try makeTarget(width:width,height:height)
        try render(to:texture,time:time,waitUntilCompleted:true)
        let row = ((width*4+255)/256)*256
        guard let buffer = device.makeBuffer(length:row*height,options:.storageModeShared),
              let command = queue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else {
            throw SceneError.gpu("Readback allocation failed")
        }
        blit.copy(from:texture,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),
                  sourceSize:MTLSize(width:width,height:height,depth:1),to:buffer,destinationOffset:0,
                  destinationBytesPerRow:row,destinationBytesPerImage:row*height)
        blit.endEncoding(); command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw SceneError.gpu(error.localizedDescription) }
        var data = Data(capacity:width*height*4)
        for y in 0..<height { data.append(buffer.contents().advanced(by:y*row).assumingMemoryBound(to:UInt8.self),count:width*4) }
        return data
    }
}
#endif
