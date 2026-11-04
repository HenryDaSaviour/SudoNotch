import AppKit
import SwiftUI
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var statusText: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "SudoNotch starts when you log in"
        case .requiresApproval: return "Needs approval in System Settings → Login Items"
        case .notFound: return "Only works from the installed app (not `swift run`)"
        default: return "SudoNotch won't start automatically"
        }
    }
    static var runsFromInstalledLocation: Bool {
        let p = Bundle.main.bundlePath
        return p.hasPrefix("/Applications/") || p.hasPrefix(NSHomeDirectory() + "/Applications/")
    }
    static func set(_ on: Bool) {
        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
        catch { NSLog("SudoNotch login item error: \(error)") }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    let settings = AppSettings.shared
    let model = NotchModel.shared
    var notch: NotchWindowController!
    var corners: ScreenCornerController!
    var system: SystemEventsMonitor!
    var settingsWindow: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance.
        // Only the later launch yields, so two simultaneous launches can't both quit.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: {
               $0 != .current && ($0.launchDate ?? .distantFuture) < (NSRunningApplication.current.launchDate ?? .distantPast)
           }) {
            NSApp.terminate(nil); return
        }

        LockScreenSupport.shared.start()
        corners = ScreenCornerController()
        notch = NotchWindowController(model: model)
        corners.onOpenNotch = { [weak self] in self?.notch.setExpanded(true) }
        corners.start()
        notch.start()

        model.music.start()
        model.clipboard.start()
        system = SystemEventsMonitor(model: model)
        system.start()


        // First launch: open at login by default (the app is meant to live in the notch).
        // Skipped when running from the DMG / Downloads so we don't register a path that disappears.
        if !UserDefaults.standard.bool(forKey: "didFirstLaunch"), LoginItem.runsFromInstalledLocation {
            UserDefaults.standard.set(true, forKey: "didFirstLaunch")
            LoginItem.set(true)
        }
        if !LoginItem.runsFromInstalledLocation { warnNotInstalled() }
    }

    private func warnNotInstalled() {
        // Only nag for real .app launches (not `swift run`), once per launch.
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let alert = NSAlert()
        alert.messageText = "Move SudoNotch to Applications"
        alert.informativeText = "Drag SudoNotch into your Applications folder and open it from there, so it can start at login."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// No menu bar icon: relaunching the app (Spotlight / Applications) opens Settings instead.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: Settings window

    func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 780, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = NSColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1)
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: URL commands: sudonotch://expand, /collapse, /tab/music, /toast/Hello, /hud/volume/0.5,
    //                     /corner/topLeft, /anim/topRight/ripple, /settings, /dump

    @objc func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: s) else { return }
        var parts = [url.host ?? ""] + url.pathComponents.filter { $0 != "/" }
        parts = parts.map { $0.removingPercentEncoding ?? $0 }
        // Test hooks only respond when `defaults write dev.anvay.sudonotch debugHooks -bool true`, so web pages can't poke them.
        let debugOnly: Set<String> = ["tools", "keyboard", "locked", "dump", "snap", "animsnap", "settingsPage", "theme", "anim", "corner", "toast", "hud"]
        if debugOnly.contains(parts.first ?? ""), !UserDefaults.standard.bool(forKey: "debugHooks") { return }
        switch parts.first ?? "" {
        case "expand": notch.setExpanded(true)
        case "collapse": model.isPinned = false; notch.setExpanded(false)
        case "toggle": notch.toggle()
        case "pin": model.isPinned = true
        case "settings": showSettings()
        case "tab":
            if parts.count > 1, let t = NotchTab(rawValue: parts[1]) { model.tab = t; notch.setExpanded(true) }
        case "toast":
            if parts.count > 1 { model.showToast(symbol: "bell.fill", text: parts[1]) }
        case "hud":
            if parts.count > 2, let v = Double(parts[2]) {
                let kind: HUDKind = parts[1] == "brightness" ? .brightness : (parts[1] == "muted" ? .muted : .volume)
                model.showHUD(kind: kind, value: v)
            }
        case "corner":
            if parts.count > 1, let c = Corner(rawValue: parts[1]) { corners.fire(c, force: true) }
        case "anim":
            if parts.count > 2, let c = Corner(rawValue: parts[1]), let a = CornerAnimation(rawValue: parts[2]) {
                corners.windowPlay(a, at: c)
            }
        case "theme":   // theme/<corner>/<theme>
            if parts.count > 2, let c = Corner(rawValue: parts[1]), let th = CornerTheme(rawValue: parts[2]) {
                corners.windowPlayTheme(th, at: c)
            }
        case "animsnap":   // animsnap/<corner>/<theme>/<ms>  -> animation-<theme>.png
            if parts.count > 3, let c = Corner(rawValue: parts[1]), let th = CornerTheme(rawValue: parts[2]), let ms = Int(parts[3]) {
                let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/SudoNotch")
                corners.debugSnapTheme(c, th, afterMs: ms, to: dir.appendingPathComponent("animation-\(th.rawValue).png"))
            }
        case "until": model.lid.minutes = -1; model.caffeine.minutes = -1   // show the "Until…" time rows
        case "keyboard": if parts.count > 1 { parts[1] == "lock" ? model.keyboard.lock() : model.keyboard.unlock() }
        case "locked": notch.setLocked(parts.count > 1 && parts[1] == "1")   // simulate the lock screen
        case "notchanim":   // notchanim/on|off/<ms>: start expanding/collapsing, then snapshot <ms> later -> notch-<ms>.png
            if parts.count > 2, let ms = Int(parts[2]) {
                notch.setExpanded(parts[1] == "on")
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak self] in
                    self?.snapshot()
                    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/SudoNotch")
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent("notch-\(ms).png"))
                    try? FileManager.default.copyItem(at: dir.appendingPathComponent("notch.png"), to: dir.appendingPathComponent("notch-\(ms).png"))
                }
            }
        case "dump": dumpState()
        case "snap": snapshot()
        case "settingsPage":
            if parts.count > 1 { SettingsPage.debugInitial = SettingsPage(rawValue: parts[1]) }
            showSettings()
        default: break
        }
    }

    func dumpState() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/SudoNotch")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let state: [String: Any] = [
            "expanded": model.isExpanded, "pinned": model.isPinned, "tab": model.tab.rawValue,
            "collapsedSize": NSStringFromSize(model.collapsedSize), "expandedSize": NSStringFromSize(model.expandedSize),
            "baseSize": NSStringFromSize(model.baseSize),
            "panelFrame": NSStringFromRect(notch.panel.frame), "panelIgnoresMouse": notch.panel.ignoresMouseEvents,
            "panelAlpha": notch.panel.alphaValue, "cornerWindows": corners.windowFrames,
            "lastCornerEvent": corners.lastEvent, "transient": String(describing: model.transient),
            "musicSource": model.music.source?.rawValue ?? "none", "musicTitle": model.music.title,
            "loginItem": LoginItem.isEnabled, "locked": model.isLocked,
            "lockScreenAvailable": LockScreenSupport.shared.isAvailable, "panelSpaces": LockScreenSupport.shared.debugSpaces(for: notch.panel),
            "keyboardLocked": model.keyboard.isLocked, "keyboardNeedsPermission": model.keyboard.needsPermission,
            "lidAwake": model.lid.isAwakeWhenClosed, "lockScreenStatus": Int(LockScreenSupport.shared.lastStatus), "screen": NSStringFromRect(notch.screen?.frame ?? .zero),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("state.json"))
        }
    }
}

