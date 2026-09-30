import Foundation
import Mettle
import MettlePreview
#if os(macOS)
import AppKit
import SwiftUI
import Combine
import ImageIO
import UniformTypeIdentifiers
#endif

struct Arguments {
    let verb: String
    let input: String?
    let options: [String:String]
    init() throws {
        var tokens = Array(CommandLine.arguments.dropFirst())
        self.verb = tokens.isEmpty ? "demo" : tokens.removeFirst()
        var input: String?, options: [String:String] = [:]
        while !tokens.isEmpty {
            let token = tokens.removeFirst()
            if token == "--allow-partial" { options[token] = "true" }
            else if token.hasPrefix("--") {
                guard !tokens.isEmpty else { throw SceneError.invalid("Missing value for \(token)") }
                options[token] = tokens.removeFirst()
            } else if input == nil { input = token }
            else { throw SceneError.invalid("Unexpected argument \(token)") }
        }
        self.input = input; self.options = options
    }
    func int(_ key:String,_ fallback:Int) throws -> Int {
        guard let text = options[key] else { return fallback }
        guard let v = Int(text) else { throw SceneError.invalid("\(key) must be an integer") }; return v
    }
    func double(_ key:String,_ fallback:Double) throws -> Double {
        guard let text = options[key] else { return fallback }
        guard let v = Double(text),v.isFinite else { throw SceneError.invalid("\(key) must be finite") }; return v
    }
}

#if os(macOS)
func writePNG(_ bgra:Data,width:Int,height:Int,url:URL) throws {
    guard let provider = CGDataProvider(data:bgra as CFData),
          let space = CGColorSpace(name:CGColorSpace.sRGB),
          let image = CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,
                              space:space,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
                              provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else {
        throw SceneError.invalid("Unable to encode GPU pixels as PNG")
    }
    try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else {
        throw SceneError.invalid("Cannot create PNG at \(url.path)")
    }
    CGImageDestinationAddImage(destination,image,nil)
    guard CGImageDestinationFinalize(destination) else { throw SceneError.invalid("PNG write failed") }
}

#endif

