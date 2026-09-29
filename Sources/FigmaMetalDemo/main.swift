import Foundation
import FigmaMetal
#if os(macOS)
import AppKit
import SwiftUI
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
struct DemoView: View {
    let renderer: MetalRenderer
    @State private var playing = true
    @State private var position = 0.0
    @State private var failure = ""
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                VStack(alignment:.leading,spacing:4) {
                    Text("FigmaMetal").font(.system(size:26,weight:.semibold))
                    Text("Source geometry → native Metal. No animation middleware.").foregroundStyle(.secondary)
                }
                Spacer()
                Text("v0.1 • experimental").font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary)
            }
            FigmaMetalView(renderer:renderer,time:playing ? nil : position,isPlaying:playing,onError:{ failure = String(describing:$0) })
                .aspectRatio(renderer.scene.width/renderer.scene.height,contentMode:.fit)
                .accessibilityLabel("Animated vector renderer test scene")
            HStack {
                Button(playing ? "Pause / scrub" : "Play") { playing.toggle() }
                Slider(value:$position,in:0...max(renderer.scene.duration,0.001),onEditingChanged:{ editing in if editing {playing = false} })
                Text(String(format:"%.2f s",position)).monospacedDigit().frame(width:65)
            }
            Text("\(renderer.vertexCount) prepared vertices • \(renderer.sampleCount)× MSAA • \(renderer.device.name)")
                .font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary)
            if !failure.isEmpty { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
        }.padding(24).frame(minWidth:680,minHeight:540)
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    let renderer: MetalRenderer
    init(_ renderer:MetalRenderer) { self.renderer = renderer }
    func applicationDidFinishLaunching(_ notification:Notification) {
        let menu = NSMenu(); let app = NSMenuItem(); menu.addItem(app)
        let submenu = NSMenu(); submenu.addItem(withTitle:"Quit FigmaMetal",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        app.submenu = submenu; NSApp.mainMenu = menu
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:700),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        window.title = "FigmaMetal — Native Metal Preview"
        window.contentView = NSHostingView(rootView:DemoView(renderer:renderer))
        window.center(); window.makeKeyAndOrderFront(nil); self.window = window
        NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { true }
}
#endif

func run() throws {
    let args = try Arguments()
    if ["help","--help","-h"].contains(args.verb) {
        print("""
        FigmaMetal v0.1
          figma-metal demo [scene.figmetal.json]
          figma-metal validate scene.figmetal.json [--allow-partial]
          figma-metal render [scene.figmetal.json] --output frame.png [--time 0] [--width 720] [--height 480]
          figma-metal bench [scene.figmetal.json] [--frames 120] [--width 720] [--height 480]
        Add --scene N to select a scene. Input defaults to the bundled synthetic demo.
        """); return
    }
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
    case "demo":
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let delegate = AppDelegate(renderer); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    default: throw SceneError.invalid("Unknown command \(args.verb); run figma-metal help")
    }
    #else
    throw SceneError.unsupported("Rendering requires macOS with Metal. Core validation works on this platform.")
    #endif
}
do { try run() } catch { fputs("\(error)\n",stderr); exit(1) }
