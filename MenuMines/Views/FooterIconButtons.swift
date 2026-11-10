import SwiftUI

// MARK: - Icon Buttons

enum FooterIconMetrics {
    /// Big enough to hit without aiming, the size of a toolbar's icon buttons.
    static let size: CGFloat = 24
}

/// A rounded backing under the pointer, darker while pressed: how the system's own small icon
/// buttons in menu bar panels respond.
struct HoverBacking: ViewModifier {
    var isPressed = false
    var isOn = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    private var opacity: Double {
        guard isEnabled else { return isOn ? 0.1 : 0 }
        if isPressed { return 0.18 }
        if isOn { return isHovered ? 0.2 : 0.14 }
        return isHovered ? 0.09 : 0
    }

    func body(content: Content) -> some View {
        content
            .frame(width: FooterIconMetrics.size, height: FooterIconMetrics.size)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(opacity * 1.6) : Color.primary.opacity(opacity))
            )
            .contentShape(.rect)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.08), value: isHovered)
    }
}

struct FooterIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                .modifier(HoverBacking(isPressed: configuration.isPressed))
        }
    }
}

/// An icon that stays lit while it's on, and tells VoiceOver it's a switch and which way it's set.
struct FooterIconToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
        }
        .buttonStyle(ToggleLabelStyle(isOn: configuration.isOn))
        .accessibilityAddTraits(.isToggle)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
        .accessibilityValue(String(localized: configuration.isOn ? "toggle_value_on" : "toggle_value_off"))
    }

    private struct ToggleLabelStyle: ButtonStyle {
        let isOn: Bool

        func makeBody(configuration: Configuration) -> some View {
            StyledLabel(configuration: configuration, isOn: isOn)
        }
    }

    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        let isOn: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13))
                .foregroundStyle(isOn ? Color.accentColor : (isEnabled ? Color.primary : Color.secondary))
                .modifier(HoverBacking(isPressed: configuration.isPressed, isOn: isOn))
        }
    }
}