extension AppDelegate {
    /// Renders the app's own windows to PNGs (no Screen Recording permission needed).
    func snapshot() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/SudoNotch")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func png(_ draw: @escaping (CGRect) -> Void, size: NSSize, bg: NSColor, file: String) {
            let img = NSImage(size: size, flipped: false) { r in bg.setFill(); r.fill(); draw(r); return true }
            guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let data = rep.representation(using: .png, properties: [:]) else { return }
            try? data.write(to: dir.appendingPathComponent(file))
        }
        func viewDraw(_ v: NSView) -> (CGRect) -> Void {
            return { _ in
                guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
                v.cacheDisplay(in: v.bounds, to: rep)
                rep.draw(in: v.bounds)
            }
        }
        if let v = notch.panel.contentView {
            png(viewDraw(v), size: v.bounds.size, bg: NSColor(white: 0.85, alpha: 1), file: "notch.png")
        }
        if let v = settingsWindow?.contentView {
            png(viewDraw(v), size: v.bounds.size, bg: .black, file: "settings.png")
        }
        corners.snapshot(to: dir.appendingPathComponent("corners.png"))
    }
}

extension ScreenCornerController {
    func snapshot(to url: URL) {
        guard let v = NSScreen.screens.first.flatMap({ s in windowView(for: s) }), let layer = v.layer else { return }
        let size = v.bounds.size
        let img = NSImage(size: size, flipped: false) { r in
            NSColor(white: 0.85, alpha: 1).setFill(); r.fill()
            if let ctx = NSGraphicsContext.current?.cgContext { layer.render(in: ctx) }
            return true
        }
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
    }
}

extension ScreenCornerController {
    func windowPlayTheme(_ t: CornerTheme, at c: Corner) {
        guard let s = NSScreen.screens.first else { return }
        windowView(for: s)?.playTheme(t, at: c, color: settings.accentColor)
    }

    func windowPlay(_ a: CornerAnimation, at c: Corner) {
        guard let s = NSScreen.screens.first else { return }
        let id = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        playOn(display: id, a, c)
    }
}
