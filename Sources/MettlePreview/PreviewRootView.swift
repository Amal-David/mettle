#if os(macOS)
import AppKit
import SwiftUI
import Mettle
import UniformTypeIdentifiers

/// A document preview utility, deliberately separate from the embeddable renderer.
public struct PreviewRootView: View {
    @ObservedObject var session: PreviewSession
    @State private var isDropTarget = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(session: PreviewSession) { self.session = session }
    public var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 204)
            Divider()
            VStack(spacing: 0) {
                toolbar
                Divider()
                if session.referencesVisible { references }
                else if session.renderer != nil { workspace }
                else { welcome }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Color(red: 0.37, green: 0.32, blue: 0.91))
        .accentColor(Color(red: 0.37, green: 0.32, blue: 0.91))
        .preferredColorScheme(session.appearance == "System" ? nil : (session.appearance == "Light" ? .light : .dark))
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(8).background(Color.accentColor.opacity(0.05)).allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTarget, perform: session.acceptDrop)
        .alert(item: $session.issue) { issue in
            Alert(title: Text(issue.title), message: Text(issue.message), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $session.helpVisible) { exportGuide }
        .onAppear { session.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { value in session.reduceMotion = value; if value { session.pause() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in session.pause() }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up").font(.system(size: 19, weight: .medium)).foregroundStyle(Color.accentColor)
                Text("Mettle").font(.system(size: 17, weight: .semibold))
                Spacer()
            }.padding(.horizontal, 18).padding(.top, 23).padding(.bottom, 26)
            sectionLabel("WORKSPACE")
            sidebarRow("Preview", subtitle: nil, icon: "play.rectangle", selected: !session.referencesVisible) {
                session.referencesVisible = false
            }
            sidebarRow("Motion references", subtitle: nil, icon: "square.grid.2x2", selected: session.referencesVisible) {
                session.pause(); session.referencesVisible = true
            }
            if session.renderer != nil {
                sectionLabel("OPEN FILE").padding(.top, 24)
                sidebarRow(session.title, subtitle: session.exampleID == nil ? "Your export" : "Developer fixture",
                           icon: "doc", selected: false) { session.referencesVisible = false }
            }
            Spacer(minLength: 20)
            Button { session.helpVisible = true } label: {
                Label("How to export from Figma", systemImage: "questionmark.circle")
                    .font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.bottom, 18)
            Menu {
                ForEach(session.examples) { example in
                    Button(example.title) { session.openExample(example) }
                }
            } label: { Label("Developer fixtures", systemImage: "wrench.and.screwdriver") }
                .menuStyle(.borderlessButton).font(.system(size: 10)).foregroundStyle(.secondary)
                .padding(.horizontal, 18).padding(.bottom, 18)
            Divider().padding(.horizontal, 18)
            HStack(spacing: 5) {
                Circle().fill(Color.orange).frame(width: 5, height: 5)
                Text("Experimental").font(.system(size: 11))
                Spacer(); Text("v0.3").font(.system(size: 10, design: .monospaced))
            }.foregroundStyle(.secondary).padding(18)
        }.background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }
    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 9, weight: .semibold)).tracking(1)
            .foregroundStyle(.secondary).padding(.horizontal, 18).padding(.bottom, 8)
    }
    private func sidebarRow(_ title: String, subtitle: String?, icon: String, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14)).frame(width: 18)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular)).lineLimit(2)
                    if let subtitle { Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.horizontal, 8).padding(.bottom, 3)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
    }
    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.referencesVisible ? "Motion references" : (session.renderer == nil ? "Preview" : session.title)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(session.referencesVisible ? "External inspiration · not rendered by Mettle" : (session.renderer == nil ? "Open an export. Inspect the motion." : session.sourceDescription))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if session.isLoading { ProgressView().controlSize(.small).help("Opening \(session.loadingName)") }
            Menu {
                Picker("Appearance", selection: $session.appearance) {
                    ForEach(["Light", "Dark", "System"], id: \.self) { Text($0) }
                }
            } label: { Image(systemName: "circle.lefthalf.filled") }
                .menuStyle(.borderlessButton).fixedSize().help("Appearance").accessibilityLabel("Appearance")
            Button(action: session.openPanel) { Label("Open…", systemImage: "folder") }.help("Open a Mettle export (⌘O)")
            if session.renderer != nil && !session.referencesVisible {
                Button(action: session.exportPanel) { Label("Export frame…", systemImage: "square.and.arrow.up") }
                    .disabled(session.isLoading).help("Save this frame as a PNG at its original size (⇧⌘E)")
                Button { session.inspectorVisible.toggle() } label: { Image(systemName: "sidebar.right") }
                    .buttonStyle(.borderless).foregroundStyle(session.inspectorVisible ? Color.accentColor : Color.secondary)
                    .help("Show or hide file details (⌘I)").accessibilityLabel("File details")
            }
        }.controlSize(.regular).padding(.horizontal, 22).frame(height: 66)
    }
    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .center, spacing: 32) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("FROM DESIGN TO DEVICE").font(.system(size: 9, weight: .semibold)).tracking(1.5)
                            .foregroundStyle(Color.accentColor)
                        Text("Your Figma.\nIn motion.")
                            .font(.system(size: 36, weight: .semibold)).tracking(-1.1).lineSpacing(-2).fixedSize(horizontal: false, vertical: true)
                        Text("Preview your exported animation, fine-check the timing, and save any frame.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 13) {
                        Image(systemName: "arrow.down.document").font(.system(size: 29, weight: .light)).foregroundStyle(Color.accentColor)
                        Text(session.isLoading ? "Opening…" : "Drop a Mettle export")
                            .font(.system(size: 14, weight: .medium))
                        Button("Open animation…", action: session.openPanel)
                            .buttonStyle(.borderedProminent).controlSize(.large).disabled(session.isLoading)
                        Text(".figmetal.json  ·  ⌘O")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }.frame(width: 265).padding(.vertical, 28)
                        .background(Color.accentColor.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
                }
                HStack(spacing: 24) {
                    instruction("1", "Export in Figma", "Run the local Mettle plugin.")
                    instruction("2", "Open it here", "Play, scrub or export a still.")
                    Button("Setup guide") { session.helpVisible = true }.buttonStyle(.link).font(.system(size: 11))
                }
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("A better reference point.").font(.system(size: 19, weight: .semibold)).tracking(-0.3)
                        Text("Selected motion work by independent designers.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("View all four →") { session.referencesVisible = true }.buttonStyle(.link).font(.system(size: 11))
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                    ForEach(Array(MotionReference.curated.prefix(2))) { reference in ReferenceCard(reference: reference, compact: true) }
                }
                Text("These are external references, not Mettle demos or supported imports. The preview opens only Mettle exports.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(32).frame(maxWidth: 980).frame(maxWidth: .infinity)
        }.background(Color(nsColor: .textBackgroundColor))
    }
    private var references: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Motion with a purpose.").font(.system(size: 29, weight: .semibold)).tracking(-0.7)
                    Text("Four references for the quality we’re aiming for. Watch each original to see the movement and interaction.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                    ForEach(MotionReference.curated) { ReferenceCard(reference: $0, compact: false) }
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                    Text("Reference gallery only. These previews belong to their credited creators and are not produced by Mettle. Some use features our experimental renderer doesn’t support yet. Thumbnails: CC BY 4.0.")
                        .fixedSize(horizontal: false, vertical: true)
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                Link("View attribution and compatibility notes ↗", destination: URL(string: "https://github.com/Amal-David/mettle/blob/main/docs/REFERENCES.md")!)
                    .font(.system(size: 10))
            }.padding(32).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }.background(Color(nsColor: .textBackgroundColor))
    }
    private func instruction(_ n: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(n).font(.system(size: 10, weight: .semibold)).frame(width: 21, height: 21)
                .background(Color.secondary.opacity(0.09), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var workspace: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                canvasToolbar
                Divider()
                if let renderer = session.renderer {
                    PreviewCanvas(renderer: renderer, time: session.playback.position, zoom: session.zoom,
                                  background: session.background, onError: session.renderFailed)
                }
                Divider()
                transport
            }
            if session.inspectorVisible {
                Divider(); inspector.frame(width: 226)
            }
        }
    }
    private var canvasToolbar: some View {
        HStack(spacing: 10) {
            if let document = session.document, document.scenes.count > 1 {
                Picker("Scene", selection: Binding(get: { session.selectedScene }, set: session.chooseScene)) {
                    ForEach(document.scenes.indices, id: \.self) { Text(document.scenes[$0].name).tag($0) }
                }.frame(maxWidth: 230)
            } else {
                Text("Canvas").font(.system(size: 11, weight: .medium))
                if let s = session.scene {
                    Text("\(Int(s.width)) × \(Int(s.height))").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Menu {
                Picker("Preview background", selection: $session.background) {
                    ForEach(["Checkerboard", "Light", "Dark"], id: \.self) { Text($0) }
                }
            } label: { Label("Background", systemImage: "square.lefthalf.filled") }
                .menuStyle(.borderlessButton).fixedSize().help("Preview only. Exported PNG transparency is unchanged.")
            Picker("Zoom", selection: $session.zoom) {
                ForEach(["Fit", "50%", "100%", "200%"], id: \.self) { Text($0) }
            }.labelsHidden().frame(width: 68).help("Fit the canvas or choose an explicit zoom")
        }.controlSize(.small).padding(.horizontal, 22).frame(height: 42)
    }
    private var transport: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Button(action: session.togglePlayback) {
                    Label(session.playback.isPlaying ? "Pause" : "Play", systemImage: session.playback.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 53)
                }.buttonStyle(.borderedProminent).disabled(!session.hasMotion || session.reduceMotion || session.isLoading)
                    .help(session.reduceMotion ? "Reduce Motion is enabled in macOS" : "Play or pause (Space)")
                Button { session.seek(0) } label: { Image(systemName: "backward.end") }
                    .buttonStyle(.borderless).help("Restart (⌘R)").accessibilityLabel("Restart animation")
                Slider(value: Binding(get: { session.playback.position }, set: session.seek), in: 0...max(0.001, session.duration))
                    .disabled(!session.hasMotion || session.isLoading).accessibilityLabel("Animation time")
                    .accessibilityValue(String(format: "%.2f of %.2f seconds", session.playback.position, session.duration))
                Text(String(format: "%.2f / %.2f s", session.playback.position, session.duration))
                    .font(.system(size: 10, design: .monospaced)).monospacedDigit().frame(width: 104, alignment: .trailing)
            }
            HStack(spacing: 10) {
                Group {
                    if session.reduceMotion { Label("Reduce Motion is on", systemImage: "accessibility") }
                    else if !session.status.isEmpty { Label(session.status, systemImage: "checkmark.circle") }
                    else if !session.hasMotion { Text("Static frame · no animation tracks") }
                    else if session.exampleID != nil { Text("Developer fixture · not a design reference") }
                    else { Text(session.playback.isPlaying ? "Playing" : "Paused · Space to play") }
                }.font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 2)
                Picker("Speed", selection: Binding(get: { session.playback.speed }, set: session.setSpeed)) {
                    ForEach([0.25, 0.5, 1.0, 2.0], id: \.self) { Text(String(format: "%g×", $0)).tag($0) }
                }.frame(width: 98).disabled(!session.hasMotion).controlSize(.small)
                Toggle(isOn: Binding(get: { session.repeatEnabled }, set: { _ in session.toggleRepeat() })) {
                    Label(session.playback.repetition == .pingPong ? "Ping-pong" : "Repeat", systemImage: "repeat")
                }.toggleStyle(.button).controlSize(.small).disabled(!session.hasMotion)
            }
        }.padding(.horizontal, 22).padding(.vertical, 16)
    }
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Text("File details").font(.system(size: 13, weight: .semibold)); Spacer() }
                if let scene = session.scene {
                    detail("SCENE", scene.name)
                    detail("CANVAS", "\(Int(scene.width)) × \(Int(scene.height)) px")
                    detail("DURATION", session.hasMotion ? String(format: "%.2f seconds", scene.duration) : "Static frame")
                    detail("SOURCE", session.exampleID == nil ? "Local Mettle export" : session.sourceDescription)
                }
                Divider()
                Text("This is a preview, not a design editor. Change the animation in Figma, then open the new export.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let diagnostics = session.document?.diagnostics, !diagnostics.isEmpty {
                    DisclosureGroup("Export notes (\(diagnostics.count))") {
                        ForEach(diagnostics.indices, id: \.self) { i in
                            Text(diagnostics[i].message).font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 6)
                        }
                    }.font(.system(size: 11))
                }
                if let r = session.renderer {
                    DisclosureGroup("Rendering details") {
                        VStack(alignment: .leading, spacing: 12) {
                            detail("DEVICE", r.device.name)
                            detail("GEOMETRY", "\(r.vertexCount) vertices")
                            detail("ANTIALIASING", "\(r.sampleCount)× MSAA")
                        }.padding(.top, 12)
                    }.font(.system(size: 11))
                }
            }.padding(18)
        }.background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }
    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).tracking(0.5)
            Text(value).font(.system(size: 11)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var exportGuide: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Run Mettle locally").font(.system(size: 22, weight: .semibold))
            Text("Mettle Preview opens exports made by the Mettle plugin. It doesn’t open raw Figma files or connect to your account.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            instruction("1", "Install the development plugin", "In Figma: Plugins → Development → Import plugin from manifest. Choose plugin/manifest.json in the Mettle repository.")
            instruction("2", "Export a frame", "Select a frame, run Mettle, and review the compatibility report. Keep “Allow incomplete export” unchecked.")
            instruction("3", "Open the exported file", "Save the .figmetal.json file, then drag it into this window or choose Open animation.")
            Link("Full local setup & troubleshooting ↗", destination: URL(string: "https://github.com/Amal-David/mettle/blob/main/docs/LOCAL_SETUP.md")!)
            Text("The desktop preview is optional. The Figma exporter creates the asset; the Swift package plays it inside your app.").font(.system(size: 11)).foregroundStyle(.secondary)
            Text("Some Figma features are not supported yet. The export report is the source of truth; a loaded preview is not a pixel-perfect certification.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("Got it") { session.helpVisible = false }.keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 500)
    }
}

private struct ReferenceCard: View {
    let reference: MotionReference
    var compact: Bool
    @State private var hovered = false
    var body: some View {
        Button(action: reference.openOriginal) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Color(white: 0.96)
                    if let image = reference.thumbnail {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else { Image(systemName: "play.rectangle").foregroundStyle(.secondary) }
                }.frame(height: compact ? 154 : 155).clipped()
                VStack(alignment: .leading, spacing: 7) {
                    Text(reference.category).font(.system(size: 8, weight: .semibold)).tracking(0.9).foregroundStyle(.secondary)
                    HStack(alignment: .top) {
                        Text(reference.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                        Spacer(minLength: 3)
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
                    if !compact {
                        Text(reference.lesson).font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true).frame(minHeight: 30, alignment: .top)
                    }
                    HStack {
                        Text("by " + reference.creator).font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer(minLength: 2)
                        Text("Watch original ↗").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.accentColor)
                    }.padding(.top, 3)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }.background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(hovered ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.10)))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .help(reference.limitation + " Opens the creator’s page in your browser.")
            .accessibilityLabel("Watch " + reference.title + " by " + reference.creator + ". External reference, not Mettle output.")
    }
}

