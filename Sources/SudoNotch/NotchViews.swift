import SwiftUI
import UniformTypeIdentifiers

struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let tr = min(topRadius, rect.width / 4)
        let br = min(bottomRadius, rect.height / 2, rect.width / 4)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr, y: rect.minY + tr), control: CGPoint(x: rect.minX + tr, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr + br, y: rect.maxY), control: CGPoint(x: rect.minX + tr, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - tr, y: rect.maxY - br), control: CGPoint(x: rect.maxX - tr, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct NotchRootView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        let size = model.currentSize
        let tr: CGFloat = model.isExpanded ? 14 : 8
        let shape = NotchShape(topRadius: tr, bottomRadius: model.isExpanded ? 28 : 13)
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            Group {
                if model.isExpanded {
                    // Laid out at its final size the whole time, so it never reflows (and never squishes) while the shape grows or shrinks.
                    ExpandedView(model: model)
                        .padding(.horizontal, 14)
                        .frame(width: model.expandedSize.width, height: model.expandedSize.height, alignment: .top)
                        .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.08)),
                                                removal: .opacity.animation(.easeIn(duration: 0.08))))
                } else {
                    CollapsedView(model: model)
                        .padding(.horizontal, 8)
                        .transition(.opacity.animation(.easeOut(duration: 0.15)))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)   // everything, including content that is fading out, is cut to the notch outline
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(NotchWindowController.spring, value: model.layoutKey)
        .animation(.easeInOut(duration: 0.2), value: model.transient)
        .environment(\.colorScheme, .dark)
        .tint(Color(nsColor: settings.accentColor))
    }
}

// MARK: - Collapsed

struct CollapsedView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        HStack(spacing: 0) {
            left.frame(width: max(0, model.wing - 8), alignment: .leading)
            Spacer(minLength: 0)
            right.frame(width: max(0, model.wing - 8), alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .frame(height: model.baseSize.height)
    }

    @ViewBuilder var left: some View {
        switch model.transient {
        case .toast(let symbol, _):
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
        case .hud(let kind, _):
            Image(systemName: hudSymbol(kind, value: hudValue)).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white).frame(width: 24, alignment: .leading)
        case nil:
            if model.keyboard.isLocked {
                Image(systemName: "lock.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.orange)
            } else if model.musicActive {
                Group {
                    if let art = model.music.artwork {
                        Image(nsImage: art).resizable().scaledToFill()
                    } else {
                        Color.white.opacity(0.15).overlay(Image(systemName: "music.note").foregroundStyle(.white.opacity(0.8)))
                    }
                }
                .frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 5))
            } else if model.lid.isAwakeWhenClosed {
                Image(systemName: "laptopcomputer").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.orange)
            } else if model.caffeine.isOn {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.orange)
            }
        }
    }

    var hudValue: Double { if case .hud(_, let v) = model.transient { return v } else { return 0 } }

    @ViewBuilder var right: some View {
        switch model.transient {
        case .toast(_, let text):
            Text(text).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
        case .hud(let kind, let value):
            HUDBar(value: kind == .muted ? 0 : value)
        case nil:
            if model.keyboard.isLocked {
                Text(model.keyboard.timeString).font(.system(size: 11.5, weight: .semibold, design: .monospaced)).foregroundStyle(Color.orange)
            } else if model.musicActive {
                Equalizer(color: Color(nsColor: AppSettings.shared.accentColor), paused: model.isHidden)
            } else if model.lid.isAwakeWhenClosed {
                Text(model.lid.timeString).font(.system(size: 11.5, weight: .semibold, design: .monospaced)).foregroundStyle(Color.orange)
            } else if model.caffeine.isOn {
                Text(model.caffeine.timeString).font(.system(size: 11.5, weight: .semibold, design: .monospaced)).foregroundStyle(Color.orange)
            }
        }
    }
}

func hudSymbol(_ kind: HUDKind, value: Double) -> String {
    switch kind {
    case .muted: return "speaker.slash.fill"
    case .brightness: return value > 0.5 ? "sun.max.fill" : "sun.min.fill"
    case .volume:
        if value <= 0.001 { return "speaker.fill" }
        return value < 0.34 ? "speaker.wave.1.fill" : (value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
    }
}

struct HUDBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule().fill(Color.white).frame(width: max(5, g.size.width * CGFloat(min(1, max(0, value)))))
            }
        }
        .frame(width: 44, height: 5)
        .animation(.easeOut(duration: 0.12), value: value)
    }
}