func run() throws {
    let args = try Arguments()
    if ["help","--help","-h"].contains(args.verb) {
        print("""
        Mettle v0.3
          mettle preview [scene.figmetal.json] [--example motion|vectors] [--time 1]
          mettle demo (alias for preview)
          mettle validate scene.figmetal.json [--allow-partial]
          mettle render [scene.figmetal.json] --output frame.png [--time 0] [--width 720] [--height 480]
          mettle frames scene.figmetal.json --output frames [--fps 30] [--frames 60]
          mettle bench [scene.figmetal.json] [--frames 120] [--width 720] [--height 480]
        Preview opens a welcome screen. Use --example motion or --example vectors to load an example.
        Add --scene N to select a scene. Render/bench default to the synthetic test scene.
        """); return
    }
    #if os(macOS)
    if ["demo", "preview"].contains(args.verb) {
        guard let vectors = Bundle.module.url(forResource: "demo.figmetal", withExtension: "json", subdirectory: "Resources"),
              let motion = Bundle.module.url(forResource: "motion.figmetal", withExtension: "json", subdirectory: "Resources") else {
            throw SceneError.invalid("Bundled preview examples are missing")
        }
        let examples = [
            PreviewExample(id: "motion", title: "Motion sample", detail: "Example · exported from Figma", symbol: "play.rectangle", url: motion),
            PreviewExample(id: "vectors", title: "Vector sample", detail: "Example · synthetic test artwork", symbol: "square.on.circle", url: vectors)
        ]
        var exampleID = args.options["--example"]
        // Preserve deterministic legacy screenshot commands without making test
        // artwork the normal opening screen.
        if exampleID == nil && args.input == nil && args.options["--time"] != nil { exampleID = "vectors" }
        if let exampleID, !examples.contains(where: { $0.id == exampleID }) { throw SceneError.invalid("Example must be motion or vectors") }
        let initialURL = args.input.map { URL(fileURLWithPath: $0) } ?? examples.first(where: { $0.id == exampleID })?.url
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let delegate = PreviewApplication(examples: examples, initialURL: initialURL,
            initialExampleID: args.input == nil ? exampleID : nil,
            initialTime: try args.double("--time", 0), initialScene: try args.int("--scene", 0))
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        return
    }
    #endif
    let url: URL
    if let input = args.input { url = URL(fileURLWithPath:input) }
    else {
        guard let bundled = Bundle.module.url(forResource:"demo.figmetal",withExtension:"json",subdirectory:"Resources") else {
            throw SceneError.invalid("Bundled demo is missing")
        }; url = bundled
    }
    let document = try SceneDocument.load(url:url,allowPartial:args.options["--allow-partial"] == "true")
    let index = try args.int("--scene",0)
    guard document.scenes.indices.contains(index) else { throw SceneError.invalid("Scene index out of range") }
    let scene = document.scenes[index]
    for issue in document.diagnostics { print("[\(issue.severity)] \(issue.code) \(issue.nodeID): \(issue.message)") }
    if args.verb == "validate" {
        var nodes = 0, bindings = 0, vertices = 0
        func check(_ node:Node) throws {
            nodes += 1; bindings += node.bindings.count
            for d in node.draws { vertices += try Tessellator().tessellate(paths:d.paths).count }
            vertices += try Tessellator().tessellate(paths:node.clip).count
            for child in node.children { try check(child) }
        }
        try check(scene.root)
        print("VALID: \(scene.name), \(nodes) nodes, \(bindings) bindings, \(vertices) prepared vertices, \(scene.duration)s")
        return
    }
    #if os(macOS)
    let renderer = try MetalRenderer(scene:scene)
    let width = try args.int("--width",Int(scene.width)), height = try args.int("--height",Int(scene.height))
    switch args.verb {
    case "render":
        let time = try args.double("--time",0)
        let data = try renderer.pixels(width:width,height:height,time:time)
        let output = URL(fileURLWithPath:args.options["--output"] ?? "frame.png")
        try writePNG(data,width:width,height:height,url:output)
        print("Rendered \(output.path) on \(renderer.device.name); \(renderer.lastStatistics.drawCalls) draw calls; GPU \(renderer.lastStatistics.gpuMilliseconds) ms")
    case "frames":
        let fps = try args.double("--fps",30), start = try args.double("--time",0)
        guard fps >= 1 && fps <= 120, start >= 0 else { throw SceneError.invalid("FPS must be 1...120 and start time nonnegative") }
        let count = try args.int("--frames",max(1,Int(ceil(max(0,scene.duration-start)*fps))))
        guard count >= 1 && count <= 3600 else { throw SceneError.invalid("Sequence must contain 1...3600 frames") }
        let directory = URL(fileURLWithPath:args.options["--output"] ?? "frames",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        var entries: [[String:Any]] = []
        for index in 0..<count {
            let time = start+Double(index)/fps
            let filename = String(format:"%04d.png",index)
            let pixels = try renderer.pixels(width:width,height:height,time:time)
            try writePNG(pixels,width:width,height:height,url:directory.appendingPathComponent(filename))
            entries.append(["index":index,"time":time,"file":filename])
        }
        let manifest: [String:Any] = ["fps":fps,"width":width,"height":height,"frames":entries,
            "device":renderer.device.name,"curveTolerance":0.05,"sampleCount":renderer.sampleCount,
            "note":"Native Metal sequence, evaluated at index/fps. No reference images are loaded by the renderer."]
        try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys])
            .write(to:directory.appendingPathComponent("manifest.json"),options:.atomic)
        print("Rendered \(count) native frames at \(fps) fps into \(directory.path)")
    case "bench":
        let count = try args.int("--frames",120)
        guard count >= 1 && count <= 10000 else { throw SceneError.invalid("Frames must be 1...10000") }
        let target = try renderer.makeTarget(width:width,height:height)
        for i in 0..<5 { try renderer.render(to:target,time:Double(i)/60,waitUntilCompleted:true) }
        var gpu: [Double] = [], wall: [Double] = []
        for i in 0..<count {
            let start = Date()
            try renderer.render(to:target,time:Double(i)/60,waitUntilCompleted:true)
            wall.append(Date().timeIntervalSince(start)*1000); gpu.append(renderer.lastStatistics.gpuMilliseconds)
        }
        gpu.sort(); wall.sort()
        func percentile(_ a:[Double],_ p:Double)->Double { a[min(a.count-1,Int(Double(a.count-1)*p))] }
        let result:[String:Any] = ["device":renderer.device.name,"width":width,"height":height,"frames":count,
            "sampleCount":renderer.sampleCount,"vertices":renderer.vertexCount,"drawCalls":renderer.lastStatistics.drawCalls,
            "surfaces":renderer.lastStatistics.surfaceCount,"gpuMedianMs":percentile(gpu,0.5),"gpuP95Ms":percentile(gpu,0.95),
            "wallMedianMs":percentile(wall,0.5),"wallP95Ms":percentile(wall,0.95),"note":"Synchronous offscreen benchmark; not an on-device iOS FPS measurement." ]
        print(String(data:try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
    default: throw SceneError.invalid("Unknown command \(args.verb); run mettle help")
    }
    #else
    throw SceneError.unsupported("Rendering requires macOS with Metal. Core validation works on this platform.")
    #endif
}
do { try run() } catch { fputs("\(error)\n",stderr); exit(1) }
