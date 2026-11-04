import SwiftUI

// Controls styled after the macOS Spotlight / Siri panel: dark rounded surfaces, hairline borders, capsule buttons, no stock bordered buttons.

/// Capsule button. `prominent` is the filled "on" state (orange with dark text); otherwise a soft translucent pill.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var fixedWidth = true   // true: stretch to fill the row

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, prominent: prominent, stretch: fixedWidth)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let stretch: Bool
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(prominent ? Color.black : Color.white)
                .padding(.horizontal, 14)
                .frame(maxWidth: stretch ? .infinity : nil).frame(height: 30)
                .background(Capsule(style: .continuous).fill(fill))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(prominent ? 0 : 0.08), lineWidth: 0.5))
                .contentShape(Capsule(style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(enabled ? 1 : 0.5)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hover)
                .onHover { hover = $0 }
        }

        var fill: Color {
            if prominent { return Color.orange.opacity(hover ? 1 : 0.92) }
            return Color.white.opacity(configuration.isPressed ? 0.2 : (hover ? 0.17 : 0.12))
        }
    }
}

/// A pop-up that looks like a Spotlight filter chip: current value + small chevrons, opens a native macOS menu.
struct PillMenu<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(String, Value)]
    @State private var hover = false

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { i in
                Button {
                    selection = options[i].1
                } label: {
                    if options[i].1 == selection { Label(options[i].0, systemImage: "checkmark") } else { Text(options[i].0) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(options.first { $0.1 == selection }?.0 ?? "").lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.5)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 11).frame(height: 30)
            .background(Capsule(style: .continuous).fill(Color.white.opacity(hover ? 0.12 : 0.07)))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
            .contentShape(Capsule(style: .continuous))
        }
        .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain).fixedSize()
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}