struct Equalizer: View {
    let color: Color
    var paused = false
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.15, paused: paused)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<4, id: \.self) { i in
                    let h = 5 + 11 * abs(sin(t * (3.0 + Double(i) * 0.9) + Double(i)))
                    Capsule().fill(color).frame(width: 3, height: h)
                }
            }
            .frame(height: 18)
        }
    }
}

// MARK: - Expanded

struct ExpandedView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(NotchTab.allCases) { t in
                    Button {
                        withAnimation(NotchWindowController.spring) { model.tab = t }
                    } label: {
                        Image(systemName: t.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 24)
                            .background(model.tab == t ? Color.white.opacity(0.18) : Color.clear, in: Capsule())
                            .foregroundStyle(model.tab == t ? Color.white : Color.white.opacity(0.55))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                IconButton(symbol: model.isPinned ? "pin.fill" : "pin", active: model.isPinned) { model.isPinned.toggle() }
                IconButton(symbol: "gearshape") { AppDelegate.shared.showSettings() }
            }
            .padding(.horizontal, 20)
            .frame(height: model.baseSize.height)

            Group {
                switch model.tab {
                case .music: MusicView(music: model.music)
                case .clipboard: ClipboardView(clipboard: model.clipboard)
                case .shelf: ShelfView(shelf: model.shelf, model: model)
                case .airdrop: AirDropView(shelf: model.shelf)
                case .tools: ToolsView(keyboard: model.keyboard, lid: model.lid, caffeine: model.caffeine)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct IconButton: View {
    let symbol: String
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 24)
                .foregroundStyle(active ? Color.white : Color.white.opacity(0.55))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Music

func timeString(_ s: Double) -> String {
    let t = Int(max(0, s))
    return String(format: "%d:%02d", t / 60, t % 60)
}

struct MusicView: View {
    @ObservedObject var music: MusicService

    var body: some View {
        if music.hasTrack {
            HStack(spacing: 16) {
                Group {
                    if let art = music.artwork {
                        Image(nsImage: art).resizable().scaledToFill()
                    } else {
                        Color.white.opacity(0.1).overlay(Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(.white.opacity(0.5)))
                    }
                }
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 6) {
                    Text(music.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(music.artist).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    Spacer(minLength: 2)
                    SeekBar(music: music)
                    HStack(spacing: 26) {
                        Spacer()
                        Button { music.previous() } label: { Image(systemName: "backward.fill") }
                        Button { music.togglePlay() } label: {
                            Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 20))
                        }
                        Button { music.next() } label: { Image(systemName: "forward.fill") }
                        Spacer()
                    }
                    .font(.system(size: 16))
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "music.note.list").font(.system(size: 26)).foregroundStyle(.white.opacity(0.4))
                Text(music.runningSources.isEmpty ? "Open a player to see what's playing" : "Nothing playing")
                    .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.55))
                HStack {
                    ForEach(MusicService.Source.allCases, id: \.rawValue) { s in
                        Button(s.rawValue) { music.open(s) }.buttonStyle(PillButtonStyle(fixedWidth: false))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct SeekBar: View {
    @ObservedObject var music: MusicService
    @State private var scrub: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let pos = scrub ?? music.livePosition
            let frac = music.duration > 0 ? pos / music.duration : 0
            HStack(spacing: 8) {
                Text(timeString(pos)).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2))
                        Capsule().fill(Color.white).frame(width: g.size.width * CGFloat(min(1, max(0, frac))))
                    }
                    .frame(height: 5).frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in scrub = Double(min(1, max(0, v.location.x / g.size.width))) * music.duration }
                        .onEnded { v in
                            let t = Double(min(1, max(0, v.location.x / g.size.width))) * music.duration
                            music.seek(to: t); scrub = nil
                        })
                }
                .frame(height: 14)
                Text(timeString(music.duration)).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

// MARK: Clipboard

struct ClipboardView: View {
    @ObservedObject var clipboard: ClipboardService

