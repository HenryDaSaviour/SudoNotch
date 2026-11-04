import AppKit
import ApplicationServices
import Combine

// MARK: - Keyboard lock (for cleaning your keyboard)

/// Swallows every key press until unlocked. Needs Accessibility access (macOS only lets apps that have it
/// intercept keyboard events). The mouse keeps working, so you can always click Unlock.
final class KeyboardLockService: ObservableObject {
    @Published private(set) var isLocked = false
    @Published private(set) var remaining: TimeInterval = 0
    @Published var needsPermission = false
    /// Auto-unlock after this many minutes; 0 means "until I unlock it".
    @Published var minutes: Int = {
        let v = UserDefaults.standard.object(forKey: "keyboardLockMinutes") as? Int
        return v ?? 5
    }() { didSet { UserDefaults.standard.set(minutes, forKey: "keyboardLockMinutes") } }

    var onLock: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var endDate: Date?
    private var timer: Timer?

    init() {
        // The password field on the lock screen must never be blocked, so release the keyboard whenever the
        // session stops being ours.
        let dist = DistributedNotificationCenter.default()
        dist.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.unlock() }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.unlock() }
        }
    }

    var timeString: String {
        guard endDate != nil else { return "ON" }
        let s = Int(ceil(remaining))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    func toggle() { isLocked ? unlock() : lock() }

    func lock() {
        guard !isLocked else { return }
        guard AXIsProcessTrusted() else {
            needsPermission = true
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            return
        }
        // keyDown, keyUp, flagsChanged and system-defined events (media / brightness / volume keys).
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue) | (1 << 14)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon, let t = Unmanaged<KeyboardLockService>.fromOpaque(refcon).takeUnretainedValue().tap {
                        CGEvent.tapEnable(tap: t, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                return nil   // swallow the key
            }, userInfo: ctx) else {
            needsPermission = true
            return
        }
        needsPermission = false
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)

        endDate = minutes > 0 ? Date().addingTimeInterval(Double(minutes) * 60) : nil
        remaining = Double(minutes) * 60
        isLocked = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        onLock?()
    }

    func unlock() {
        guard isLocked else { return }
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false); CFMachPortInvalidate(t) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil; source = nil
        timer?.invalidate(); timer = nil
        endDate = nil
        isLocked = false
    }

    private func tick() {
        guard let end = endDate else { return }
        let left = max(0, end.timeIntervalSinceNow)
        if Int(ceil(left)) != Int(ceil(remaining)) { remaining = left }
        if left <= 0 { unlock() }
    }
}

/// "Until 7:00 AM" helper shared by the lid and caffeinate timers (minutes == -1 means "use the clock time").
enum WakeTime {
    static func defaultTime() -> Date { Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date() }

    /// The next moment the clock shows this hour:minute (today if it's still ahead, otherwise tomorrow).
    static func next(_ t: Date) -> Date {
        let c = Calendar.current.dateComponents([.hour, .minute], from: t)
        return Calendar.current.nextDate(after: Date().addingTimeInterval(60), matching: c, matchingPolicy: .nextTime)
            ?? Date().addingTimeInterval(8 * 3600)
    }

    static func label(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
}

// MARK: - Stay awake with the lid closed

/// Wraps `pmset disablesleep`, which is what lets a MacBook keep running with its lid shut.
/// Changing it needs root. The very first time, macOS asks for an administrator password once so we can install a narrow
/// sudoers rule (/etc/sudoers.d/sudonotch) that lets this user run ONLY `pmset -a disablesleep 0|1` without a password.
/// After that, Turn on / Turn off / the auto-off timer never prompt. Settings has a button that removes the rule again.
final class LidService: ObservableObject {
    @Published private(set) var isAwakeWhenClosed = false
    @Published private(set) var isBusy = false
    @Published private(set) var hasPermission = false
    @Published private(set) var remaining: TimeInterval = 0
    @Published var minutes = 60          // -1 = until the clock time below
    @Published var wakeTime = WakeTime.defaultTime()
    @Published var message: String?

    private let queue = DispatchQueue(label: "sudonotch.lid")
    private static let flag = "/tmp/sudonotch-lid-\(getuid()).flag"   // holds the end time; the watcher quits if it changes
    private static let rulePath = "/etc/sudoers.d/sudonotch"
    private var endDate: Date?
    private var timer: Timer?

    init() { refresh() }

    var endString: String { endDate.map(WakeTime.label) ?? "" }

