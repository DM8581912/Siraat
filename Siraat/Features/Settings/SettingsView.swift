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

            Section("Prayer Times") {
                Picker("Calculation method", selection: $viewModel.settings.calculationMethod) {
                    ForEach(CalculationMethod.selectable) { method in
                        Text(method.displayName).tag(method)
                    }
                }

                Picker("Asr (madhab)", selection: $viewModel.settings.madhab) {
                    ForEach(Madhab.allCases) { madhab in
                        Text(madhab.displayName).tag(madhab)
                    }
                }

                Picker("High-latitude rule", selection: $viewModel.settings.highLatitudeRule) {
                    Text("Automatic").tag(HighLatitudeRule?.none)
                    ForEach(HighLatitudeRule.allCases) { rule in
                        Text(rule.displayName).tag(HighLatitudeRule?.some(rule))
                    }
                }
            }

            Section("Hijri Date") {
                Stepper(
                    hijriAdjustmentLabel,
                    value: $viewModel.settings.hijriDayAdjustment,
                    in: -2...2
                )
                Text("Nudge the Hijri date ±1–2 days to match your local moon-sighting authority.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Label("Microphone access starts only after you tap Record or Listen.", systemImage: "mic")
                Label("Location is used only for prayer times and qibla direction.", systemImage: "location")
                Label("Any translation API keys are stored in the device Keychain, never committed to source or bundled in the app.", systemImage: "lock.shield")
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

                Toggle("Play adhan sound", isOn: $viewModel.prayerReminderSettings.playAdhanSound)
                    .disabled(!viewModel.prayerReminderSettings.isEnabled)
                Text("Adhan recording by Atcovi (Wikimedia Commons, CC BY-SA 4.0).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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

    private var hijriAdjustmentLabel: String {
        let value = viewModel.settings.hijriDayAdjustment
        let sign = value > 0 ? "+" : ""
        let unit = abs(value) == 1 ? "day" : "days"
        return "Adjustment: \(sign)\(value) \(unit)"
    }
}
