import AppKit
import SwiftUI
import Combine

// MARK: - Music

final class MusicService: ObservableObject {
    enum Source: String {
        case music = "Music", spotify = "Spotify"
        var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
    }

    @Published var title = ""
    @Published var artist = ""
    @Published var isPlaying = false
    @Published var duration: Double = 0
    @Published var artwork: NSImage?
    @Published var source: Source?
    @Published var runningSources: [Source] = []

    private var basePosition: Double = 0
    private var stamp = Date()
    private var timer: Timer?
    private var polling = false
    private var artworkKey = ""
    private let queue = DispatchQueue(label: "sudonotch.music")
    private var scripts: [String: NSAppleScript] = [:]

    var hasTrack: Bool { source != nil && !title.isEmpty }

    var livePosition: Double {
        let p = isPlaying ? basePosition + Date().timeIntervalSince(stamp) : basePosition
        return duration > 0 ? min(p, duration) : p
    }

    func start() {
        // Music and Spotify announce every track / play-pause change, and apps launching or quitting are announced too,
        // so we only look when something happened. The timer is a slow safety net (e.g. for scrubbing).
        let dnc = DistributedNotificationCenter.default()
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            dnc.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in self?.pollSoon() }
        }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                if Source.allCases.contains(where: { $0.bundleID == id }) { self?.pollSoon() }
            }
        }
        let t = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = 4
        timer = t
        poll()
    }

    private var pollWork: DispatchWorkItem?
    private func pollSoon() {
        pollWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.poll() }
        pollWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: w)
    }

    func poll() {
        guard !polling else { return }
        let running = Source.allCases.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty }
        if running != runningSources { runningSources = running }
        guard !running.isEmpty else {
            if source != nil { clear() }
            return
        }
        polling = true
        queue.async { [weak self] in
            guard let self else { return }
            var best: (Source, [String])?
            for s in running {
                guard let fields = self.fetch(s) else { continue }
                if best == nil || fields[0] == "playing" { best = (s, fields) }
                if fields[0] == "playing" { break }
            }
            DispatchQueue.main.async {
                self.polling = false
                if let (s, f) = best { self.apply(s, f) } else if self.source != nil { self.clear() }
            }
        }
    }

    private func clear() {
        source = nil; title = ""; artist = ""; isPlaying = false; artwork = nil; duration = 0; artworkKey = ""
    }

    private func apply(_ s: Source, _ f: [String]) {
        let playing = f[0] == "playing"
        let newTitle = f[1], newArtist = f[2]
        var dur = Double(f[3].replacingOccurrences(of: ",", with: ".")) ?? 0
        if s == .spotify { dur /= 1000 }
        let pos = Double(f[4].replacingOccurrences(of: ",", with: ".")) ?? 0
        if source != s { source = s }
        if title != newTitle { title = newTitle }
        if artist != newArtist { artist = newArtist }
        if isPlaying != playing { isPlaying = playing }
        if duration != dur { duration = dur }
        basePosition = pos; stamp = Date()   // position is interpolated by the seek bar, so no redraw is needed for it
        let key = "\(s.rawValue)|\(newTitle)|\(newArtist)"
        if key != artworkKey {
            artworkKey = key
            artwork = nil
            loadArtwork(s, key: key, spotifyURL: f.count > 5 ? f[5] : "")
        }
    }

    private func loadArtwork(_ s: Source, key: String, spotifyURL: String) {
        if s == .spotify {
            guard let url = URL(string: spotifyURL), !spotifyURL.isEmpty else { return }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async { if self?.artworkKey == key { self?.artwork = img } }
            }.resume()
        } else {
            queue.async { [weak self] in
                guard let self else { return }
                let src = "tell application \"Music\" to get raw data of artwork 1 of current track"
                let desc = self.run(src)
                guard let data = desc?.data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async { if self.artworkKey == key { self.artwork = img } }
            }
        }
    }

    private func run(_ source: String) -> NSAppleEventDescriptor? {
        let script = scripts[source] ?? NSAppleScript(source: source)
        scripts[source] = script
        var err: NSDictionary?
        let r = script?.executeAndReturnError(&err)
        if let err { NSLog("SudoNotch AppleScript error: \(err)") }
        return r
    }

    private func fetch(_ s: Source) -> [String]? {
        let src: String
        switch s {
        case .music:
            src = """
            if application "Music" is not running then return "stopped"
            tell application "Music"
              if player state is stopped then return "stopped"
              set t to "" 
              set a to ""
              set d to 0
              try
                set t to name of current track
              end try
              try
                set a to artist of current track
              end try
              try
                set d to duration of current track
              end try
              return (player state as text) & "|||" & t & "|||" & a & "|||" & d & "|||" & player position
            end tell
            """
        case .spotify:
            src = """
            if application "Spotify" is not running then return "stopped"
            tell application "Spotify"
              if player state is stopped then return "stopped"
              set t to ""
              set a to ""
              set d to 0
              set u to ""
              try
                set t to name of current track
              end try
              try
                set a to artist of current track
              end try
              try
                set d to duration of current track
              end try
              try
                set u to artwork url of current track
              end try
              return (player state as text) & "|||" & t & "|||" & a & "|||" & d & "|||" & player position & "|||" & u
            end tell
            """
        }
        guard let out = run(src)?.stringValue, out != "stopped" else { return nil }
        let parts = out.components(separatedBy: "|||")
        return parts.count >= 5 ? parts : nil
    }

    // Controls
    private func command(_ cmd: String) {
        guard let s = source else { return }
        queue.async { [weak self] in
            // Never relaunch a player the user has quit in the meantime.
            _ = self?.run("if application \"\(s.rawValue)\" is running then tell application \"\(s.rawValue)\" to \(cmd)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.poll() }
        }
    }
    func togglePlay() { command("playpause"); isPlaying.toggle(); basePosition = livePosition; stamp = Date() }
    func next() { command("next track") }
    func previous() { command("previous track") }
    func seek(to seconds: Double) {
        basePosition = seconds; stamp = Date(); objectWillChange.send()
        command("set player position to \(seconds)")
    }
    func open(_ s: Source) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: s.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

extension MusicService.Source: CaseIterable {}

// MARK: - Clipboard

struct ClipItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let date: Date
    let preview: String   // computed once; rendering a multi-megabyte string every frame is what hurts

    init(text: String, date: Date) {
        self.text = text
        self.date = date
        self.preview = String(text.prefix(400)).trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ⏎ ")
    }
}

