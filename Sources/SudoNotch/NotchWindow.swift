import AppKit
import SwiftUI
import Combine

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the transparent panel that hosts the notch UI and drives hover / drag expansion.
final class NotchWindowController {
    static let windowSize = CGSize(width: 720, height: 340)
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.9)   // settles quickly with just a hint of overshoot

    let model: NotchModel
    let panel: NotchPanel
    private let settings = AppSettings.shared
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var tick: Timer?
    private var bag = Set<AnyCancellable>()
    private var dragPasteboardCount = 0
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var screenFrame: CGRect = .zero          // cached so mouse events don't walk NSScreen.screens
    private var fullscreenHidden = false
    private var lastMenuBar: CGFloat?

    /// The built-in display with the hardware notch if there is one, otherwise the primary screen.
    var screen: NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first ?? NSScreen.main
    }

    init(model: NotchModel) {
        self.model = model
        panel = NotchPanel(contentRect: CGRect(origin: .zero, size: Self.windowSize),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        let host = NSHostingView(rootView: NotchRootView(model: model))
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: Self.windowSize)
        panel.contentView = host
    }

    func start() {
        reposition()
        applySettings()
        LockScreenSupport.shared.show(panel)
        LockScreenSupport.shared.onLockChange = { [weak self] locked in self?.setLocked(locked) }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] e in self?.handle(e) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in self?.handle(e); return e }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.reposition() }
        settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.reposition(); self?.refreshFullscreen(force: true); self?.applySettings() }
        }.store(in: &bag)
        // Full-screen changes arrive as events (new Space / new frontmost app), so no fast polling is needed.
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshFullscreen()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self?.refreshFullscreen() }   // the full-screen animation takes a moment
            }
        }
        // Slow safety net only; the timer is allowed to coalesce with other wakeups.
        let t = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            guard let self else { return }
            // A drop onto our own panel can swallow the mouse-up; don't stay "dragging" forever.
            if model.isFileDragActive, NSEvent.pressedMouseButtons == 0 { model.isFileDragActive = false }
            if model.isExpanded || model.isFileDragActive { mouseChanged() }
            refreshFullscreen()
        }
        t.tolerance = 2
        tick = t
        refreshFullscreen(force: true)
    }

    // MARK: Geometry

    func baseNotchSize(for s: NSScreen) -> CGSize {
        if s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            // Cover the physical cut-out exactly, including the flared top corners (the shape has ears of ~8pt each side).
            return CGSize(width: s.frame.width - l.width - r.width + 2 * 9, height: s.safeAreaInsets.top)
        }
        // Line the fake notch up with the bottom edge of the menu bar.
        let bar = s.frame.maxY - s.visibleFrame.maxY
        if bar > 1 { lastMenuBar = min(bar, 60) }   // remember it, so the notch doesn't change height while a full-screen app hides the bar
        let menuBar = lastMenuBar ?? NSStatusBar.system.thickness
        return CGSize(width: settings.notchWidth, height: settings.matchMenuBar ? menuBar : settings.notchHeight)
    }

    func reposition() {
        guard let s = screen else { return }
        let base = baseNotchSize(for: s)
        if model.baseSize != base { model.baseSize = base }
        let f = s.frame, w = Self.windowSize
        screenFrame = f
        let frame = CGRect(x: f.midX - w.width / 2, y: f.maxY - w.height, width: w.width, height: w.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    func shapeRect(_ size: CGSize) -> CGRect {
        let f = screenFrame
        return CGRect(x: f.midX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height)
    }

    var currentShapeRect: CGRect { shapeRect(model.currentSize) }

    /// Re-checks whether a full-screen app is up (a window-list query, so it only runs on events and a slow timer).
    func refreshFullscreen(force: Bool = false) {
        var now = false
        if settings.hideInFullscreen, let s = screen { now = Self.isFullScreen(on: s) }
        guard now != fullscreenHidden || force else { return }
        fullscreenHidden = now
        reposition()
        applySettings()
    }

    /// True while a full-screen app, video or game is covering the screen.
    /// Checks macOS's own full-screen flag, then falls back to "is there a normal window the size of the whole screen".
    static func isFullScreen(on s: NSScreen) -> Bool {
        if NSApp.currentSystemPresentationOptions.contains(.fullScreen) { return true }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let ours = ProcessInfo.processInfo.processIdentifier
        // CoreGraphics puts the origin at the top-left of the primary display; AppKit at the bottom-left.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? s.frame.height
        let f = s.frame
        let target = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != ours,
                  ((w[kCGWindowAlpha as String] as? Double) ?? 1) > 0.01,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: dict) else { continue }
            if abs(b.minX - target.minX) < 2, abs(b.minY - target.minY) < 2,
               b.width >= target.width - 2, b.height >= target.height - 2 { return true }
        }
        return false
    }

    func applySettings() {
        let sharing: NSWindow.SharingType = settings.hideFromSharing ? .none : .readOnly
        if panel.sharingType != sharing { panel.sharingType = sharing }
        if !settings.notchEnabled {
            if model.isExpanded { setExpanded(false) }
            model.isPinned = false
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
        let hide = fullscreenHidden && settings.hideInFullscreen && !model.isExpanded
        let alpha: CGFloat = hide ? 0 : 1
        if panel.alphaValue != alpha { panel.alphaValue = alpha }
        if model.isHidden != hide { model.isHidden = hide }
    }

    // MARK: Mouse

    private func hit(_ r: CGRect, _ p: CGPoint, pad: CGFloat) -> Bool {
        p.x >= r.minX - pad && p.x <= r.maxX + pad && p.y >= r.minY - pad && p.y <= r.maxY + pad
    }

    private func handle(_ e: NSEvent) {
        let drag = dragPasteboard
        switch e.type {
        case .leftMouseDown:
            dragPasteboardCount = drag.changeCount
        case .leftMouseDragged:
            if drag.changeCount != dragPasteboardCount,
               drag.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
                if !model.isFileDragActive { model.isFileDragActive = true }
            }
        case .leftMouseUp:
            if model.isFileDragActive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.model.isFileDragActive = false }
            }
        default: break
        }
        // Fast exit: the cursor is nowhere near the notch and nothing is open, so there's nothing to decide.
        if !model.isExpanded, !model.isFileDragActive {
            let p = NSEvent.mouseLocation
            if p.y < screenFrame.maxY - 70 || abs(p.x - screenFrame.midX) > 340 {
                if expandWork != nil { cancelExpand() }
                return
            }
        }
        mouseChanged()
    }

    /// Lock screen: collapse, unpin and ignore the mouse so nothing interactive is exposed.
    func setLocked(_ locked: Bool) {
        guard model.isLocked != locked else { return }
        if locked {
            model.isPinned = false
            model.isFileDragActive = false
            setExpanded(false)
        }
        model.isLocked = locked
        panel.ignoresMouseEvents = true
    }

    func mouseChanged() {
        guard !model.isLocked else { panel.ignoresMouseEvents = true; return }
        guard settings.notchEnabled, panel.alphaValue > 0 || model.isExpanded else {
            panel.ignoresMouseEvents = true
            return
        }
        let p = NSEvent.mouseLocation
        if model.isExpanded {
            let rect = currentShapeRect
            let inside = hit(rect, p, pad: 0)
            panel.ignoresMouseEvents = !inside
            if inside || hit(rect, p, pad: 8) || model.isPinned || model.isEditing || model.isFileDragActive {
                cancelCollapse()
            } else {
                scheduleCollapse()
            }
        } else {
            panel.ignoresMouseEvents = true
            let near = shapeRect(model.collapsedSize)
            if model.isFileDragActive {
                if hit(near, p, pad: 50) { model.tab = .shelf; setExpanded(true) }
            } else if settings.hoverToOpen, hit(near, p, pad: 2) {
                scheduleExpand()
            } else {
                cancelExpand()
            }
        }
    }

    private func scheduleExpand() {
        guard expandWork == nil else { return }
        let w = DispatchWorkItem { [weak self] in
            self?.expandWork = nil
            guard let self, hit(shapeRect(model.collapsedSize), NSEvent.mouseLocation, pad: 2) else { return }
            setExpanded(true)
        }
        expandWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.hoverDelay, execute: w)
    }

    private func cancelExpand() { expandWork?.cancel(); expandWork = nil }

    private func scheduleCollapse() {
        guard collapseWork == nil else { return }
        let w = DispatchWorkItem { [weak self] in
            self?.collapseWork = nil
            guard let self, model.isExpanded, !model.isPinned, !model.isEditing, !model.isFileDragActive,
                  !hit(currentShapeRect, NSEvent.mouseLocation, pad: 8) else { return }
            setExpanded(false)
        }
        collapseWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
    }

    private func cancelCollapse() { collapseWork?.cancel(); collapseWork = nil }

    func setExpanded(_ on: Bool) {
        guard model.isExpanded != on, !on || (settings.notchEnabled && !model.isLocked) else { return }
        cancelExpand(); cancelCollapse()
        if on {
            panel.alphaValue = 1
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else {
            model.isEditing = false
            panel.resignKey()
        }
        withAnimation(Self.spring) { model.isExpanded = on }
        panel.ignoresMouseEvents = !on
    }

    func toggle() { setExpanded(!model.isExpanded) }
}
