import AppKit
import QuartzCore
import Combine

// MARK: - Overlay view: rounded black corners + hot corner animations

final class CornerView: NSView {
    private var shapes: [Corner: CAShapeLayer] = [:]
    var radius: CGFloat = 12 { didSet { updatePaths() } }
    var cornersVisible = true { didSet { shapes.values.forEach { $0.isHidden = !cornersVisible } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false
        for c in Corner.allCases {
            let l = CAShapeLayer()
            l.fillColor = NSColor.black.cgColor
            layer?.addSublayer(l)
            shapes[c] = l
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        updatePaths()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Black fill between the screen corner and a quarter circle of the given radius.
    func cornerPath(_ c: Corner, radius r: CGFloat) -> CGPath {
        let w = bounds.width, h = bounds.height
        let p = CGMutablePath()
        switch c {
        case .topLeft:
            p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: r, y: h))
            p.addArc(center: CGPoint(x: r, y: h - r), radius: r, startAngle: .pi / 2, endAngle: .pi, clockwise: false)
        case .topRight:
            p.move(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w - r, y: h))
            p.addArc(center: CGPoint(x: w - r, y: h - r), radius: r, startAngle: .pi / 2, endAngle: 0, clockwise: true)
        case .bottomLeft:
            p.move(to: .zero); p.addLine(to: CGPoint(x: 0, y: r))
            p.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: false)
        case .bottomRight:
            p.move(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w - r, y: 0))
            p.addArc(center: CGPoint(x: w - r, y: r), radius: r, startAngle: 3 * .pi / 2, endAngle: 2 * .pi, clockwise: false)
        }
        p.closeSubpath()
        return p
    }

    func point(of c: Corner) -> CGPoint {
        switch c {
        case .topLeft: return CGPoint(x: 0, y: bounds.height)
        case .topRight: return CGPoint(x: bounds.width, y: bounds.height)
        case .bottomLeft: return .zero
        case .bottomRight: return CGPoint(x: bounds.width, y: 0)
        }
    }

    private func updatePaths() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for c in Corner.allCases {
            shapes[c]?.frame = bounds
            shapes[c]?.path = cornerPath(c, radius: radius)
        }
        CATransaction.commit()
    }

    // MARK: Animations

    func play(_ anim: CornerAnimation, at c: Corner, color: NSColor) {
        switch anim {
        case .none, .byAction: break
        case .ripple: ripple(c, color)
        case .glow: glow(c, color)
        case .neonArc: neonArc(c, color)
        case .sparks: sparks(c, color)
        case .squeeze: squeeze(c)
        }
    }

    func add(_ l: CALayer, removeAfter t: TimeInterval) {
        layer?.addSublayer(l)
        DispatchQueue.main.asyncAfter(deadline: .now() + t) { l.removeFromSuperlayer() }
    }

    private func ripple(_ c: Corner, _ color: NSColor) {
        let pt = point(of: c)
        for i in 0..<3 {
            let l = CAShapeLayer()
            l.frame = bounds
            l.fillColor = nil
            l.strokeColor = color.cgColor
            l.lineWidth = 3 - CGFloat(i) * 0.6
            let small = CGPath(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8), transform: nil)
            let big = CGPath(ellipseIn: CGRect(x: pt.x - 170, y: pt.y - 170, width: 340, height: 340), transform: nil)
            l.path = big
            l.opacity = 0
            let path = CABasicAnimation(keyPath: "path"); path.fromValue = small; path.toValue = big
            path.timingFunction = CAMediaTimingFunction(name: .easeOut)
            let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 0.95; fade.toValue = 0
            let g = CAAnimationGroup()
            g.animations = [path, fade]; g.duration = 0.85
            g.beginTime = CACurrentMediaTime() + Double(i) * 0.14
            g.fillMode = .backwards
            l.add(g, forKey: "ripple")
            add(l, removeAfter: 1.4)
        }
    }

    private func glow(_ c: Corner, _ color: NSColor) {
        let pt = point(of: c)
        let size: CGFloat = 360
        let l = CAGradientLayer()
        l.type = .radial
        l.colors = [color.withAlphaComponent(0.85).cgColor, color.withAlphaComponent(0.25).cgColor, NSColor.clear.cgColor]
        l.locations = [0, 0.45, 1]
        l.startPoint = CGPoint(x: 0.5, y: 0.5)
        l.endPoint = CGPoint(x: 1, y: 1)
        l.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        l.position = pt
        l.opacity = 0
        let scale = CABasicAnimation(keyPath: "transform.scale"); scale.fromValue = 0.15; scale.toValue = 1.1
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let fade = CAKeyframeAnimation(keyPath: "opacity"); fade.values = [0, 1, 0]; fade.keyTimes = [0, 0.25, 1]
        let g = CAAnimationGroup(); g.animations = [scale, fade]; g.duration = 0.7
        l.add(g, forKey: "glow")
        add(l, removeAfter: 0.8)
    }

    private func neonArc(_ c: Corner, _ color: NSColor) {
        let pt = point(of: c)
        let (start, end): (CGFloat, CGFloat) = {
            switch c {
            case .topLeft: return (-.pi / 2, 0)
            case .topRight: return (-.pi, -.pi / 2)
            case .bottomLeft: return (0, .pi / 2)
            case .bottomRight: return (.pi / 2, .pi)
            }
        }()
        for (i, r) in [48, 82, 116].enumerated() {
            let l = CAShapeLayer()
            l.frame = bounds
            let path = CGMutablePath()
            path.addArc(center: pt, radius: CGFloat(r), startAngle: start, endAngle: end, clockwise: false)
            l.path = path
            l.fillColor = nil
            l.strokeColor = color.cgColor
            l.lineWidth = 3.5
            l.lineCap = .round
            l.shadowColor = color.cgColor; l.shadowRadius = 9; l.shadowOpacity = 1; l.shadowOffset = .zero
            l.opacity = 0
            let draw = CABasicAnimation(keyPath: "strokeEnd"); draw.fromValue = 0; draw.toValue = 1; draw.duration = 0.38
            draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
            let fade = CAKeyframeAnimation(keyPath: "opacity"); fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.1, 0.6, 1]
            fade.duration = 0.8
            let g = CAAnimationGroup(); g.animations = [draw, fade]; g.duration = 0.8
            g.beginTime = CACurrentMediaTime() + Double(i) * 0.09; g.fillMode = .backwards
            l.add(g, forKey: "arc")
            add(l, removeAfter: 1.3)
        }
    }

    private func sparks(_ c: Corner, _ color: NSColor) {
        let pt = point(of: c)
        let dot = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            NSColor.white.setFill(); NSBezierPath(ovalIn: r).fill(); return true
        }
        guard let cg = dot.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let cell = CAEmitterCell()
        cell.contents = cg
        cell.birthRate = 500
        cell.lifetime = 0.8; cell.lifetimeRange = 0.3
        cell.velocity = 260; cell.velocityRange = 140
        cell.yAcceleration = -60
        cell.scale = 0.55; cell.scaleRange = 0.3; cell.scaleSpeed = -0.5
        cell.alphaSpeed = -1.2
        cell.color = color.cgColor
        cell.emissionRange = .pi / 2
        cell.emissionLongitude = {
            switch c {
            case .topLeft: return -.pi / 4
            case .topRight: return -3 * .pi / 4
            case .bottomLeft: return .pi / 4
            case .bottomRight: return 3 * .pi / 4
            }
        }()
        let e = CAEmitterLayer()
        e.frame = bounds
        e.emitterPosition = pt
        e.emitterShape = .point
        e.renderMode = .additive
        e.emitterCells = [cell]
        add(e, removeAfter: 1.4)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { e.birthRate = 0 }
    }

    private func squeeze(_ c: Corner) {
        guard let l = shapes[c] else { return }
        let big = min(bounds.width, bounds.height) * 0.16 + 60
        let a = CAKeyframeAnimation(keyPath: "path")
        a.values = [cornerPath(c, radius: radius), cornerPath(c, radius: big), cornerPath(c, radius: radius)]
        a.keyTimes = [0, 0.35, 1]
        a.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(controlPoints: 0.3, 1.6, 0.5, 1)]
        a.duration = 0.75
        l.add(a, forKey: "squeeze")
    }
}