    var timeString: String {
        guard endDate != nil else { return "Awake" }
        let s = Int(ceil(remaining))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    func refresh() {
        queue.async { [weak self] in
            let value = Self.readSleepDisabled()
            let allowed = Self.canSudo()
            DispatchQueue.main.async {
                guard let self else { return }
                if self.hasPermission != allowed { self.hasPermission = allowed }
                self.apply(value)
            }
        }
    }

    private func apply(_ value: Bool) {
        if isBusy { return }
        if value {
            // The app was restarted while the watcher is still counting down: pick the countdown back up.
            if endDate == nil, let text = try? String(contentsOfFile: Self.flag, encoding: .utf8),
               let epoch = TimeInterval(text.trimmingCharacters(in: .whitespacesAndNewlines)), epoch > Date().timeIntervalSince1970 {
                endDate = Date(timeIntervalSince1970: epoch)
                remaining = max(0, epoch - Date().timeIntervalSince1970)
                startTimer()
            }
            if !isAwakeWhenClosed { isAwakeWhenClosed = true }
        } else {
            if isAwakeWhenClosed { isAwakeWhenClosed = false }
            if endDate != nil {
                clearSession()
                NotchModel.shared.showToast(symbol: "moon.zzz.fill", text: "Lid-closed: sleeps")
            }
        }
    }

    func toggle() { isAwakeWhenClosed ? turnOff() : turnOn() }

    func turnOn() {
        guard !isBusy else { return }
        isBusy = true; message = nil
        let end = minutes < 0 ? WakeTime.next(wakeTime) : Date().addingTimeInterval(Double(minutes * 60))
        let epoch = Int(end.timeIntervalSince1970)
        queue.async { [weak self] in
            var (ok, cancelled) = (Self.canSudo(), false)
            if !ok { (ok, cancelled) = Self.installRule() }
            if ok { try? String(epoch).write(toFile: Self.flag, atomically: true, encoding: .utf8); ok = Self.sudoPmset(on: true) }
            if ok { Self.startWatcher(epoch: epoch) }
            let state = Self.readSleepDisabled()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isBusy = false
                self.hasPermission = ok || self.hasPermission
                self.isAwakeWhenClosed = state
                if state {
                    self.endDate = end
                    self.remaining = end.timeIntervalSinceNow
                    self.startTimer()
                    NotchModel.shared.showToast(symbol: "laptopcomputer", text: "Lid-closed: awake")
                } else {
                    try? FileManager.default.removeItem(atPath: Self.flag)
                    if !cancelled { self.message = "Couldn't change it. Did the password prompt get dismissed?" }
                }
            }
        }
    }

    func turnOff() {
        guard !isBusy else { return }
        isBusy = true; message = nil
        queue.async { [weak self] in
            var (ok, cancelled) = (Self.canSudo(), false)
            if !ok { (ok, cancelled) = Self.installRule() }
            if ok { ok = Self.sudoPmset(on: false); if ok { try? FileManager.default.removeItem(atPath: Self.flag) } }
            let state = Self.readSleepDisabled()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isBusy = false
                self.isAwakeWhenClosed = state
                if !state {
                    self.clearSession()
                    NotchModel.shared.showToast(symbol: "moon.zzz.fill", text: "Lid-closed: sleeps")
                } else if !cancelled { self.message = "Couldn't change it. Did the password prompt get dismissed?" }
            }
        }
    }

