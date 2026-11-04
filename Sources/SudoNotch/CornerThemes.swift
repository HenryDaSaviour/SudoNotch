import AppKit
import QuartzCore

/// Hot corner animations themed after what the corner does (Quick Note, Mission Control, Launchpad…).
enum CornerTheme: String, CaseIterable {
    case quickNote, missionControl, appWindows, desktop, screenSaver, launchpad
    case lockScreen, sleepDisplay, generic
}

extension CornerView {
    /// +1/-1 per axis pointing from the screen corner into the screen.
    func inward(_ c: Corner) -> CGPoint {
        CGPoint(x: (c == .topLeft || c == .bottomLeft) ? 1 : -1, y: (c == .bottomLeft || c == .bottomRight) ? 1 : -1)
    }

    func playTheme(_ t: CornerTheme, at c: Corner, color: NSColor) {
        switch t {
        case .quickNote: quickNote(c)
        case .missionControl: missionControl(c)
        case .appWindows: appWindows(c)
        case .desktop: showDesktop(c)
        case .screenSaver: screenSaver(c)
        case .launchpad: launchpad(c)
        case .lockScreen: lockScreen(c)
        case .sleepDisplay: sleepDisplay(c)
        case .generic: play(.neonArc, at: c, color: color)
        }
    }

    // MARK: Helpers

    private var scale: CGFloat { window?.backingScaleFactor ?? 2 }

