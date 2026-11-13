import SwiftUI
import FinderWheelCore

struct SettingsView: View {
    @Bindable var settings: AppSettings
    /// Edited locally and stored on Save or Return, so the Keychain is not written on every keystroke.
    @State private var keyDraft = ""
    @State private var locales: [Locale] = []
    @State private var modelInstalled: Bool?
    @State private var isDownloading = false
    @State private var downloadError: String?

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
                if settings.mistralKey.isEmpty {
                    Text("Add a key to use Markdown on PDFs and images.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Used only for the Markdown action on PDFs and images, which sends those files to Mistral. The key is stored in your Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Transcription") {
                Picker("Language", selection: $settings.transcriptionLocaleID) {
                    ForEach(locales, id: \.identifier) { locale in
                        Text(SpeechModels.displayName(for: locale)).tag(locale.identifier)
                    }
                }
                HStack {
                    if isDownloading {
                        ProgressView().controlSize(.small)
                        Text("Downloading speech model…")
                    } else if modelInstalled == true {
                        Label("Speech model installed", systemImage: "checkmark.circle")
                    } else if modelInstalled == false {
                        Label("Speech model not installed", systemImage: "arrow.down.circle")
                        Spacer()
                        Button("Download") { download() }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let downloadError {
                    Text(downloadError).font(.caption).foregroundStyle(.red)
                }
                Text("Used for the Markdown action on video and audio. Transcription runs on this Mac.")
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
        .task {
            locales = await SpeechModels.supportedLocales()
            // Make sure the stored language is one of the picker's options.
            if let match = await SpeechModels.supported(Locale(identifier: settings.transcriptionLocaleID)) {
                if settings.transcriptionLocaleID != match.identifier { settings.transcriptionLocaleID = match.identifier }
            } else if let first = locales.first(where: { $0.language.languageCode?.identifier == "en" }) ?? locales.first {
                settings.transcriptionLocaleID = first.identifier
            }
        }
        .task(id: settings.transcriptionLocaleID) {
            modelInstalled = nil
            downloadError = nil
            modelInstalled = await SpeechModels.isInstalled(Locale(identifier: settings.transcriptionLocaleID))
        }
    }

    private func download() {
        let locale = Locale(identifier: settings.transcriptionLocaleID)
        isDownloading = true
        downloadError = nil
        Task {
            do {
                try await SpeechModels.install(locale)
            } catch {
                downloadError = error.localizedDescription
            }
            isDownloading = false
            modelInstalled = await SpeechModels.isInstalled(locale)
        }
    }
}
