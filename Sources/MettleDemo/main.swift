import Foundation
import Mettle
import MettlePreview
#if os(macOS)
import AppKit
import SwiftUI
import Combine
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
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
            if options[token] != nil { throw SceneError.invalid("Duplicate option \(token)") }
            if token == "--allow-partial" { options[token] = "true" }
            else if token.hasPrefix("--") {
                guard !tokens.isEmpty, !tokens[0].hasPrefix("--") else { throw SceneError.invalid("Missing value for \(token)") }
                options[token] = tokens.removeFirst()
            } else if input == nil { input = token }
            else { throw SceneError.invalid("Unexpected argument \(token)") }
        }
        self.input = input; self.options = options
        let shared: Set<String> = ["--scene", "--allow-partial"]
        let allowed: [String: Set<String>] = [
            "validate": shared,
            "preview": ["--scene", "--example", "--time", "--raster-scale"], "demo": ["--scene", "--example", "--time", "--raster-scale"],
            "render": shared.union(["--output", "--time", "--width", "--height", "--loop", "--raster-scale"]),
            "frames": shared.union(["--output", "--time", "--width", "--height", "--loop", "--times", "--fps", "--frames", "--raster-scale"]),
            "bench": shared.union(["--frames", "--width", "--height", "--loop", "--raster-scale"]),
            "help": [], "--help": [], "-h": []
        ]
        guard let valid = allowed[verb] else { throw SceneError.invalid("Unknown command \(verb); run mettle help") }
        if let unknown = options.keys.sorted().first(where: { !valid.contains($0) }) {
            throw SceneError.invalid("Unknown option \(unknown) for \(verb)")
        }
        if options["--times"] != nil, ["--fps", "--frames", "--time"].contains(where: { options[$0] != nil }) {
            throw SceneError.invalid("Use either --times or --fps/--frames/--time, not both")
        }
        if ["validate", "frames"].contains(verb), input == nil {
            throw SceneError.invalid("\(verb) requires an explicit .figmetal.json input file")
        }
        if let scale = options["--raster-scale"], !["1", "2"].contains(scale) {
            throw SceneError.invalid("Raster scale must be 1 or 2")
        }
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
          mettle preview [scene.figmetal.json] [--example motion|vectors] [--time 1] [--raster-scale 1|2]
          mettle demo (alias for preview)
          mettle validate scene.figmetal.json [--allow-partial]
          mettle render [scene.figmetal.json] --output frame.png [--time 0] [--width 720] [--height 480]
          mettle frames scene.figmetal.json --output frames [--fps 30] [--frames 60]
          mettle frames scene.figmetal.json --output frames --times 0,0.125,0.2 --loop once
          mettle bench [scene.figmetal.json] [--frames 120] [--width 720] [--height 480]
        Preview opens a welcome screen. Use --example motion or --example vectors to load an example.
        Add --scene N to select a scene. Render/bench default to the synthetic test scene.
        --times preserves exact source timestamps. --loop once preserves the final endpoint for comparison.
        Preview/render/frames/bench accept --raster-scale 2 for higher coverage with a Metal resolve; default is 1.
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
            initialTime: try args.double("--time", 0), initialScene: try args.int("--scene", 0),
            initialRasterScale: try args.int("--raster-scale", 1))
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
    let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard fileSize <= 32*1024*1024 else { throw SceneError.invalid("File exceeds 32 MiB") }
    let sourceData = try Data(contentsOf: url)
    let document = try SceneDocument.decode(sourceData,allowPartial:args.options["--allow-partial"] == "true")
    let index = try args.int("--scene",0)
    guard document.scenes.indices.contains(index) else { throw SceneError.invalid("Scene index out of range") }
    var scene = document.scenes[index]
    if let loop = args.options["--loop"] {
        guard ["once", "loop", "pingPong"].contains(loop) else { throw SceneError.invalid("Loop must be once, loop, or pingPong") }
        scene.loop = loop
    }
    for issue in document.diagnostics { fputs("[\(issue.severity)] \(issue.code) \(issue.nodeID): \(issue.message)\n", stderr) }
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
    let renderer = try MetalRenderer(scene:scene, rasterScale:try args.int("--raster-scale",1))
    let width = try args.int("--width",max(1,Int(scene.width.rounded()))), height = try args.int("--height",max(1,Int(scene.height.rounded())))
    switch args.verb {
    case "render":
        let time = try args.double("--time",0)
        guard (0...86400).contains(time) else { throw SceneError.invalid("Render time must be within 0...86400 seconds") }
        let data = try renderer.pixels(width:width,height:height,time:time)
        let output = URL(fileURLWithPath:args.options["--output"] ?? "frame.png")
        try writePNG(data,width:width,height:height,url:output)
        print("Rendered \(output.path) on \(renderer.device.name); \(renderer.lastStatistics.drawCalls) draw calls; GPU \(renderer.lastStatistics.gpuMilliseconds) ms")
    case "frames":
        let fps = try args.double("--fps",30), start = try args.double("--time",0)
        let times: [Double]
        if let csv = args.options["--times"] { times = try FrameSampling.explicit(csv) }
        else { times = try FrameSampling.regular(fps: fps, start: start, duration: scene.duration,
            count: args.options["--frames"] == nil ? nil : try args.int("--frames", 1)) }
        let directory = URL(fileURLWithPath:args.options["--output"] ?? "frames",isDirectory:true)
        if FileManager.default.fileExists(atPath: directory.path),
           !(try FileManager.default.contentsOfDirectory(atPath: directory.path)).isEmpty {
            throw SceneError.invalid("Frame output directory must be empty. Choose a fresh directory so old and new evidence cannot be mixed.")
        }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        var entries: [[String:Any]] = []
        for (frameIndex, time) in times.enumerated() {
            let filename = String(format:"%04d.png",frameIndex)
            let pixels = try renderer.pixels(width:width,height:height,time:time)
            let frameURL = directory.appendingPathComponent(filename)
            try writePNG(pixels,width:width,height:height,url:frameURL)
            let digest = SHA256.hash(data: try Data(contentsOf: frameURL)).map { String(format:"%02x", $0) }.joined()
            entries.append(["index":frameIndex,"time":time,"file":filename,"sha256":digest])
        }
        var manifest: [String:Any] = ["format":"mettle-frames","version":1,"backend":"Metal",
            "sourceSHA256":SHA256.hash(data: sourceData).map { String(format:"%02x", $0) }.joined(),
            "sceneIndex":index,"sceneDuration":scene.duration,"loop":scene.loop,
            "width":width,"height":height,"frames":entries,
            "device":renderer.device.name,"curveTolerance":0.05,"sampleCount":renderer.sampleCount,
            "rasterScale":renderer.rasterScale,"rasterWidth":width*renderer.rasterScale,"rasterHeight":height*renderer.rasterScale,
            "note":"Native Metal sequence evaluated at the exact listed timestamps. No reference images are loaded by the renderer."]
        if args.options["--times"] == nil { manifest["fps"] = fps }
        try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys])
            .write(to:directory.appendingPathComponent("manifest.json"),options:.atomic)
        print("Rendered \(times.count) native frames at exact timestamps into \(directory.path)")
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
            "sampleCount":renderer.sampleCount,"rasterScale":renderer.rasterScale,"vertices":renderer.vertexCount,"drawCalls":renderer.lastStatistics.drawCalls,
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