    /// Opacity envelope: fade in, hold, fade out over `duration`.
    private func envelope(_ duration: Double, fadeIn: Double = 0.12, fadeOut: Double = 0.3) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [0, 1, 1, 0]
        a.keyTimes = [0, NSNumber(value: fadeIn / duration), NSNumber(value: 1 - fadeOut / duration), 1]
        a.duration = duration
        return a
    }

    private func run(_ layer: CALayer, _ anims: [CAAnimation], duration: Double, delay: Double = 0) {
        layer.opacity = 0
        let g = CAAnimationGroup()
        g.animations = anims
        g.duration = duration
        g.beginTime = CACurrentMediaTime() + delay
        g.fillMode = .backwards
        layer.add(g, forKey: "theme")
        add(layer, removeAfter: duration + delay + 0.3)
    }

    private func symbol(_ name: String, size: CGFloat, color: NSColor = .white) -> CALayer? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
              let img = base.withSymbolConfiguration(.init(pointSize: size, weight: .semibold)) else { return nil }
        let tinted = NSImage(size: img.size, flipped: false) { r in
            img.draw(in: r); color.set(); r.fill(using: .sourceAtop); return true
        }
        let l = CALayer()
        l.bounds = CGRect(origin: .zero, size: img.size)
        l.contents = tinted
        l.contentsGravity = .resizeAspect
        l.contentsScale = scale
        return l
    }

    private func miniWindow(_ size: CGSize, tint: NSColor = .white) -> CALayer {
        let w = CALayer()
        w.bounds = CGRect(origin: .zero, size: size)
        w.backgroundColor = NSColor(white: 0.12, alpha: 0.82).cgColor
        w.borderColor = tint.withAlphaComponent(0.9).cgColor
        w.borderWidth = 1.5
        w.cornerRadius = 9
        w.shadowColor = NSColor.black.cgColor; w.shadowOpacity = 0.5; w.shadowRadius = 8; w.shadowOffset = CGSize(width: 0, height: -3)
        let bar = CALayer()
        bar.frame = CGRect(x: 0, y: size.height - 14, width: size.width, height: 14)
        bar.backgroundColor = tint.withAlphaComponent(0.22).cgColor
        bar.cornerRadius = 9
        bar.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        w.addSublayer(bar)
        for (i, col) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            let dot = CALayer()
            dot.frame = CGRect(x: 7 + CGFloat(i) * 9, y: size.height - 10, width: 6, height: 6)
            dot.cornerRadius = 3; dot.backgroundColor = col.cgColor
            w.addSublayer(dot)
        }
        return w
    }

    private func move(_ from: CGPoint, _ to: CGPoint, duration: Double, spring: Bool = false) -> CAAnimation {
        let a = CABasicAnimation(keyPath: "position")
        a.fromValue = NSValue(point: from); a.toValue = NSValue(point: to)
        a.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
        a.duration = duration
        return a
    }

    private func grow(_ values: [CGFloat], times: [Double], keyPath: String = "transform.scale", duration: Double) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: keyPath)
        a.values = values; a.keyTimes = times.map { NSNumber(value: $0) }; a.duration = duration
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return a
    }

    // MARK: Quick Note — a yellow note curls out of the corner

    private func quickNote(_ c: Corner) {
        let d = inward(c), pt = point(of: c)
        let size = CGSize(width: 176, height: 156)
        let note = CALayer()
        note.bounds = CGRect(origin: .zero, size: size)
        note.anchorPoint = CGPoint(x: d.x > 0 ? 0 : 1, y: d.y > 0 ? 0 : 1)
        note.position = pt
        note.backgroundColor = NSColor(srgbRed: 1, green: 0.85, blue: 0.30, alpha: 1).cgColor
        note.cornerRadius = 14
        note.shadowColor = NSColor.black.cgColor; note.shadowOpacity = 0.45; note.shadowRadius = 14; note.shadowOffset = CGSize(width: 0, height: -4)
        for i in 0..<4 {
            let bar = CALayer()
            let w: CGFloat = i == 0 ? 96 : (i == 3 ? 70 : size.width - 40)
            bar.frame = CGRect(x: 20, y: size.height - 40 - CGFloat(i) * 26, width: w, height: i == 0 ? 9 : 6)
            bar.backgroundColor = NSColor.black.withAlphaComponent(i == 0 ? 0.45 : 0.22).cgColor
            bar.cornerRadius = 3
            note.addSublayer(bar)
        }
        // Dog-ear on the corner facing into the screen.
        let cx: CGFloat = d.x > 0 ? size.width : 0, cy: CGFloat = d.y > 0 ? size.height : 0
        let fold = CAShapeLayer()
        let tri = CGMutablePath()
        tri.move(to: CGPoint(x: cx, y: cy)); tri.addLine(to: CGPoint(x: cx - d.x * 38, y: cy)); tri.addLine(to: CGPoint(x: cx, y: cy - d.y * 38)); tri.closeSubpath()
        fold.path = tri
        fold.fillColor = NSColor(srgbRed: 0.86, green: 0.66, blue: 0.12, alpha: 1).cgColor
        note.addSublayer(fold)

        let dur = 1.35
        let pop = grow([0.04, 1.07, 1, 1, 0.04], times: [0, 0.2, 0.3, 0.78, 1], duration: dur)
        let tilt = grow([0.22 * d.x * d.y, -0.04 * d.x * d.y, 0, 0, 0.22 * d.x * d.y], times: [0, 0.2, 0.3, 0.78, 1],
                        keyPath: "transform.rotation.z", duration: dur)
        run(note, [pop, tilt, envelope(dur, fadeIn: 0.06, fadeOut: 0.2)], duration: dur)
    }

    // MARK: Mission Control — windows spread out into a grid

    private func missionControl(_ c: Corner) {
        let d = inward(c), pt = point(of: c)
        let centre = CGPoint(x: pt.x + d.x * 170, y: pt.y + d.y * 130)
        let offsets = [CGPoint(x: -62, y: 42), CGPoint(x: 62, y: 42), CGPoint(x: -62, y: -42), CGPoint(x: 62, y: -42)]
        let dur = 1.3
        for (i, o) in offsets.enumerated() {
            let w = miniWindow(CGSize(width: 108, height: 72))
            let end = CGPoint(x: centre.x + o.x, y: centre.y + o.y)
            w.position = end
            let slide = move(centre, end, duration: 0.45)
            slide.beginTime = 0
            let pop = grow([0.35, 1, 1], times: [0, 0.35, 1], duration: dur)
            run(w, [slide, pop, envelope(dur, fadeIn: 0.1, fadeOut: 0.3)], duration: dur, delay: Double(i) * 0.04)
        }
    }

    // MARK: App Exposé — a cascade of windows from the same app

    private func appWindows(_ c: Corner) {
        let d = inward(c), pt = point(of: c)
        let dur = 1.25
        for i in 0..<3 {
            let w = miniWindow(CGSize(width: 126, height: 84))
            let end = CGPoint(x: pt.x + d.x * (110 + CGFloat(i) * 46), y: pt.y + d.y * (92 + CGFloat(i) * 34))
            w.position = end
            let slide = move(pt, end, duration: 0.4)
            let pop = grow([0.3, 1, 1], times: [0, 0.3, 1], duration: dur)
            run(w, [slide, pop, envelope(dur, fadeIn: 0.1, fadeOut: 0.3)], duration: dur, delay: Double(i) * 0.08)
        }
    }

    // MARK: Show Desktop — windows slide off toward the screen edge

    private func showDesktop(_ c: Corner) {
        let d = inward(c), pt = point(of: c)
        let dur = 1.1
        for i in 0..<3 {
            let w = miniWindow(CGSize(width: 120, height: 80))
            let start = CGPoint(x: pt.x + d.x * (160 + CGFloat(i) * 26), y: pt.y + d.y * (80 + CGFloat(i) * 54))
            let end = CGPoint(x: pt.x - d.x * 140, y: start.y)
            w.position = start
            let slide = CABasicAnimation(keyPath: "position")
            slide.fromValue = NSValue(point: start); slide.toValue = NSValue(point: end)
            slide.timingFunction = CAMediaTimingFunction(controlPoints: 0.6, 0, 0.9, 0.5)
            slide.beginTime = 0.2; slide.duration = 0.8; slide.fillMode = .both
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.15, 0.7, 1]; fade.duration = dur
            run(w, [slide, fade], duration: dur, delay: Double(i) * 0.07)
        }
    }

    // MARK: Screen Saver — the screen dims and stars twinkle

    private func screenSaver(_ c: Corner) {
        let d = inward(c), pt = point(of: c)
        vignette(at: pt, radius: 420, alpha: 0.55, duration: 1.5)
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<22 {
            let r = CGFloat.random(in: 50...300, using: &rng), a = CGFloat.random(in: 0.05...1.5, using: &rng)
            let s = CGFloat.random(in: 2...4.5, using: &rng)
            let star = CAShapeLayer()
            star.path = CGPath(ellipseIn: CGRect(x: -s, y: -s, width: 2 * s, height: 2 * s), transform: nil)
            star.fillColor = NSColor.white.cgColor
            star.shadowColor = NSColor.white.cgColor; star.shadowRadius = 5; star.shadowOpacity = 1; star.shadowOffset = .zero
            star.position = CGPoint(x: pt.x + d.x * r * cos(a), y: pt.y + d.y * r * sin(a))
            let dur = 1.4
            let twinkle = CAKeyframeAnimation(keyPath: "opacity")
            twinkle.values = [0, 1, 0.25, 1, 0]; twinkle.keyTimes = [0, 0.25, 0.5, 0.75, 1]; twinkle.duration = dur
            let pulse = grow([0.3, 1.2, 0.6, 1.1, 0.3], times: [0, 0.25, 0.5, 0.75, 1], duration: dur)
            run(star, [twinkle, pulse], duration: dur, delay: Double.random(in: 0...0.45, using: &rng))
        }
    }

    /// Soft dark radial wash growing from a point.
    private func vignette(at pt: CGPoint, radius: CGFloat, alpha: CGFloat, duration: Double) {
        let g = CAGradientLayer()
        g.type = .radial
        g.colors = [NSColor.black.withAlphaComponent(alpha).cgColor, NSColor.black.withAlphaComponent(alpha * 0.4).cgColor, NSColor.clear.cgColor]
        g.locations = [0, 0.55, 1]
        g.startPoint = CGPoint(x: 0.5, y: 0.5); g.endPoint = CGPoint(x: 1, y: 1)
        g.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        g.position = pt
        let grow = CABasicAnimation(keyPath: "transform.scale"); grow.fromValue = 0.2; grow.toValue = 1
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut); grow.duration = duration * 0.5
        run(g, [grow, envelope(duration, fadeIn: 0.25, fadeOut: 0.4)], duration: duration)
    }

    // MARK: Launchpad — a grid of app tiles pops in

    private func launchpad(_ c: Corner) {
        let d = inward(c), pt = point(of: c)
        let tile: CGFloat = 28, gap: CGFloat = 10
        let origin = CGPoint(x: pt.x + d.x * 40, y: pt.y + d.y * 40)
        let dur = 1.25
        for ix in 0..<3 {
            for iy in 0..<3 {
                let l = CAShapeLayer()
                l.path = CGPath(roundedRect: CGRect(x: -tile / 2, y: -tile / 2, width: tile, height: tile), cornerWidth: 8, cornerHeight: 8, transform: nil)
                let hue = CGFloat(ix * 3 + iy) / 9
                l.fillColor = NSColor(hue: hue, saturation: 0.65, brightness: 1, alpha: 1).cgColor
                l.shadowColor = NSColor.black.cgColor; l.shadowOpacity = 0.4; l.shadowRadius = 4; l.shadowOffset = CGSize(width: 0, height: -2)
                l.position = CGPoint(x: origin.x + d.x * (tile / 2 + CGFloat(ix) * (tile + gap)),
                                     y: origin.y + d.y * (tile / 2 + CGFloat(iy) * (tile + gap)))
                let pop = grow([0, 1.18, 1, 1, 0.6], times: [0, 0.22, 0.32, 0.8, 1], duration: dur)
                run(l, [pop, envelope(dur, fadeIn: 0.08, fadeOut: 0.25)], duration: dur, delay: Double(ix + iy) * 0.05)
            }
        }
    }

    // MARK: Lock Screen — a padlock snaps shut

    private func lockScreen(_ c: Corner) {
        let d = inward(c), pt = point(of: c)
        let centre = CGPoint(x: pt.x + d.x * 86, y: pt.y + d.y * 86)
        let dur = 1.4
        let disc = CAShapeLayer()
        disc.path = CGPath(ellipseIn: CGRect(x: -44, y: -44, width: 88, height: 88), transform: nil)
        disc.fillColor = NSColor(white: 0.08, alpha: 0.88).cgColor
        disc.strokeColor = NSColor.white.withAlphaComponent(0.25).cgColor
        disc.lineWidth = 1.5
        disc.position = centre
        let pop = grow([0.2, 1.12, 1, 1, 0.4], times: [0, 0.22, 0.3, 0.8, 1], duration: dur)
        run(disc, [pop, envelope(dur, fadeIn: 0.08, fadeOut: 0.25)], duration: dur)

        if let open = symbol("lock.open.fill", size: 38), let closed = symbol("lock.fill", size: 38) {
            for (l, vals, times) in [(open, [0, 1, 1, 0, 0] as [CGFloat], [0, 0.15, 0.36, 0.4, 1] as [Double]),
                                     (closed, [0, 0, 1, 1, 0] as [CGFloat], [0, 0.36, 0.4, 0.8, 1] as [Double])] {
                l.position = centre
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = vals; fade.keyTimes = times.map { NSNumber(value: $0) }; fade.duration = dur
                let snap = grow([1, 1, 1.25, 1, 1], times: [0, 0.36, 0.42, 0.55, 1], duration: dur)
                run(l, [fade, snap], duration: dur)
            }
        }
    }

    // MARK: Sleep Display — the corner dims and a moon appears

    private func sleepDisplay(_ c: Corner) {
        let d = inward(c), pt = point(of: c)
        vignette(at: pt, radius: 620, alpha: 0.7, duration: 1.5)
        if let moon = symbol("moon.zzz.fill", size: 44, color: NSColor(white: 1, alpha: 0.92)) {
            moon.position = CGPoint(x: pt.x + d.x * 84, y: pt.y + d.y * 84)
            let dur = 1.5
            let float = grow([0.7, 1, 1.04, 1, 0.9], times: [0, 0.25, 0.5, 0.75, 1], duration: dur)
            run(moon, [float, envelope(dur, fadeIn: 0.2, fadeOut: 0.35)], duration: dur)
        }
    }
}