    var body: some View {
        if clipboard.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 24)).foregroundStyle(.white.opacity(0.4))
                Text("Copy something and it shows up here").font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .trailing, spacing: 6) {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(clipboard.items) { item in
                            Button { clipboard.copy(item) } label: {
                                HStack {
                                    Text(item.preview).lineLimit(1).font(.system(size: 12.5))
                                    Spacer(minLength: 8)
                                    if clipboard.copiedID == item.id {
                                        Label("Copied", systemImage: "checkmark").font(.system(size: 10.5, weight: .semibold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button("Clear") { clipboard.clear() }.buttonStyle(.plain)
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

// MARK: Shelf

struct ShelfView: View {
    @ObservedObject var shelf: ShelfService
    @ObservedObject var model: NotchModel
    @State private var targeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(targeted ? Color.accentColor : Color.white.opacity(0.25))
            if shelf.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 24))
                    Text("Drop files here to park them").font(.system(size: 12.5))
                }
                .foregroundStyle(.white.opacity(targeted ? 0.9 : 0.5))
            } else {
                HStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(shelf.items) { item in ShelfTile(item: item) { shelf.remove(item) } }
                        }
                        .padding(12)
                    }
                    Button { shelf.clear() } label: { Image(systemName: "trash").font(.system(size: 12)) }
                        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5)).padding(.trailing, 12)
                }
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { shelf.add([url]) }
                }
            }
            return true
        }
    }
}

struct ShelfTile: View {
    let item: ShelfItem
    let remove: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 44, height: 44)
            Text(item.name).font(.system(size: 10.5)).lineLimit(1).frame(width: 70)
        }
        .overlay(alignment: .topTrailing) {
            if hover {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                        .foregroundStyle(.white, Color.black.opacity(0.7))
                }
                .buttonStyle(.plain).offset(x: 6, y: -4)
            }
        }
        .onHover { hover = $0 }
        .onDrag { NSItemProvider(object: item.url as NSURL) }
    }
}

// MARK: AirDrop

struct AirDropView: View {
    @ObservedObject var shelf: ShelfService
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(targeted ? Color.accentColor : Color.white.opacity(0.25))
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(targeted ? Color.accentColor : Color.white.opacity(0.75))
                    Text(targeted ? "Release to AirDrop" : "Drop files to AirDrop")
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
                let group = DispatchGroup()
                var urls: [URL] = []
                for p in providers {
                    group.enter()
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        DispatchQueue.main.async { if let url { urls.append(url) }; group.leave() }
                    }
                }
                group.notify(queue: .main) { Self.send(urls) }
                return true
            }

            VStack(spacing: 8) {
                AirDropButton(title: "Choose files…", symbol: "doc.badge.plus") { choose() }
                AirDropButton(title: shelf.items.isEmpty ? "Send shelf" : "Send shelf (\(shelf.items.count))",
                              symbol: "tray.full") { Self.send(shelf.items.map(\.url)) }
                    .opacity(shelf.items.isEmpty ? 0.4 : 1).disabled(shelf.items.isEmpty)
                AirDropButton(title: "Open AirDrop", symbol: "arrow.up.forward.app") { Self.openAirDrop() }
            }
            .frame(width: 160)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { r in if r == .OK { Self.send(panel.urls) } }
    }

    static func send(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }

    static func openAirDrop() {
        let path = "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app"
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else if let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
            NSWorkspace.shared.openApplication(at: finder, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

struct AirDropButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).frame(width: 18)
                Text(title).font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Tools: keyboard lock, lid, caffeinate

struct ToolCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(white: 0.085), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5))
    }
}

