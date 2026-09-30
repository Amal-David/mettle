import Foundation
import Mettle
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
struct DemoView: View {
    let renderer: MetalRenderer
    @State private var playing: Bool
    @State private var position: Double
    @State private var lastTick = ProcessInfo.processInfo.systemUptime
    @State private var failure = ""
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let clock = Timer.publish(every: 1.0/60.0, on: .main, in: .common).autoconnect()

    init(renderer: MetalRenderer, initialTime: Double? = nil) {
        self.renderer = renderer
        _playing = State(initialValue: initialTime == nil)
        _position = State(initialValue: max(0, initialTime ?? 0))
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased()).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .medium)).textSelection(.enabled)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Text("M").font(.system(size: 27, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.45, green: 0.94, blue: 0.83))
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mettle").font(.system(size: 28, weight: .semibold))
                    Text("Design in Figma. Move in Metal.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("EXPERIMENTAL  /  v0.2").font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(red: 0.99, green: 0.77, blue: 0.40))
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(.white.opacity(0.055), in: Capsule())
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 16) {
                    MettleView(renderer: renderer, time: position, isPlaying: false,
                        onError: { failure = String(describing: $0) })
                        .aspectRatio(renderer.scene.width/renderer.scene.height, contentMode: .fit)
                        .accessibilityLabel("Native Metal animation preview")
                        .padding(14).background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08)))
                    HStack(spacing: 14) {
                        Button { playing.toggle(); lastTick = ProcessInfo.processInfo.systemUptime } label: {
                            Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 18, height: 18)
                        }.buttonStyle(.bordered).help(playing ? "Pause playback" : "Play animation")
                        Slider(value: $position, in: 0...max(renderer.scene.duration, 0.001),
                            onEditingChanged: { editing in if editing { playing = false } })
                            .tint(Color(red: 0.45, green: 0.94, blue: 0.83))
                            .accessibilityLabel("Animation time")
                        Text(String(format: "%.2f / %.2f s", position, renderer.scene.duration))
                            .font(.system(size: 11, design: .monospaced)).monospacedDigit().frame(width: 118)
                    }.padding(.horizontal, 4)
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 22) {
                    Text("NATIVE PREVIEW").font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.45, green: 0.94, blue: 0.83))
                    metric("Scene", renderer.scene.name)
                    metric("Source canvas", "\(Int(renderer.scene.width)) × \(Int(renderer.scene.height))")
                    metric("Prepared geometry", "\(renderer.vertexCount) vertices")
                    metric("Antialiasing", "\(renderer.sampleCount)× MSAA")
                    metric("Device", renderer.device.name)
                    Divider()
                    Text("Source paths. Native shaders.").font(.system(size: 12, weight: .medium))
                    Text("No Lottie, browser, or image-sequence playback. Unsupported features are reported at export.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(width: 190).padding(.top, 12)
            }
            HStack {
                Circle().fill(Color(red: 0.45, green: 0.94, blue: 0.83)).frame(width: 5, height: 5)
                Text("Swift + Metal").font(.system(size: 11, design: .monospaced))
                Spacer()
                Text("Engineering prototype · not a universal Figma player")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !failure.isEmpty { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
        }
        .padding(28).frame(minWidth: 940, minHeight: 680)
        .background(Color(red: 0.055, green: 0.065, blue: 0.085))
        .preferredColorScheme(.dark)
        .onReceive(clock) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            defer { lastTick = now }
            guard playing, scenePhase == .active, !reduceMotion else { return }
            position += max(0, now-lastTick)
            if position > renderer.scene.duration {
                position = 0 // Preview restart; core playback preserves the scene's own loop semantics.
            }
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    let renderer: MetalRenderer
    let initialTime: Double?
    init(_ renderer:MetalRenderer, initialTime: Double? = nil) { self.renderer = renderer; self.initialTime = initialTime }
    func applicationDidFinishLaunching(_ notification:Notification) {
        let menu = NSMenu(); let app = NSMenuItem(); menu.addItem(app)
        let submenu = NSMenu(); submenu.addItem(withTitle:"Quit Mettle",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        app.submenu = submenu; NSApp.mainMenu = menu
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1080,height:760),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        window.title = "Mettle — Experimental Native Preview"
        window.contentView = NSHostingView(rootView:DemoView(renderer:renderer, initialTime:initialTime))
        window.center(); window.makeKeyAndOrderFront(nil); self.window = window
        NSApp.activate(ignoringOtherApps:true)
        print("METTLE_WINDOW_ID=\(window.windowNumber)"); fflush(stdout)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { true }
}
#endif

func run() throws {
    let args = try Arguments()
    if ["help","--help","-h"].contains(args.verb) {
        print("""
        Mettle v0.2
          mettle demo [scene.figmetal.json] [--time 1]
          mettle validate scene.figmetal.json [--allow-partial]
          mettle render [scene.figmetal.json] --output frame.png [--time 0] [--width 720] [--height 480]
          mettle frames scene.figmetal.json --output frames [--fps 30] [--frames 60]
          mettle bench [scene.figmetal.json] [--frames 120] [--width 720] [--height 480]
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
    case "demo":
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let delegate = AppDelegate(renderer, initialTime: args.options["--time"] == nil ? nil : try args.double("--time",0)); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    default: throw SceneError.invalid("Unknown command \(args.verb); run mettle help")
    }
    #else
    throw SceneError.unsupported("Rendering requires macOS with Metal. Core validation works on this platform.")
    #endif
}
do { try run() } catch { fputs("\(error)\n",stderr); exit(1) }
