import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var services: AppServices
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        Form {
            Section("Reader") {
                Picker("Script", selection: $viewModel.settings.script) {
                    ForEach(QuranScript.allCases) { script in
                        Text(script.displayName).tag(script)
                    }
                }

                Picker("Reading mode", selection: $viewModel.settings.readingMode) {
                    ForEach(ReadingMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Slider(value: $viewModel.settings.fontSize, in: 22...42, step: 1) {
                    Text("Arabic font size")
                }

                Picker("Translation", selection: $viewModel.settings.translationLanguage) {
                    ForEach(TranslationLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                Picker("Reciter", selection: $viewModel.settings.selectedReciterID) {
                    ForEach(QuranReciter.allCases) { reciter in
                        Text(reciter.displayName).tag(reciter.rawValue)
                    }
                }

                Picker("Appearance", selection: $viewModel.settings.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section("Privacy") {
                Label("Microphone access starts only after you tap Record or Listen.", systemImage: "mic")
                Label("Location is used only for prayer times and qibla direction.", systemImage: "location")
                Label("API keys are read from xcconfig or Keychain, never from source code.", systemImage: "lock.shield")
                Text(viewModel.secretsStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Prayer Reminders") {
                Toggle("Enable reminders", isOn: $viewModel.prayerReminderSettings.isEnabled)

                Stepper(
                    "\(viewModel.prayerReminderSettings.minutesBefore) minutes before",
                    value: $viewModel.prayerReminderSettings.minutesBefore,
                    in: 0...45,
                    step: 5
                )
                .disabled(!viewModel.prayerReminderSettings.isEnabled)
            }

            Section {
                Button {
                    viewModel.save()
                } label: {
                    Label("Save Settings", systemImage: "checkmark.circle")
                }
            }
        }
        .navigationTitle("Settings")
        .task {
            viewModel.configure(
                databaseManager: services.quranDatabaseManager,
                prayerNotificationService: services.prayerNotificationService,
                appearanceController: services.appearanceController
            )
            viewModel.load()
        }
        .onChange(of: viewModel.settings) {
            viewModel.save()
        }
        .onChange(of: viewModel.prayerReminderSettings) {
            viewModel.save()
        }
    }
}
