import AppKit
import IOKit.ps
import CoreAudio
import IOBluetooth
import CoreBluetooth

/// Battery, Bluetooth, volume and brightness events, surfaced as toasts / HUDs in the notch.
final class SystemEventsMonitor: NSObject, CBCentralManagerDelegate {
    private let model: NotchModel
    private let settings = AppSettings.shared
    private let startTime = Date()

    init(model: NotchModel) { self.model = model }

    func start() {
        startPower()
        startBluetooth()
        startVolume()
        startBrightness()
    }

    private var warmedUp: Bool { Date().timeIntervalSince(startTime) > 3 }

    // MARK: Power

    private var lastPowerState: String?
    private var lastPercent: Int?
    private var lastCharged = false

    private func startPower() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<SystemEventsMonitor>.fromOpaque(ctx).takeUnretainedValue().powerChanged()
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        powerChanged()
    }

    private func powerChanged() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let pct = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let state = d[kIOPSPowerSourceStateKey] as? String ?? ""
            let charged = d[kIOPSIsChargedKey] as? Bool ?? false
            defer { lastPowerState = state; lastPercent = pct; lastCharged = charged }
            guard settings.batteryAlerts, lastPowerState != nil else { continue }
            if state != lastPowerState {
                if state == kIOPSACPowerValue {
                    model.showToast(symbol: "bolt.fill", text: "Charging \(pct)%")
                } else {
                    model.showToast(symbol: "battery.50percent", text: "On battery \(pct)%")
                }
            } else if charged && !lastCharged {
                model.showToast(symbol: "battery.100percent.bolt", text: "Fully charged")
            } else if state == kIOPSBatteryPowerValue, pct <= 20, (lastPercent ?? 100) > 20 {
                model.showToast(symbol: "battery.25percent", text: "Battery low \(pct)%")
            }
        }
    }

    // MARK: Bluetooth

    private var connectNote: IOBluetoothUserNotification?
    private var disconnectNotes: [String: IOBluetoothUserNotification] = [:]
    private var cbManager: CBCentralManager?
    private var bluetoothStarted = false

    /// IOBluetooth blocks the calling thread until the user answers the Bluetooth permission prompt,
    /// so only touch it once access is already granted; otherwise ask via CoreBluetooth (non-blocking).
    private func startBluetooth() {
        switch CBManager.authorization {
        case .allowedAlways: registerBluetooth()
        case .notDetermined: cbManager = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        default: break
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if CBManager.authorization == .allowedAlways { registerBluetooth() }
    }

    private func registerBluetooth() {
        guard !bluetoothStarted else { return }
        bluetoothStarted = true
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(btConnected(_:device:)))
        if let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for d in paired where d.isConnected() { watchDisconnect(d) }
        }
    }

    private func watchDisconnect(_ d: IOBluetoothDevice) {
        guard let addr = d.addressString, disconnectNotes[addr] == nil else { return }
        disconnectNotes[addr] = d.register(forDisconnectNotification: self, selector: #selector(btDisconnected(_:device:)))
    }

    @objc private func btConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        watchDisconnect(device)
        guard settings.bluetoothAlerts, warmedUp else { return }
        model.showToast(symbol: symbol(for: device), text: device.name ?? "Bluetooth device")
    }

    @objc private func btDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        if let addr = device.addressString { disconnectNotes[addr]?.unregister(); disconnectNotes[addr] = nil }
        guard settings.bluetoothAlerts, warmedUp else { return }
        model.showToast(symbol: "bolt.slash.fill", text: "\(device.name ?? "Device") off")
    }

    private func symbol(for d: IOBluetoothDevice) -> String {
        let name = (d.name ?? "").lowercased()
        if name.contains("airpods") || name.contains("buds") || name.contains("headphone") { return "airpods" }
        if name.contains("keyboard") { return "keyboard" }
        if name.contains("mouse") || name.contains("trackpad") { return "computermouse" }
        return "wave.3.right"
    }

    // MARK: Volume

    private var volumeDevice: AudioObjectID = 0
    private var lastVolume: Float?
    private var lastMuted: Bool?

    private func startVolume() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            self?.attachVolumeListeners()
        }
        attachVolumeListeners()
    }

    private func attachVolumeListeners() {
        var dev = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr,
              dev != 0, dev != volumeDevice else { return }
        volumeDevice = dev
        lastVolume = readVolume(dev); lastMuted = readMute(dev)
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
                var a = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
                if AudioObjectHasProperty(dev, &a) {
                    AudioObjectAddPropertyListenerBlock(dev, &a, .main) { [weak self] _, _ in self?.volumeChanged() }
                }
            }
        }
    }

    private func readVolume(_ dev: AudioObjectID) -> Float? {
        var values: [Float] = []
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                               mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            guard AudioObjectHasProperty(dev, &a) else { continue }
            var v = Float32(0); var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr { values.append(v) }
            if element == kAudioObjectPropertyElementMain, !values.isEmpty { break }
        }
        return values.isEmpty ? nil : values.reduce(0, +) / Float(values.count)
    }

    private func readMute(_ dev: AudioObjectID) -> Bool? {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                           mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(dev, &a) else { return nil }
        var m = UInt32(0); var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &m) == noErr ? m != 0 : nil
    }

    private func volumeChanged() {
        let v = readVolume(volumeDevice), m = readMute(volumeDevice)
        defer { lastVolume = v; lastMuted = m }
        guard warmedUp, v != lastVolume || m != lastMuted else { return }
        if m == true { model.showHUD(kind: .muted, value: 0) }
        else { model.showHUD(kind: .volume, value: Double(v ?? 0)) }
    }

    // MARK: Brightness (built-in display, via DisplayServices if present)

    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private var getBrightness: GetBrightness?
    private var lastBrightness: Float?
    private var brightnessTimer: Timer?
    private var brightnessFailures = 0

    private func startBrightness() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let sym = dlsym(h, "DisplayServicesGetBrightness") else { return }
        getBrightness = unsafeBitCast(sym, to: GetBrightness.self)
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.pollBrightness() }
        t.tolerance = 0.5
        brightnessTimer = t
    }

    private func pollBrightness() {
        guard let getBrightness, settings.hudEnabled else { return }
        var b: Float = 0
        // Can fail while the lid is closed or an external display is main; just try again next tick.
        guard getBrightness(CGMainDisplayID(), &b) == 0 else { lastBrightness = nil; return }
        defer { lastBrightness = b }
        if let last = lastBrightness, abs(last - b) > 0.008, warmedUp {
            model.showHUD(kind: .brightness, value: Double(b))
        }
    }
}
