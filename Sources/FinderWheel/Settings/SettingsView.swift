import SwiftUI
import FinderWheelCore

struct SettingsView: View {
    @Bindable var settings: AppSettings
    /// Edited locally and stored on Save or Return, so the Keychain is not written on every keystroke.
    @State private var keyDraft = ""

    private func saveKey() {
        settings.mistralKey = keyDraft
    }

    var body: some View {
        Form {
            Section {
                Picker("Hotkey", selection: $settings.hotkeyID) {
                    ForEach(HotkeyCombo.all) { combo in
                        Text(combo.label).tag(combo.id)
                    }
                }
                Text("Hold the hotkey in Finder to show the wheel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Mistral OCR") {
                HStack {
                    SecureField("API key", text: $keyDraft)
                        .onSubmit(saveKey)
                    Button("Save", action: saveKey)
                        .disabled(keyDraft == settings.mistralKey)
                }
                .onAppear { keyDraft = settings.mistralKey }
                Text("Used only for the Markdown action on PDFs and images, which sends those files to Mistral. The key is stored in your Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Images") {
                Toggle("Remove location data when converting or compressing", isOn: $settings.stripLocation)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
