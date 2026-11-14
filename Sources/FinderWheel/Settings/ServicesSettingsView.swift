import SwiftUI
import FinderWheelCore

/// Settings for the outside services some actions use: Mistral OCR and on-device transcription.
struct ServicesSettingsView: View {
    @Bindable var settings: AppSettings
    /// Edited locally and stored on Save or Return, so the Keychain is not written on every keystroke.
    @State private var keyDraft = ""
    @State private var draftLoaded = false
    @State private var locales: [Locale] = []
    @State private var localesLoaded = false
    @State private var modelInstalled: Bool?
    @State private var isDownloading = false
    @State private var downloadError: String?

    private func saveKey() {
        settings.mistralKey = keyDraft
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsSectionTitle("Mistral OCR")
            SettingsCard {
                SettingsRow {
                    Text("API Key")
                    SecureField("API Key", text: $keyDraft, prompt: Text("Paste your Mistral key"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveKey)
                        .padding(.leading, 24)
                    Button("Save", action: saveKey)
                        .disabled(keyDraft == settings.mistralKey)
                }
                // Only the first time: switching tabs must not throw away an unsaved key.
                .onAppear { if !draftLoaded { keyDraft = settings.mistralKey; draftLoaded = true } }
                SettingsSeparator()
                SettingsRow {
                    if settings.mistralKey.isEmpty {
                        Label("No key yet. Markdown for PDFs and images needs one.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Key saved in your Keychain", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Remove") {
                            keyDraft = ""
                            saveKey()
                        }
                        .controlSize(.small)
                    }
                    Spacer(minLength: 0)
                }
                .font(.callout)
            }
            SettingsFootnote("Used only by the Markdown action on PDFs and images, which sends those files to Mistral. Everything else stays on this Mac.")
            Link("Get a key at console.mistral.ai", destination: URL(string: "https://console.mistral.ai")!)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.top, 4)

            SettingsSectionTitle("Transcription")
                .padding(.top, 24)
            SettingsCard {
                if localesLoaded && locales.isEmpty {
                    SettingsRow {
                        Label("On-device transcription is not available on this Mac.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                } else {
                    SettingsRow {
                        Text("Language")
                        Spacer()
                        Picker("Language", selection: $settings.transcriptionLocaleID) {
                            ForEach(locales, id: \.identifier) { locale in
                                Text(SpeechModels.displayName(for: locale)).tag(locale.identifier)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .disabled(isDownloading)
                    }
                    SettingsSeparator()
                    SettingsRow {
                        if isDownloading {
                            ProgressView().controlSize(.small)
                            Text("Downloading speech model…")
                                .foregroundStyle(.secondary)
                        } else if modelInstalled == false {
                            Label("Speech model not installed", systemImage: "arrow.down.circle")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Download") { download() }
                                .controlSize(.small)
                        } else if modelInstalled == true {
                            Label("Speech model installed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Checking speech model…", systemImage: "circle.dotted")
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.callout)
                }
            }
            SettingsFootnote("Used by the Markdown action on video and audio. Transcription runs on this Mac.")
            if let downloadError {
                SettingsFootnote(downloadError).foregroundStyle(.red)
            }
        }
        .settingsPage()
        .task {
            locales = await SpeechModels.supportedLocales()
            localesLoaded = true
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
            let installed = await SpeechModels.isInstalled(locale)
            // Ignore the result if the language changed in the meantime.
            if settings.transcriptionLocaleID == locale.identifier { modelInstalled = installed }
        }
    }
}
