import SwiftUI

/// What the board answers to, from the keyboard and the mouse.
struct ControlsPopoverView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "controls_title"))
                .font(.headline)

            // One grid for both sections, so keys and gestures share a column.
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                sectionHeader(String(localized: "controls_section_keyboard"))
                keyRow(["↑", "↓", "←", "→"], action: String(localized: "controls_move"))
                keyRow(
                    [String(localized: "controls_key_space"), String(localized: "controls_key_return")],
                    action: String(localized: "controls_reveal")
                )
                keyRow(["F"], action: String(localized: "controls_flag"))
                keyRow(["⌘R"], action: String(localized: "controls_reset"))
                keyRow(
                    [String(localized: "controls_key_escape"), "⌘W"],
                    action: String(localized: "controls_close")
                )

                sectionHeader(String(localized: "controls_section_mouse"))
                    .padding(.top, 4)
                mouseRow(String(localized: "controls_mouse_click"), action: String(localized: "controls_reveal"))
                mouseRow(String(localized: "controls_mouse_secondary"), action: String(localized: "controls_flag"))
                mouseRow(String(localized: "controls_mouse_chord"), action: String(localized: "controls_chord"))
                GridRow {
                    Image(systemName: "flag")
                    actionText(String(localized: "controls_flag_mode_description"))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "controls_flag_mode_description"))
            }
        }
        .font(.callout)
        .padding()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .gridCellColumns(2)
            .accessibilityAddTraits(.isHeader)
    }

    /// Wraps rather than widening the popover.
    private func actionText(_ text: String) -> some View {
        Text(text)
            .frame(maxWidth: 180, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func keyRow(_ keys: [String], action: String) -> some View {
        GridRow {
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { Keycap(label: $0) }
            }
            actionText(action)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(
            format: String(localized: "metric_accessibility_label"),
            keys.joined(separator: ", "),
            action
        ))
    }

    private func mouseRow(_ gesture: String, action: String) -> some View {
        GridRow {
            Text(gesture)
                .foregroundStyle(.secondary)
                .fixedSize()
            actionText(action)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: String(localized: "metric_accessibility_label"), gesture, action))
    }
}

/// A key drawn the way the system draws one in its own shortcut lists.
private struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .frame(minWidth: 12)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.22), lineWidth: 0.5)
            )
    }
}