// MARK: - Controller

final class ScreenCornerController {
    let settings = AppSettings.shared
    private var windows: [CGDirectDisplayID: (NSWindow, CornerView)] = [:]
    private var globalMonitor: Any?
    private var bag = Set<AnyCancellable>()

    private var armed = true
    private var pending: DispatchWorkItem?
    private var pendingKey: String?
    private var activePoint: CGPoint?

    var onOpenNotch: (() -> Void)?
    private(set) var lastEvent = ""

    func start() {
        rebuild()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.rebuild() }
        settings.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.applySettings() } }.store(in: &bag)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.mouseMoved()
        }
        // Synthetic cursor jumps (used only by the test helpers) don't emit mouse-moved events, so poll when testing.
        if UserDefaults.standard.bool(forKey: "debugHooks") {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.mouseMoved() }
        }
    }

    private var pollTimer: Timer?
    private var screenRects: [(rect: CGRect, screen: NSScreen)] = []
    private var cachedEnabled = true
    private var cachedSize: CGFloat = 5
    private var cachedDwell: Double = 0.05

    private func displayID(_ s: NSScreen) -> CGDirectDisplayID {
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    func rebuild() {
        let ids = Set(NSScreen.screens.map(displayID))
        for (id, w) in windows where !ids.contains(id) { w.0.orderOut(nil); windows[id] = nil }
        for s in NSScreen.screens {
            let id = displayID(s)
            if let (w, v) = windows[id] {
                if w.frame != s.frame { w.setFrame(s.frame, display: true) }
                v.frame = CGRect(origin: .zero, size: s.frame.size)
                continue
            }
            let w = NSWindow(contentRect: s.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            w.isReleasedWhenClosed = false
            let v = CornerView(frame: CGRect(origin: .zero, size: s.frame.size))
            v.autoresizingMask = [.width, .height]
            w.contentView = v
            windows[id] = (w, v)
            w.setFrame(s.frame, display: true)
            w.orderFrontRegardless()
            LockScreenSupport.shared.show(w)
        }
        screenRects = NSScreen.screens.map { ($0.frame.insetBy(dx: -1, dy: -1), $0) }
        applySettings()
    }

    func applySettings() {
        cachedEnabled = settings.hotCornersEnabled
        cachedSize = CGFloat(settings.hotCornerSize)
        cachedDwell = settings.hotCornerDwell
        for (id, (w, v)) in windows {
            let hasHardwareNotch = NSScreen.screens.first(where: { displayID($0) == id })?.safeAreaInsets.top ?? 0 > 0
            // Real displays only round their own corners: skip external monitors so there are no black wedges at seams.
            let eligible = CGDisplayIsBuiltin(id) != 0 || NSScreen.screens.count == 1
            v.radius = CGFloat(settings.cornerRadius)
            // Notched MacBooks already have rounded display corners; drawing ours would double them up.
            v.cornersVisible = settings.cornersEnabled && !hasHardwareNotch && eligible
            w.sharingType = settings.hideFromSharing ? .none : .readOnly
            if settings.cornersEnabled || settings.hotCornersEnabled { w.orderFrontRegardless() } else { w.orderOut(nil) }
        }
    }

    // MARK: Hot corner detection

    private func mouseMoved() {
        guard cachedEnabled else { return }
        let p = NSEvent.mouseLocation
        guard let s = screenRects.first(where: { $0.rect.contains(p) })?.screen else { return }
        let f = s.frame, t = cachedSize
        let l = p.x <= f.minX + t, r = p.x >= f.maxX - t, b = p.y <= f.minY + t, top = p.y >= f.maxY - t
        // Fast exit for the 99.9% of mouse moves that are nowhere near a corner.
        if !((l || r) && (b || top)) {
            if pending != nil { pending?.cancel(); pending = nil }
            pendingKey = nil
            if !armed {
                if let a = activePoint, hypot(p.x - a.x, p.y - a.y) > 40 { armed = true; activePoint = nil }
                else if activePoint == nil { armed = true }
            }
            return
        }
        var corner: Corner?
        if l && top { corner = .topLeft } else if r && top { corner = .topRight }
        else if l && b { corner = .bottomLeft } else if r && b { corner = .bottomRight }

        if let corner {
            let key = "\(displayID(s))|\(corner.rawValue)"
            guard armed, pendingKey != key else { return }
            pending?.cancel()
            pendingKey = key
            let w = DispatchWorkItem { [weak self] in
                guard let self else { return }
                pending = nil
                armed = false
                activePoint = p
                fire(corner, on: s)
            }
            pending = w
            DispatchQueue.main.asyncAfter(deadline: .now() + cachedDwell, execute: w)
        } else {
            pending?.cancel(); pending = nil; pendingKey = nil
            if let a = activePoint, hypot(p.x - a.x, p.y - a.y) > 40 { armed = true; activePoint = nil }
            else if activePoint == nil { armed = true }
        }
    }

    // MARK: Firing

    func fire(_ corner: Corner, on screen: NSScreen? = nil, previewOnly: Bool = false, force: Bool = false) {
        // macOS mode: stay quiet on corners where macOS itself does nothing.
        if settings.usesSystemHotCorners, !previewOnly, !force, settings.systemActionCode(for: corner) == 0 { return }
        guard let s = screen ?? NSScreen.screens.first else { return }
        let source = settings.usesSystemHotCorners ? "macOS(\(settings.systemActionName(for: corner)))" : settings.action(for: corner).rawValue
        lastEvent = "\(corner.rawValue):\(settings.animation(for: corner).rawValue):\(source)"
        let anim = settings.animation(for: corner)
        if let view = windows[displayID(s)]?.1 {
            if anim == .byAction { view.playTheme(theme(for: corner), at: corner, color: settings.accentColor) }
            else { view.play(anim, at: corner, color: settings.accentColor) }
        }
        // In macOS mode the system itself performs the action; we only animate.
        guard !previewOnly, !settings.usesSystemHotCorners else { return }
        let action = settings.action(for: corner), arg = settings.argument(for: corner)
        // Let the animation start before the action takes over the screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.run(action, arg: arg) }
    }

    func preview(_ corner: Corner) { fire(corner, previewOnly: true) }

    func windowView(for s: NSScreen) -> CornerView? { windows[displayID(s)]?.1 }

    func playOn(display id: CGDirectDisplayID, _ a: CornerAnimation, _ c: Corner) {
        windows[id]?.1.play(a, at: c, color: settings.accentColor)
    }

    private func run(_ action: CornerAction, arg: String) {
        switch action {
        case .none: break
        case .missionControl: dock("com.apple.expose.awake") { self.open("/System/Applications/Mission Control.app") }
        case .appExpose: dock("com.apple.expose.front.awake")
        case .showDesktop: dock("com.apple.showdesktop.awake")
        case .apps:
            let candidates = ["/System/Applications/Apps.app", "/System/Applications/Launchpad.app"]
            if let p = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) { open(p) }
        case .screenSaver: open("/System/Library/CoreServices/ScreenSaverEngine.app")
        case .sleepDisplay: shell("/usr/bin/pmset", ["displaysleepnow"])
        case .openNotch: onOpenNotch?()
        case .runShortcut: if !arg.isEmpty { shell("/usr/bin/shortcuts", ["run", arg]) }
        case .openApp:
            if !arg.isEmpty {
                if arg.hasPrefix("/") { open(arg) } else { shell("/usr/bin/open", ["-a", arg]) }
            }
        }
    }

    private func open(_ path: String) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }

    private func shell(_ exe: String, _ args: [String]) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        try? p.run()
    }

    /// Triggers Dock-owned actions (Mission Control, Show Desktop…) without needing Accessibility access.
    private func dock(_ name: String, fallback: (() -> Void)? = nil) {
        typealias Fn = @convention(c) (CFString, Int32) -> Int32
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification") {
            _ = unsafeBitCast(sym, to: Fn.self)(name as CFString, 0)
        } else {
            fallback?()
        }
    }

    // For state dumps / QA
    var windowFrames: [String] { windows.values.map { NSStringFromRect($0.0.frame) } }
}