/// Spotlight-style result header: an icon tile and a title.
struct ToolHeader: View {
    let symbol: String
    let title: String
    var active = false
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? Color.orange : .white.opacity(0.9))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(active ? Color.orange.opacity(0.2) : Color.white.opacity(0.09)))
            Text(title).font(.system(size: 13.5, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

func toolCaption(_ text: String, warning: Bool = false) -> some View {
    Text(text).font(.system(size: 11.5)).foregroundStyle(warning ? Color.orange : .white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
}

/// Clock-time field shown next to the duration chip when it is on "Until…" (today if still ahead, otherwise tomorrow).
struct WakeTimeRow: View {
    @Binding var time: Date
    var body: some View {
        DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
            .labelsHidden().datePickerStyle(.field).environment(\.colorScheme, .dark).fixedSize()
    }
}

struct ControlsCards: View {
    @ObservedObject var keyboard: KeyboardLockService
    @ObservedObject var lid: LidService
    @ObservedObject var caffeine: CaffeinateService
    private let tick = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            ToolCard {
                ToolHeader(symbol: keyboard.isLocked ? "lock.fill" : "keyboard", title: "Keyboard lock", active: keyboard.isLocked)
                toolCaption(keyboard.isLocked ? "Every key is off. Wipe away!" : "Turns every key off so you can clean your keyboard.")
                Spacer(minLength: 0)
                if keyboard.needsPermission {
                    toolCaption("Allow SudoNotch under Privacy & Security → Accessibility, then try again.", warning: true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    if !keyboard.isLocked {
                        PillMenu(selection: $keyboard.minutes, options: [("1 min", 1), ("2 min", 2), ("5 min", 5), ("10 min", 10), ("Until unlocked", 0)])
                    }
                    Button(keyboard.isLocked ? "Unlock · \(keyboard.timeString)" : "Lock keyboard") { keyboard.toggle() }
                        .buttonStyle(PillButtonStyle(prominent: keyboard.isLocked))
                }
            }
            ToolCard {
                ToolHeader(symbol: "laptopcomputer", title: "Awake with lid closed", active: lid.isAwakeWhenClosed)
                toolCaption(lid.message ?? (lid.isAwakeWhenClosed
                     ? "ON, turns off by itself at \(lid.endString) (\(lid.timeString) left). Don't put your Mac in a bag like this."
                     : (lid.hasPermission ? "OFF: closing the lid sleeps your Mac. Pick a time and it switches back by itself."
                                          : "OFF. First time only: macOS asks for your password once, then it never asks again.")),
                            warning: lid.message != nil)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 6) {
                    if !lid.isAwakeWhenClosed {
                        HStack(spacing: 6) {
                            PillMenu(selection: $lid.minutes, options: [("15 min", 15), ("30 min", 30), ("1 hour", 60), ("2 hours", 120), ("4 hours", 240),
                                                                    ("8 hours", 480), ("12 hours", 720), ("Until…", -1)])
                            if lid.minutes < 0 { WakeTimeRow(time: $lid.wakeTime) }
                        }
                    }
                    Button(lid.isBusy ? "Working…" : (lid.isAwakeWhenClosed ? "Turn off" : "Turn on")) { lid.toggle() }
                        .buttonStyle(PillButtonStyle(prominent: lid.isAwakeWhenClosed)).disabled(lid.isBusy)
                }
            }
            ToolCard {
                ToolHeader(symbol: "cup.and.saucer.fill", title: "Caffeinate", active: caffeine.isOn)
                toolCaption(caffeine.isOn ? "Your Mac and screen stay awake\(caffeine.timeString == "On" ? "." : " until \(caffeine.endString) (\(caffeine.timeString) left).")"
                                          : "Stops your Mac and screen from sleeping. Same as the caffeinate command.")
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 6) {
                    if !caffeine.isOn {
                        HStack(spacing: 6) {
                            PillMenu(selection: $caffeine.minutes, options: [("15 min", 15), ("30 min", 30), ("1 hour", 60), ("2 hours", 120), ("4 hours", 240),
                                                                         ("8 hours", 480), ("12 hours", 720), ("Until…", -1), ("Until off", 0)])
                            if caffeine.minutes < 0 { WakeTimeRow(time: $caffeine.wakeTime) }
                        }
                    }
                    Button(caffeine.isOn ? "Stop" : "Stay awake") { caffeine.toggle() }
                        .buttonStyle(PillButtonStyle(prominent: caffeine.isOn))
                }
            }
        }
        .onAppear { lid.refresh() }
        .onReceive(tick) { _ in lid.refresh() }
    }
}

/// The Tools tab.
struct ToolsView: View {
    @ObservedObject var keyboard: KeyboardLockService
    @ObservedObject var lid: LidService
    @ObservedObject var caffeine: CaffeinateService

    var body: some View { ControlsCards(keyboard: keyboard, lid: lid, caffeine: caffeine) }
}