    /// Deletes the sudoers rule again (asks for the password, since it's a system file).
    func removePermission() {
        guard !isBusy else { return }
        isBusy = true
        queue.async { [weak self] in
            Self.runAsAdmin("/bin/rm -f \(Self.rulePath) /etc/sudoers.d/pseudonotch")   // also the rule an older build (PseudoNotch) installed
            let allowed = Self.canSudo()
            DispatchQueue.main.async { self?.isBusy = false; self?.hasPermission = allowed }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func clearSession() {
        timer?.invalidate(); timer = nil
        endDate = nil; remaining = 0
    }

    private func tick() {
        guard let end = endDate else { timer?.invalidate(); timer = nil; return }
        let left = max(0, end.timeIntervalSinceNow)
        if Int(ceil(left)) != Int(ceil(remaining)) { remaining = left }
        if left <= 0 { refresh() }   // the watcher flips the setting right about now
    }

    // MARK: privileged bits

    /// True when the sudoers rule is in place (`-l` only asks, it never runs the command).
    private static func canSudo() -> Bool {
        run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"])
    }

    private static func sudoPmset(on: Bool) -> Bool {
        run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"])
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// Detached user-level watcher: turns sleep back on at `epoch`, or sooner if the flag file is removed. It does nothing
    /// if a newer session has replaced the flag, and it keeps working even if SudoNotch is quit meanwhile.
    private static func startWatcher(epoch: Int) {
        let script = "END=\(epoch); F=\(flag); " +
            "while [ $(date +%s) -lt $END ] && [ \"$(cat $F 2>/dev/null)\" = \"$END\" ]; do sleep 5; done; " +
            "if [ \"$(cat $F 2>/dev/null)\" = \"$END\" ] || [ ! -e $F ]; then /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0; fi"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        p.arguments = ["/bin/sh", "-c", script]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        try? p.run()
    }

    /// The one-time setup: asks macOS for the admin password and installs the narrow sudoers rule (checked with visudo first).
    private static func installRule() -> (ok: Bool, cancelled: Bool) {
        let user = NSUserName()
        guard user.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else { return (false, false) }
        let line = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
        let cmd = "T=$(/usr/bin/mktemp); /bin/echo '\(line)' > $T; " +
            "/usr/sbin/visudo -cf $T && /bin/mkdir -p /etc/sudoers.d && /usr/bin/install -m 0440 -o root -g wheel $T \(rulePath); R=$?; /bin/rm -f $T; exit $R"
        let result = runAsAdmin(cmd)
        return (result.ok && canSudo(), result.cancelled)
    }

    @discardableResult
    private static func runAsAdmin(_ command: String) -> (ok: Bool, cancelled: Bool) {
        var err: NSDictionary?
        NSAppleScript(source: "do shell script \"\(command)\" with administrator privileges")?.executeAndReturnError(&err)
        let cancelled = (err?[NSAppleScript.errorNumber] as? Int) == -128
        return (err == nil, cancelled)
    }

    private static func readSleepDisabled() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g"]
        let pipe = Pipe()
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(decoding: data, as: UTF8.self)
        guard let r = out.range(of: #"SleepDisabled\s+(\d)"#, options: .regularExpression) else { return false }
        return out[r].last == "1"
    }
}

// MARK: - Caffeinate

/// Runs the system `caffeinate` tool so the Mac (and its screen) stays awake without opening Terminal.
/// `-w` ties it to this app's pid, so it can never outlive SudoNotch.
final class CaffeinateService: ObservableObject {
    @Published private(set) var isOn = false
    @Published private(set) var remaining: TimeInterval = 0
    @Published var minutes = 0   // 0 = until turned off, -1 = until the clock time below
    @Published var wakeTime = WakeTime.defaultTime()

    private var process: Process?
    private var endDate: Date?
    private var timer: Timer?

    var endString: String { endDate.map(WakeTime.label) ?? "" }

    var timeString: String {
        guard endDate != nil else { return "On" }
        let s = Int(ceil(remaining))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    func toggle() { isOn ? stop() : start() }

    func start() {
        guard !isOn else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        var args = ["-d", "-i", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        if minutes != 0 {
            let end = minutes < 0 ? WakeTime.next(wakeTime) : Date().addingTimeInterval(Double(minutes * 60))
            args += ["-t", String(max(1, Int(end.timeIntervalSinceNow)))]
            endDate = end
        } else { endDate = nil }
        p.arguments = args
        p.terminationHandler = { [weak self, weak p] _ in
            DispatchQueue.main.async {
                guard let self, self.process === p else { return }
                self.finish(timedOut: true)
            }
        }
        guard (try? p.run()) != nil else { endDate = nil; return }
        process = p
        remaining = endDate.map { max(0, $0.timeIntervalSinceNow) } ?? 0
        isOn = true
        if endDate != nil { timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() } }
        NotchModel.shared.showToast(symbol: "cup.and.saucer.fill", text: "Staying awake")
    }

    func stop() {
        guard let p = process else { return }
        process = nil
        p.terminate()
        finish(timedOut: false)
    }

    private func finish(timedOut: Bool) {
        timer?.invalidate(); timer = nil
        process = nil; endDate = nil; remaining = 0; isOn = false
        NotchModel.shared.showToast(symbol: "moon.zzz.fill", text: timedOut ? "Awake time over" : "Sleep allowed")
    }

    private func tick() {
        guard let end = endDate else { return }
        let left = max(0, end.timeIntervalSinceNow)
        if Int(ceil(left)) != Int(ceil(remaining)) { remaining = left }
    }
}
