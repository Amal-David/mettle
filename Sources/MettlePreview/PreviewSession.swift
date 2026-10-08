#if os(macOS)
import AppKit
import Combine
import Mettle
import UniformTypeIdentifiers
import ImageIO

public struct PreviewExample: Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let url: URL
    public init(id: String, title: String, detail: String, symbol: String, url: URL) {
        self.id = id; self.title = title; self.detail = detail; self.symbol = symbol; self.url = url
    }
}
public struct PreviewIssue: Identifiable {
    public let id = UUID()
    public var title: String
    public var message: String
}

/// All published state and all renderer use are confined to the main thread.
/// Parsing and first-time shader preparation run on a serial worker. A generation
/// token discards obsolete results without replacing a more recently opened file.
public final class PreviewSession: ObservableObject {
    @Published public private(set) var document: SceneDocument?
    @Published public private(set) var renderer: MetalRenderer?
    @Published public private(set) var sourceURL: URL?
    @Published public private(set) var exampleID: String?
    @Published public private(set) var selectedScene = 0
    @Published public private(set) var playback = PlaybackClock()
    @Published public private(set) var isLoading = false
    @Published public private(set) var loadingName = ""
    @Published public var issue: PreviewIssue?
    @Published public var inspectorVisible = false
    @Published public var helpVisible = false
    @Published public var referencesVisible = false
    @Published public var appearance = "Light"
    @Published public var background = "Checkerboard"
    @Published public var zoom = "Fit"
    @Published public var reduceMotion = false
    @Published public private(set) var status = ""
    public let examples: [PreviewExample]
    private let worker = DispatchQueue(label: "dev.mettle.preview.load", qos: .userInitiated)
    private var request = UUID()
    private var timer: Timer?
    private var inheritedRepetition = PlaybackClock.Repetition.once
    public var scene: Scene? {
        guard let document, document.scenes.indices.contains(selectedScene) else { return nil }
        return document.scenes[selectedScene]
    }
    public var title: String {
        if let sample = examples.first(where: { $0.id == exampleID }) { return sample.title }
        return sourceURL?.deletingPathExtension().deletingPathExtension().lastPathComponent ?? "Welcome"
    }
    public var sourceDescription: String {
        if let sample = examples.first(where: { $0.id == exampleID }) { return sample.detail }
        return sourceURL?.lastPathComponent ?? "Open a Mettle export to get started."
    }
    public var hasMotion: Bool {
        func containsTracks(_ n: Node) -> Bool { !n.bindings.isEmpty || n.children.contains(where: containsTracks) }
        return scene.map { $0.duration > 0 && containsTracks($0.root) } ?? false
    }
    public var duration: Double { playback.duration }
    public var repeatEnabled: Bool { playback.repetition != .once }
    public init(examples: [PreviewExample]) { self.examples = examples }
    deinit { timer?.invalidate() }

