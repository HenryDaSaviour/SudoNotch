import AppKit

/// Makes our windows visible on the macOS lock screen.
///
/// The lock screen is drawn by loginwindow above every normal app window. The only way to appear over it is to
/// put windows into a private WindowServer "space" with the highest possible level (SkyLight, a private framework;
/// the same trick other notch apps use). Everything is looked up at runtime, so if Apple changes or removes these
/// functions the app still launches and the notch simply isn't shown on the lock screen.
///
/// While the screen is locked the notch is read-only: it never expands and takes no clicks, so nothing from the
/// clipboard, shelf or AirDrop tabs can be reached from the lock screen.
final class LockScreenSupport {
    static let shared = LockScreenSupport()

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private var connection: Int32 = 0
    private var space: Int32 = 0
    private var addWindows: AddWindows?
    private(set) var isAvailable = false
    private(set) var lastStatus: Int32 = -1

    /// Called on the main thread when the screen locks or unlocks.
    var onLockChange: ((Bool) -> Void)?

    func start() {
        observeLockState()
        guard AppSettings.shared.showOnLockScreen else { return }
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let h = dlopen(path, RTLD_LAZY),
              let mainConn = dlsym(h, "SLSMainConnectionID"),
              let create = dlsym(h, "SLSSpaceCreate"),
              let setLevel = dlsym(h, "SLSSpaceSetAbsoluteLevel"),
              let show = dlsym(h, "SLSShowSpaces"),
              let add = dlsym(h, "SLSSpaceAddWindowsAndRemoveFromSpaces") else {
            NSLog("SudoNotch: SkyLight lock screen support unavailable")
            return
        }
        connection = unsafeBitCast(mainConn, to: MainConnection.self)()
        space = unsafeBitCast(create, to: SpaceCreate.self)(connection, 1, 0)
        guard space != 0 else { return }
        _ = unsafeBitCast(setLevel, to: SpaceSetLevel.self)(connection, space, 2_147_483_647)
        _ = unsafeBitCast(show, to: ShowSpaces.self)(connection, [space] as CFArray)
        addWindows = unsafeBitCast(add, to: AddWindows.self)
        isAvailable = true
    }

    /// Moves a window into the lock-screen-visible space. Call once the window exists on screen.
    func show(_ window: NSWindow) {
        guard isAvailable, let addWindows, window.windowNumber > 0 else { return }
        lastStatus = addWindows(connection, space, [window.windowNumber] as CFArray, 7)
    }

    /// For QA: which spaces (and at what level) a window is in, as seen by this process.
    func debugSpaces(for window: NSWindow) -> [String] {
        guard isAvailable, let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let copy = dlsym(h, "SLSCopySpacesForWindows"), let level = dlsym(h, "SLSSpaceGetAbsoluteLevel") else { return ["unavailable"] }
        typealias CopySpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
        typealias GetLevel = @convention(c) (Int32, Int32) -> Int32
        var out: [String] = ["conn \(connection) ourSpace \(space) status \(lastStatus) win \(window.windowNumber)"]
        for mask in [1, 2, 4, 7] as [Int32] {
            let raw = unsafeBitCast(copy, to: CopySpaces.self)(connection, mask, [window.windowNumber] as CFArray)?.takeRetainedValue()
            let ids = (raw as? [NSNumber])?.map { $0.intValue } ?? []
            out.append("mask \(mask): \(ids.map { "\($0)@\(unsafeBitCast(level, to: GetLevel.self)(connection, Int32($0)))" })")
        }
        return out
    }

    private func observeLockState() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.onLockChange?(true)
        }
        center.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.onLockChange?(false)
        }
    }
}
