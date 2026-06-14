import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var services: AppServices
    @StateObject private var viewModel = SettingsViewModel()

    /// Opt-in for the experimental acoustic Tajweed path. Off by default: it loads a large
    /// on-device model and runs inference, which uses noticeably more memory. Read by
    /// `CoreMLForcedAligner` on each analysis.
    @AppStorage(CoreMLForcedAligner.enabledDefaultsKey) private var acousticTajweedEnabled = false

    /// Opt-in for the streaming forced-alignment follow-along. Off by default keeps the existing
    /// word matcher; read by `HybridRecitationAnalysisProvider` on each analysis.
    @AppStorage(HybridRecitationAnalysisProvider.streamingFollowDefaultsKey) private var streamingFollowEnabled = false

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

            Section("Recitation") {
                Toggle("Live follow-along (beta)", isOn: $streamingFollowEnabled)
                Text("Tracks your recitation word by word and keeps up through isti'adha, basmala, pauses, and repeats. It never flags a correct reciter, and audio never leaves your phone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle("On-device Tajweed (experimental)", isOn: $acousticTajweedEnabled)
                Text("Grades Madd (elongation) length from your recitation using an on-device model. Off by default because it loads a large model and uses more memory. Turn it off if Listen becomes unstable. Audio never leaves your phone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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

            Section("Prayer Time Adjustments") {
                PrayerAdjustmentStepper("Fajr", value: $viewModel.settings.prayerAdjustments.fajr)
                PrayerAdjustmentStepper("Dhuhr", value: $viewModel.settings.prayerAdjustments.dhuhr)
                PrayerAdjustmentStepper("Asr", value: $viewModel.settings.prayerAdjustments.asr)
                PrayerAdjustmentStepper("Maghrib", value: $viewModel.settings.prayerAdjustments.maghrib)
                PrayerAdjustmentStepper("Isha", value: $viewModel.settings.prayerAdjustments.isha)
                Text("Add or subtract minutes to match your local mosque's timetable.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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

    /// Per-prayer minute adjustment — label shows "+2 min" / "-1 min" / "0 min".
    private struct PrayerAdjustmentStepper: View {
        let label: String
        @Binding var value: Int

        init(_ label: String, value: Binding<Int>) {
            self.label = label
            self._value = value
        }

        var body: some View {
            Stepper(
                "\(label): \(value > 0 ? "+" : "")\(value) min",
                value: $value,
                in: -30...30
            )
        }
    }

    private var hijriAdjustmentLabel: String {
        let value = viewModel.settings.hijriDayAdjustment
        let sign = value > 0 ? "+" : ""
        let unit = abs(value) == 1 ? "day" : "days"
        return "Adjustment: \(sign)\(value) \(unit)"
    }
}
