import SwiftUI
import ServiceManagement
import FinderWheelCore

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 0) {
            SettingsCard {
                SettingsRow {
                    Text("Hotkey")
                    Spacer()
                    Picker("Hotkey", selection: $settings.hotkeyID) {
                        ForEach(HotkeyCombo.all) { combo in
                            Text(combo.label).tag(combo.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            SettingsFootnote("Select files in Finder and hold the hotkey to show the wheel. Move to an action and release to run it, or press Escape to cancel.")

            SettingsCard {
                SettingsToggleRow(title: "Open at login", isOn: Binding(get: { opensAtLogin }, set: setOpensAtLogin))
                SettingsSeparator()
                SettingsToggleRow(title: "Remove location data from images",
                                  detail: "Applies to the copies saved by Convert and Compress. Your originals are never changed.",
                                  isOn: $settings.stripLocation)
            }
            .padding(.top, 20)
            if let loginError {
                SettingsFootnote(loginError).foregroundStyle(.red)
            }
        }
        .settingsPage()
        .onAppear { opensAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Could not change the login item: \(error.localizedDescription)"
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}