// MARK: - Controller glue + debugging

extension ScreenCornerController {
    /// What a corner does decides how it animates.
    func theme(for c: Corner) -> CornerTheme {
        if settings.usesSystemHotCorners {
            switch settings.systemActionCode(for: c) {
            case 2: return .missionControl
            case 3: return .appWindows
            case 4: return .desktop
            case 5, 6: return .screenSaver
            case 10: return .sleepDisplay
            case 11: return .launchpad
            case 13: return .lockScreen
            case 14: return .quickNote
            default: return .generic
            }
        }
        switch settings.action(for: c) {
        case .missionControl: return .missionControl
        case .appExpose: return .appWindows
        case .showDesktop: return .desktop
        case .apps: return .launchpad
        case .screenSaver: return .screenSaver
        case .sleepDisplay: return .sleepDisplay
        default: return .generic
        }
    }

    /// Plays a themed animation and writes what it looks like `ms` milliseconds in (for QA).
    func debugSnapTheme(_ c: Corner, _ t: CornerTheme, afterMs ms: Int, to url: URL) {
        guard let s = NSScreen.screens.first, let v = windowView(for: s), let root = v.layer else { return }
        v.playTheme(t, at: c, color: settings.accentColor)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) {
            let size = v.bounds.size
            let img = NSImage(size: size, flipped: false) { r in
                NSColor(white: 0.82, alpha: 1).setFill(); r.fill()
                if let ctx = NSGraphicsContext.current?.cgContext { (root.presentation() ?? root).render(in: ctx) }
                return true
            }
            if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
        }
    }
}