    /// Kept synchronous for deterministic model/GPU integration tests. UI opens use
    /// `open`, below, so expensive tessellation cannot freeze the file picker.
    public func loadSynchronously(url: URL, sceneIndex: Int = 0, exampleID: String? = nil,
                                  initialTime: Double = 0) throws {
        request = UUID(); isLoading = false
        let prepared = try Self.prepare(url: url, sceneIndex: sceneIndex)
        install(prepared.0, renderer: prepared.1, url: url, sceneIndex: sceneIndex,
                exampleID: exampleID, initialTime: initialTime)
    }
    private static func prepare(url: URL, sceneIndex: Int) throws -> (SceneDocument, MetalRenderer) {
        guard url.isFileURL else { throw SceneError.invalid("Only local exported files are supported.") }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let document = try SceneDocument.load(url: url) // Never silently allow partial assets.
        guard document.scenes.indices.contains(sceneIndex) else { throw SceneError.invalid("Scene index is out of range.") }
        var displayScene = document.scenes[sceneIndex]
        // The transport owns repeat/ping-pong. The renderer must show the exact
        // endpoint when scrubbing, even if the source scene loops.
        displayScene.loop = "once"
        return (document, try MetalRenderer(scene: displayScene))
    }
    private func install(_ document: SceneDocument, renderer: MetalRenderer, url: URL,
                         sceneIndex: Int, exampleID: String?, initialTime: Double) {
        stopTimer()
        self.document = document; self.renderer = renderer; self.sourceURL = url
        self.selectedScene = sceneIndex; self.exampleID = exampleID
        inheritedRepetition = PlaybackClock.Repetition(rawValue: document.scenes[sceneIndex].loop) ?? .once
        playback = PlaybackClock(duration: document.scenes[sceneIndex].duration, repetition: inheritedRepetition)
        playback.seek(to: initialTime)
        status = ""; issue = nil; zoom = "Fit"; referencesVisible = false
    }
    public func open(_ url: URL, sceneIndex: Int = 0, exampleID: String? = nil, initialTime: Double = 0) {
        pause(); let token = UUID(); request = token
        isLoading = true; loadingName = url.lastPathComponent
        worker.async { [weak self] in
            let result = Result { try Self.prepare(url: url, sceneIndex: sceneIndex) }
            DispatchQueue.main.async {
                guard let self, self.request == token else { return }
                self.isLoading = false
                switch result {
                case .success(let value):
                    self.install(value.0, renderer: value.1, url: url, sceneIndex: sceneIndex,
                                 exampleID: exampleID, initialTime: initialTime)
                case .failure(let error): self.showOpenError(error)
                }
            }
        }
    }
    public func openExample(_ example: PreviewExample) { open(example.url, exampleID: example.id) }
    public func reload() {
        guard let url = sourceURL, !isLoading else { return }
        open(url, sceneIndex: selectedScene, exampleID: exampleID, initialTime: playback.position)
    }
    public func chooseScene(_ index: Int) {
        guard let url = sourceURL, index != selectedScene else { return }
        open(url, sceneIndex: index, exampleID: exampleID)
    }
    public func close() {
        request = UUID(); isLoading = false; pause()
        document = nil; renderer = nil; sourceURL = nil; exampleID = nil
        selectedScene = 0; playback = PlaybackClock(); status = ""; issue = nil; referencesVisible = false
    }
    public func showOpenError(_ error: Error) {
        issue = PreviewIssue(title: "Couldn’t open this animation",
            message: "Choose a .figmetal.json file exported with the Mettle Figma plugin. Raw .fig, SVG and Lottie files can’t be opened here. Your current preview has not been replaced.\n\n\(error.localizedDescription)")
    }
    public func openPanel() {
        pause()
        let panel = NSOpenPanel()
        panel.title = "Open a Mettle animation"
        panel.message = "Choose a .figmetal.json export from the Mettle Figma plugin."
        panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false; panel.prompt = "Open animation"
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { [weak self] response in
                if response == .OK, let url = panel.url { self?.open(url) }
            }
        } else if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
    public func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard providers.count == 1, let item = providers.first,
              item.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            issue = PreviewIssue(title: "Drop one animation", message: "Drop a single .figmetal.json file into this window.")
            return false
        }
        item.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] value, error in
            let url: URL?
            if let value = value as? URL { url = value }
            else if let data = value as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            else { url = nil }
            DispatchQueue.main.async {
                if let url { self?.open(url) }
                else { self?.showOpenError(error ?? SceneError.invalid("The drop did not contain a readable file URL.")) }
            }
        }
        return true
    }
    public func togglePlayback() {
        guard renderer != nil, hasMotion, !reduceMotion, !isLoading else { return }
        if playback.isPlaying { pause(); return }
        playback.play(at: ProcessInfo.processInfo.systemUptime)
        let timer = Timer(timeInterval: 1.0/60.0, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func tick() {
        playback.advance(to: ProcessInfo.processInfo.systemUptime)
        if !playback.isPlaying { stopTimer() }
    }
    public func pause() { playback.pause(at: ProcessInfo.processInfo.systemUptime); stopTimer() }
    private func stopTimer() { timer?.invalidate(); timer = nil }
    public func seek(_ time: Double) { stopTimer(); playback.seek(to: time) }
    public func step(_ delta: Double) { seek(playback.position + delta) }
    public func setSpeed(_ speed: Double) { playback.setSpeed(speed, at: ProcessInfo.processInfo.systemUptime) }
    public func toggleRepeat() {
        playback.repetition = repeatEnabled ? .once : (inheritedRepetition == .pingPong ? .pingPong : .loop)
    }
    public func renderFailed(_ error: Error) {
        pause(); issue = PreviewIssue(title: "The preview couldn’t render", message: error.localizedDescription)
    }
    public func exportPanel() {
        guard let renderer else { return }
        pause()
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.canCreateDirectories = true
        panel.title = "Export the current frame"
        panel.message = "Original canvas size. Transparency is preserved; the preview background is not included."
        panel.nameFieldStringValue = "\(title)-\(String(format: "%.2f", playback.position))s.png"
        let time = playback.position
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Self.exportFrame(renderer: renderer, time: time, url: url)
                self?.status = "Saved \(url.lastPathComponent)"
            } catch { self?.issue = PreviewIssue(title: "Couldn’t save this frame", message: error.localizedDescription) }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { completion(panel.runModal()) }
    }
    public static func exportFrame(renderer: MetalRenderer, time: Double, url: URL) throws {
        let w = max(1, Int(renderer.scene.width.rounded())), h = max(1, Int(renderer.scene.height.rounded()))
        let bytes = try renderer.pixels(width: w, height: h, time: time)
        guard let provider = CGDataProvider(data: bytes as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w*4,
                  space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw SceneError.invalid("Unable to create the PNG file.")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw SceneError.invalid("Unable to finish writing the PNG file.") }
    }
}
#endif
