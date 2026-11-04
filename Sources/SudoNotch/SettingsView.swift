import SwiftUI
import ServiceManagement

enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General", notch = "Notch", corners = "Screen Corners", about = "About"
    var id: String { rawValue }
    static var debugInitial: SettingsPage?   // set by the debug URL hook only
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .notch: return "rectangle.topthird.inset.filled"
        case .corners: return "rectangle.roundedtop.fill"
        case .about: return "info.circle.fill"
        }
    }
    var tint: Color {
        switch self {
        case .general: return .gray
        case .notch: return .indigo
        case .corners: return .teal
        case .about: return .pink
        }
    }
}

// MARK: - Building blocks

struct PillToggleStyle: ToggleStyle {
    @ObservedObject var settings = AppSettings.shared
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Color(nsColor: settings.accentColor) : Color.white.opacity(0.18))
                    .frame(width: 40, height: 24)
                Circle().fill(.white).frame(width: 20, height: 20).padding(2)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: configuration.isOn)
            .onTapGesture { configuration.isOn.toggle() }
        }
    }
}

struct Card<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.4)).padding(.bottom, 8).padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.07)))
        }
    }
}

struct Row<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var last = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13))
                    if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)) }
                }
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            if !last { Divider().overlay(Color.white.opacity(0.06)).padding(.horizontal, 14) }
        }
    }
}

struct ToggleRow: View {
    let title: String
    var subtitle: String?
    var last = false
    @Binding var isOn: Bool
    var body: some View {
        Row(title: title, subtitle: subtitle, last: last) {
            Toggle("", isOn: $isOn).toggleStyle(PillToggleStyle()).labelsHidden().frame(width: 40)
        }
    }
}

struct SliderRow: View {
    let title: String
    var subtitle: String?
    var last = false
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: (Double) -> String = { String(format: "%.0f", $0) }
    var body: some View {
        Row(title: title, subtitle: subtitle, last: last) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range).frame(width: 170)
                Text(format(value)).font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6)).frame(width: 46, alignment: .trailing)
            }
        }
    }
}