final class ClipboardService: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var copiedID: UUID?

    private var lastCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let limit = 30

    func start() {
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = 0.5
        timer = t
    }

    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        let types = pb.types?.map(\.rawValue) ?? []
        // Respect password managers that flag secrets.
        if types.contains("org.nspasteboard.ConcealedType") || types.contains("org.nspasteboard.TransientType") { return }
        guard let s = pb.string(forType: .string), s.utf8.count <= 200_000,   // skip huge blobs instead of hoarding them
              !s.prefix(2000).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if items.first?.text == s { return }
        items.removeAll { $0.text == s }
        items.insert(ClipItem(text: s, date: Date()), at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
    }

    func copy(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
        lastCount = pb.changeCount
        copiedID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.copiedID == item.id { self?.copiedID = nil }
        }
    }

    func clear() { items.removeAll() }
}

// MARK: - Shelf

struct ShelfItem: Identifiable, Equatable {
    let url: URL
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

final class ShelfService: ObservableObject {
    @Published var items: [ShelfItem] = []
    private let key = "shelfPaths"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        items = paths.filter { FileManager.default.fileExists(atPath: $0) }.map { ShelfItem(url: URL(fileURLWithPath: $0)) }
    }

    func add(_ urls: [URL]) {
        for u in urls where u.isFileURL && !items.contains(where: { $0.url == u }) {
            items.append(ShelfItem(url: u))
        }
        save()
    }
    func remove(_ item: ShelfItem) { items.removeAll { $0 == item }; save() }
    func clear() { items.removeAll(); save() }
    private func save() { UserDefaults.standard.set(items.map { $0.url.path }, forKey: key) }
}
