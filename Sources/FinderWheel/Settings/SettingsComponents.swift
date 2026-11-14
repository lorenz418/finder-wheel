import SwiftUI

/// A rounded group of rows, like a section of a grouped form.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06)))
    }
}

/// One row of a `SettingsCard`.
struct SettingsRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
    }
}

/// The hairline between two rows of a `SettingsCard`.
struct SettingsSeparator: View {
    var body: some View {
        Divider().padding(.horizontal, 12)
    }
}

/// The heading above a `SettingsCard`.
struct SettingsSectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .padding(.bottom, 6)
    }
}

/// Explanatory text under a `SettingsCard`.
struct SettingsFootnote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 6)
    }
}

/// A row with a title, an optional explanation under it, and a switch.
struct SettingsToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, detail == nil ? 0 : 6)
    }
}

extension View {
    /// A page of cards: a readable column centred in the settings window, as tall as its content.
    func settingsPage() -> some View {
        padding(.vertical, 20)
            .frame(width: 520)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: SettingsWindowController.width)
    }
}