struct PageHeader: View {
    let page: SettingsPage
    let subtitle: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: page.symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(page.tint.gradient, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(page.rawValue).font(.system(size: 20, weight: .bold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Root

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var page: SettingsPage = SettingsPage.debugInitial ?? .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Color.white.opacity(0.08))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch page {
                    case .general: GeneralPage(settings: settings)
                    case .notch: NotchPage(settings: settings)
                    case .corners: CornersPage(settings: settings)
                    case .about: AboutPage()
                    }
                }
                .padding(.horizontal, 26).padding(.top, 34).padding(.bottom, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 780, height: 560)
        .background(Color(red: 0.09, green: 0.09, blue: 0.10))
        .environment(\.colorScheme, .dark)
        .tint(Color(nsColor: settings.accentColor))
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3).fill(.black).frame(width: 22, height: 12)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.4)))
                Text("SudoNotch").font(.system(size: 14, weight: .bold))
            }
            .padding(.horizontal, 10).padding(.bottom, 14).padding(.top, 8)

            ForEach(SettingsPage.allCases) { p in
                Button { withAnimation(.easeOut(duration: 0.15)) { page = p } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: p.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 24, height: 24).background(p.tint.gradient, in: RoundedRectangle(cornerRadius: 6))
                        Text(p.rawValue).font(.system(size: 13, weight: page == p ? .semibold : .regular))
                        Spacer()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(page == p ? Color.white.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { NSApp.terminate(nil) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "power").font(.system(size: 12, weight: .bold))
                    Text("Quit SudoNotch").font(.system(size: 12.5, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.42))
                .padding(.horizontal, 12).frame(height: 34)
                .background(Color.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.red.opacity(0.25)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(12).padding(.top, 20)
        .frame(width: 210)
        .background(Color.black.opacity(0.25))
    }
}

// MARK: - Pages

struct LidPermissionCard: View {
    @ObservedObject var lid: LidService
    var body: some View {
        Card("Permissions") {
            Row(title: "Password-free lid-closed mode", subtitle: lid.hasPermission
                    ? "Set up. SudoNotch can switch \"awake with lid closed\" on and off without asking for your password."
                    : "Not set up yet. It asks for your password once, the first time you turn it on.", last: true) {
                if lid.hasPermission {
                    Button("Remove") { lid.removePermission() }.buttonStyle(.bordered).disabled(lid.isBusy)
                }
            }
        }
        .onAppear { lid.refresh() }
    }
}

struct GeneralPage: View {
    @ObservedObject var settings: AppSettings
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var status = LoginItem.statusText

    var body: some View {
        PageHeader(page: .general, subtitle: "How SudoNotch behaves on your Mac")
        Card("Startup") {
            ToggleRow(title: "Open at login", subtitle: status, last: true,
                      isOn: Binding(get: { launchAtLogin }, set: { v in
                          LoginItem.set(v); launchAtLogin = LoginItem.isEnabled; status = LoginItem.statusText
                      }))
        }
        if status.contains("approval") {
            Button("Open Login Items settings…") { SMAppService.openSystemSettingsLoginItems() }
                .buttonStyle(.bordered)
        }
        Card("Appearance") {
            Row(title: "Accent colour", subtitle: "Used for animations, toggles and the equalizer", last: true) {
                ColorPicker("", selection: settings.accentBinding, supportsOpacity: false).labelsHidden()
            }
        }
        LidPermissionCard(lid: NotchModel.shared.lid)
        Card("Privacy") {
            ToggleRow(title: "Hide from screenshots & screen sharing",
                      subtitle: "Asks macOS to keep the notch and corners out of screenshots and recordings (some capture tools ignore this)", last: true,
                      isOn: $settings.hideFromSharing)
        }
    }
}

struct NotchPage: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        PageHeader(page: .notch, subtitle: "Your fake notch and what lives in it")
        Card("Notch") {
            ToggleRow(title: "Show the notch", isOn: $settings.notchEnabled)
            SliderRow(title: "Width", subtitle: "Ignored on Macs with a real notch", value: $settings.notchWidth, range: 120...300)
            ToggleRow(title: "Match menu bar height", subtitle: "Keeps the notch flush with the bottom of the menu bar",
                      last: settings.matchMenuBar, isOn: $settings.matchMenuBar)
            if !settings.matchMenuBar {
                SliderRow(title: "Height", subtitle: "Ignored on Macs with a real notch", last: true,
                          value: $settings.notchHeight, range: 20...48)
            }
        }
        Card("Opening") {
            ToggleRow(title: "Open when I hover over it", isOn: $settings.hoverToOpen)
            SliderRow(title: "Hover delay", value: $settings.hoverDelay, range: 0...0.6,
                      format: { String(format: "%.2fs", $0) })
            ToggleRow(title: "Hide in full-screen apps", isOn: $settings.hideInFullscreen)
            ToggleRow(title: "Show on the lock screen", subtitle: "Just the notch, read-only. Restart SudoNotch to apply", last: true,
                      isOn: $settings.showOnLockScreen)
        }
        Card("Live activities") {
            ToggleRow(title: "Now playing", subtitle: "Artwork and equalizer beside the notch while music plays",
                      isOn: $settings.showMusicActivity)
            ToggleRow(title: "Volume & brightness HUD", subtitle: "Shows a level bar in the notch when you change them",
                      isOn: $settings.hudEnabled)
            ToggleRow(title: "Battery alerts", subtitle: "Plugged in, unplugged, low and full", isOn: $settings.batteryAlerts)
            ToggleRow(title: "Bluetooth alerts", subtitle: "When AirPods and other devices connect or disconnect", last: true,
                      isOn: $settings.bluetoothAlerts)
        }
    }
}

struct CornersPage: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        PageHeader(page: .corners, subtitle: "Round the corners of your display like a new MacBook")
        Card("Rounded corners") {
            ToggleRow(title: "Round the screen corners", isOn: $settings.cornersEnabled)
            SliderRow(title: "Radius", last: true, value: $settings.cornerRadius, range: 4...32,
                      format: { String(format: "%.0f pt", $0) })
        }
        Card("Preview") {
            ZStack {
                LinearGradient(colors: [.purple.opacity(0.6), .blue.opacity(0.6), .teal.opacity(0.5)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Text("Your display").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.8))
            }
            .frame(height: 130)
            .clipShape(RoundedRectangle(cornerRadius: settings.cornersEnabled ? CGFloat(settings.cornerRadius) * 1.4 : 0))
            .padding(14)
            .animation(.easeOut(duration: 0.15), value: settings.cornerRadius)
        }
    }
}

struct AboutPage: View {
    var body: some View {
        PageHeader(page: .about, subtitle: "A notch for Macs that don't have one")
        Card("Features") {
            ForEach(Array(features.enumerated()), id: \.offset) { i, f in
                Row(title: f.0, subtitle: f.1, last: i == features.count - 1) { EmptyView() }
            }
        }
        Text("Tip: open sudonotch://expand or sudonotch://settings from Terminal or Shortcuts.")
            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
    }

    let features: [(String, String)] = [
        ("Music", "Controls for Apple Music and Spotify, with artwork and seeking"),
        ("Clipboard history", "The last 30 things you copied, click to copy again (passwords are skipped)"),
        ("File shelf", "Drop files on the notch to park them, drag them out anywhere"),
        ("AirDrop", "Drop files on the notch and send them to nearby devices"),
        ("Alerts & HUDs", "Battery, Bluetooth, volume and brightness shown in the notch"),
        ("Screen corners", "Rounded display corners, with an animation when you use your macOS hot corners"),
    ]
}
