import SwiftUI
import Combine

enum NotchTab: String, CaseIterable, Identifiable {
    case music, clipboard, shelf, airdrop, tools
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .music: return "music.note"
        case .clipboard: return "doc.on.clipboard"
        case .shelf: return "tray.and.arrow.down"
        case .airdrop: return "antenna.radiowaves.left.and.right"
        case .tools: return "wrench.and.screwdriver"
        }
    }
    var expandedHeight: CGFloat {
        switch self {
        case .music: return 176
        case .clipboard: return 232
        case .shelf: return 190
        case .airdrop: return 190
        case .tools: return 240
        }
    }
}

enum HUDKind: Equatable { case volume, muted, brightness }

enum Transient: Equatable {
    case toast(symbol: String, text: String)
    case hud(kind: HUDKind, value: Double)
}

final class NotchModel: ObservableObject {
    static let shared = NotchModel()

    @Published var isExpanded = false
    @Published var isPinned = false
    @Published var isEditing = false
    @Published var isFileDragActive = false
    /// True while the macOS lock screen is up: the notch stays collapsed and read-only.
    @Published var isLocked = false
    /// True while the notch is invisible (full-screen app): animations pause so nothing is drawn for nobody.
    @Published var isHidden = false
    @Published var tab: NotchTab = .music
    @Published var transient: Transient?
    @Published var baseSize = CGSize(width: 190, height: 32)

    let settings = AppSettings.shared
    let music = MusicService()
    let clipboard = ClipboardService()
    let shelf = ShelfService()
    let keyboard = KeyboardLockService()
    let lid = LidService()
    let caffeine = CaffeinateService()

    static let expandedWidth: CGFloat = 600

    private var bag = Set<AnyCancellable>()
    private var transientWork: DispatchWorkItem?

    init() {
        tab = NotchTab(rawValue: settings.lastTab) ?? .music
        [music.objectWillChange, shelf.objectWillChange, clipboard.objectWillChange,
         keyboard.objectWillChange, lid.objectWillChange, caffeine.objectWillChange, settings.objectWillChange]
            .forEach { pub in
                pub.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
            }
        keyboard.onLock = { [weak self] in self?.tab = .tools }   // hovering the notch then lands on the Unlock button
        $tab.dropFirst().sink { [weak self] t in self?.settings.lastTab = t.rawValue }.store(in: &bag)
    }

    var musicActive: Bool { settings.showMusicActivity && music.isPlaying }
    var hasActivity: Bool { musicActive || keyboard.isLocked || lid.isAwakeWhenClosed || caffeine.isOn }

    var wing: CGFloat {
        switch transient {
        case .toast: return 104
        case .hud: return 66
        case nil: return hasActivity ? 46 : 0
        }
    }

    var collapsedSize: CGSize { CGSize(width: baseSize.width + 2 * wing, height: baseSize.height) }
    var expandedSize: CGSize { CGSize(width: max(Self.expandedWidth, baseSize.width + 460), height: baseSize.height + tab.expandedHeight - 32) }
    var currentSize: CGSize { isExpanded ? expandedSize : collapsedSize }

    /// Changes whenever the visible layout changes, so SwiftUI can animate it.
    var layoutKey: String { "\(isExpanded)|\(tab.rawValue)|\(wing)|\(baseSize.width)" }

    func showToast(symbol: String, text: String, duration: TimeInterval = 2.4) {
        guard !isLocked else { return }   // device names / battery alerts don't belong on the lock screen
        present(.toast(symbol: symbol, text: text), duration: duration)
    }

    func showHUD(kind: HUDKind, value: Double) {
        guard settings.hudEnabled else { return }
        present(.hud(kind: kind, value: value), duration: 1.6)
    }

    private func present(_ t: Transient, duration: TimeInterval) {
        transientWork?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { transient = t }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { self?.transient = nil }
        }
        transientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