private struct PreviewCanvas: View {
    let renderer: MetalRenderer
    let time: Double
    let zoom: String
    let background: String
    let onError: (Error) -> Void
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        GeometryReader { geometry in
            let sw = renderer.scene.width, sh = renderer.scene.height
            let fit = max(0.01, min((geometry.size.width - 64)/sw, (geometry.size.height - 64)/sh))
            let scale = zoom == "Fit" ? fit : (Double(zoom.replacingOccurrences(of: "%", with: "")) ?? 100)/100
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    backdrop
                    MettleView(renderer: renderer, time: time, isPlaying: false, onError: onError)
                        .id(ObjectIdentifier(renderer))
                        .accessibilityLabel("Animation artwork. Use the playback controls below the canvas.")
                }.frame(width: sw*scale, height: sh*scale)
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                    .padding(32)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
            }.background(Color(nsColor: .underPageBackgroundColor))
        }
    }
    @ViewBuilder private var backdrop: some View {
        if background == "Checkerboard" {
            Canvas { context, size in
                let tile: CGFloat = 10
                let base = colorScheme == .dark ? 0.19 : 0.97
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: base)))
                var cells = Path()
                for row in 0..<Int(ceil(size.height/tile)) {
                    for column in 0..<Int(ceil(size.width/tile)) where (row+column)%2 == 0 {
                        cells.addRect(CGRect(x: CGFloat(column)*tile, y: CGFloat(row)*tile, width: tile, height: tile))
                    }
                }
                context.fill(cells, with: .color(Color(white: colorScheme == .dark ? 0.24 : 0.91)))
            }.accessibilityHidden(true)
        } else { Color(white: background == "Light" ? 1 : 0.10) }
    }
}
#endif
