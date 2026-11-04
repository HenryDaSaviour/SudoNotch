import SwiftUI
import Combine

enum Corner: String, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }
    var title: String {
        switch self {
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        }
    }
}

enum CornerAction: String, CaseIterable, Identifiable {
    case none, missionControl, appExpose, showDesktop, apps, screenSaver, sleepDisplay, openNotch, runShortcut, openApp
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "Nothing"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .showDesktop: return "Show Desktop"
        case .apps: return "Apps / Launchpad"
        case .screenSaver: return "Start Screen Saver"
        case .sleepDisplay: return "Sleep Display"
        case .openNotch: return "Open the Notch"
        case .runShortcut: return "Run Shortcut…"
        case .openApp: return "Open App…"
        }
    }
    var needsArgument: Bool { self == .runShortcut || self == .openApp }
}

enum CornerAnimation: String, CaseIterable, Identifiable {
    case byAction, none, ripple, glow, neonArc, sparks, squeeze
    var id: String { rawValue }
    var title: String {
        switch self {
        case .byAction: return "Match the action"
        case .none: return "None"
        case .ripple: return "Ripple"
        case .glow: return "Glow burst"
        case .neonArc: return "Neon arcs"
        case .sparks: return "Sparks"
        case .squeeze: return "Corner squeeze"
        }
    }
}

/// UserDefaults-backed property that also fires `objectWillChange` on the owning ObservableObject.
@propertyWrapper
struct Pref<Value> {
    let key: String
    let defaultValue: Value

    init(_ key: String, _ defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }

    @available(*, unavailable, message: "Only usable inside ObservableObject classes")
    var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }

    static subscript<Instance: ObservableObject>(
        _enclosingInstance instance: Instance,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<Instance, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<Instance, Pref>
    ) -> Value where Instance.ObjectWillChangePublisher == ObservableObjectPublisher {
        get {
            let s = instance[keyPath: storageKeyPath]
            return (UserDefaults.standard.object(forKey: s.key) as? Value) ?? s.defaultValue
        }
        set {
            instance.objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: instance[keyPath: storageKeyPath].key)
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // Notch
    @Pref("notchEnabled", true) var notchEnabled: Bool
    @Pref("notchWidth", 190.0) var notchWidth: Double
    @Pref("notchHeight", 32.0) var notchHeight: Double
    @Pref("matchMenuBar", true) var matchMenuBar: Bool
    @Pref("hoverToOpen", true) var hoverToOpen: Bool
    @Pref("hoverDelay", 0.12) var hoverDelay: Double
    @Pref("hideInFullscreen", true) var hideInFullscreen: Bool
    @Pref("showOnLockScreen", true) var showOnLockScreen: Bool
    @Pref("hideFromSharing", false) var hideFromSharing: Bool
    @Pref("showMusicActivity", true) var showMusicActivity: Bool
    @Pref("batteryAlerts", true) var batteryAlerts: Bool
    @Pref("bluetoothAlerts", true) var bluetoothAlerts: Bool
    @Pref("hudEnabled", true) var hudEnabled: Bool
    @Pref("lastTab", "music") var lastTab: String

    // Corners
    @Pref("cornersEnabled", true) var cornersEnabled: Bool
    @Pref("cornerRadius", 12.0) var cornerRadius: Double
    @Pref("hotCornersEnabled", true) var hotCornersEnabled: Bool
    @Pref("hotCornerSize", 5.0) var hotCornerSize: Double
    @Pref("hotCornerDwell", 0.05) var hotCornerDwell: Double
    /// "system": macOS runs the corner actions from Desktop & Dock settings, we only animate. "custom": we run our own.
    @Pref("hotCornerSource", "system") var hotCornerSource: String
    @Pref("accentHex", "#0A84FF") var accentHex: String


    private static let defaultActions: [Corner: (CornerAction, CornerAnimation)] = [
        .topLeft: (.missionControl, .byAction),
        .topRight: (.showDesktop, .byAction),
        .bottomLeft: (.apps, .byAction),
        .bottomRight: (.openNotch, .byAction),
    ]

    func action(for c: Corner) -> CornerAction {
        let raw = UserDefaults.standard.string(forKey: "hc.\(c.rawValue).action")
        return raw.flatMap(CornerAction.init(rawValue:)) ?? Self.defaultActions[c]!.0
    }
    func animation(for c: Corner) -> CornerAnimation {
        let raw = UserDefaults.standard.string(forKey: "hc.\(c.rawValue).anim")
        return raw.flatMap(CornerAnimation.init(rawValue:)) ?? Self.defaultActions[c]!.1
    }
    var usesSystemHotCorners: Bool { hotCornerSource != "custom" }

    /// The action code macOS has stored for this corner (0 = nothing).
    func systemActionCode(for c: Corner) -> Int {
        let short: String
        switch c { case .topLeft: short = "tl"; case .topRight: short = "tr"; case .bottomLeft: short = "bl"; case .bottomRight: short = "br" }
        guard let v = UserDefaults(suiteName: "com.apple.dock")?.object(forKey: "wvous-\(short)-corner") as? Int else {
            return c == .bottomRight ? 14 : 0   // macOS ships with Quick Note on the bottom-right corner
        }
        return v <= 1 ? 0 : v
    }

    /// What macOS itself will do for this corner (System Settings → Desktop & Dock → Hot Corners).
    func systemActionName(for c: Corner) -> String {
        switch systemActionCode(for: c) {
        case 2: return "Mission Control"
        case 3: return "Application Windows"
        case 4: return "Desktop"
        case 5: return "Start Screen Saver"
        case 6: return "Disable Screen Saver"
        case 7: return "Dashboard"
        case 10: return "Put Display to Sleep"
        case 11: return "Launchpad"
        case 12: return "Notification Center"
        case 13: return "Lock Screen"
        case 14: return "Quick Note"
        default: return "Nothing"
        }
    }

    func argument(for c: Corner) -> String {
        UserDefaults.standard.string(forKey: "hc.\(c.rawValue).arg") ?? ""
    }

    func binding(_ key: String, _ def: String) -> Binding<String> {
        Binding(
            get: { UserDefaults.standard.string(forKey: key) ?? def },
            set: { [weak self] in
                self?.objectWillChange.send()
                UserDefaults.standard.set($0, forKey: key)
            }
        )
    }
    func actionBinding(_ c: Corner) -> Binding<CornerAction> {
        let b = binding("hc.\(c.rawValue).action", action(for: c).rawValue)
        return Binding(get: { self.action(for: c) }, set: { b.wrappedValue = $0.rawValue })
    }
    func animationBinding(_ c: Corner) -> Binding<CornerAnimation> {
        let b = binding("hc.\(c.rawValue).anim", animation(for: c).rawValue)
        return Binding(get: { self.animation(for: c) }, set: { b.wrappedValue = $0.rawValue })
    }
    func argumentBinding(_ c: Corner) -> Binding<String> { binding("hc.\(c.rawValue).arg", "") }

    var accentColor: NSColor { NSColor(hex: accentHex) ?? .systemBlue }
    var accentBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: self.accentColor) },
            set: { self.accentHex = NSColor($0).hexString }
        )
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}
