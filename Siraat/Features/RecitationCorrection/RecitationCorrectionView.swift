import SwiftUI

struct RecitationCorrectionView: View {
    @EnvironmentObject private var services: AppServices
    @StateObject private var viewModel = RecitationCorrectionViewModel()
    @State private var selectedTip: CorrectionTip?

    var body: some View {
        ErrorBoundaryView(error: viewModel.loadError, retryAction: { viewModel.loadVerse() }) {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    correctionControls

                    SectionBand(title: viewModel.selectedVerse?.verseKey ?? "Selected Verse") {
                        Text("Analysis: \(viewModel.analysisEngine.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Label(
                            "Advisory Tajweed feedback, processed on-device.",
                            systemImage: "info.circle"
                        )
                        .font(.caption2)
                        .foregroundStyle(SiraatColor.textSecondary)

                        FlowLayout(spacing: 8) {
                            ForEach(viewModel.words) { word in
                                WordChip(word: word)
                                    .onTapGesture {
                                        selectedTip = word.primaryFeedbackTip
                                    }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .environment(\.layoutDirection, .rightToLeft)
                    }

                    if !viewModel.transcript.isEmpty {
                        SectionBand(title: "Live Transcript") {
                            Text.arabic(viewModel.transcript)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                                .environment(\.layoutDirection, .rightToLeft)
                        }
                    }
                }
                .padding()
            }

            VStack(spacing: 12) {
                WaveformView(level: viewModel.waveformLevel)

                HStack {
                    Button {
                        viewModel.reset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Reset correction")

                    Spacer()

                    Button {
                        viewModel.playReferenceVerse()
                    } label: {
                        Label(
                            viewModel.isPlayingReference ? "Stop" : "Play Verse",
                            systemImage: viewModel.isPlayingReference ? "stop.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(SiraatColor.gold)
                    .disabled(viewModel.selectedVerse == nil)

                    Button {
                        viewModel.isListening ? viewModel.stopListening() : viewModel.startListening()
                    } label: {
                        Label(viewModel.isListening ? "Stop" : "Record", systemImage: viewModel.isListening ? "stop.fill" : "mic.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isListening ? SiraatColor.destructive : SiraatColor.accent)
                }
            }
            .padding()
            .background(.regularMaterial)
        }
        } // ErrorBoundaryView
        .navigationTitle("Recitation Correction")
        .alert(item: $selectedTip) { tip in
            Alert(title: Text(tip.title), message: Text(tip.message), dismissButton: .default(Text("OK")))
        }
        .alert("Correction Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { _ in viewModel.errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            viewModel.configure(
                databaseManager: services.quranDatabaseManager,
                correctionService: services.recitationCorrectionService,
                analysisProvider: services.recitationAnalysisProvider,
                audioPlayer: services.quranAudioPlayer
            )
            viewModel.loadVerse()
        }
    }

    private var correctionControls: some View {
        SectionBand(title: "Practice") {
            VStack(spacing: SiraatSpacing.sm) {
                Picker("Surah", selection: Binding(get: { viewModel.selectedSurah }, set: { viewModel.selectSurah($0) })) {
                    ForEach(QuranChapter.all) { chapter in
                        Text(chapter.displayName).tag(chapter.number)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Stepper("Ayah \(viewModel.selectedVerseNumber)", value: $viewModel.selectedVerseNumber, in: viewModel.selectedChapterVerseRange)
                        .onChange(of: viewModel.selectedVerseNumber) {
                            viewModel.loadVerse()
                        }

                    Picker("Script", selection: $viewModel.script) {
                        ForEach(QuranScript.allCases) { script in
                            Text(script.displayName).tag(script)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: viewModel.script) {
                        viewModel.loadVerse()
                    }
                }
            }

            Button {
                viewModel.loadVerse()
            } label: {
                Label("Load Verse", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct WordChip: View {
    let word: RecitationWord

    var body: some View {
        HStack(spacing: SiraatSpacing.xxs) {
            // A non-color status signal so color-blind users (who can't tell green
            // from orange/red) still get feedback. Hidden from VoiceOver because the
            // status is already spoken in the accessibilityLabel below.
            if let symbol = statusSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .accessibilityHidden(true)
            }
            ArabicText(word.originalText, size: 28, weight: .semibold)
        }
        .padding(.horizontal, SiraatSpacing.sm)
        .padding(.vertical, SiraatSpacing.xs)
        .background(backgroundColor)
        .foregroundStyle(foregroundColor)
        .clipShape(RoundedRectangle(cornerRadius: SiraatRadius.inner, style: .continuous))
        .overlay(
            word.status == .pending
                ? RoundedRectangle(cornerRadius: SiraatRadius.inner, style: .continuous)
                    .strokeBorder(SiraatColor.hairline, lineWidth: 1)
                : nil
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(word.originalText), \(accessibilityStatus)")
    }

    private var statusSymbol: String? {
        if word.hasCriticalTajweedViolation {
            return "exclamationmark"
        }
        if word.hasAdvisoryTajweedViolation {
            return "questionmark"
        }

        switch word.status {
        case .pending: nil
        case .correct: "checkmark"
        case .uncertain: "questionmark"
        case .missed: "exclamationmark"
        }
    }

    private var foregroundColor: Color {
        if word.hasCriticalTajweedViolation {
            return SiraatColor.destructive
        }
        if word.hasAdvisoryTajweedViolation {
            return SiraatColor.warning
        }

        switch word.status {
        case .pending: SiraatColor.textPrimary
        case .correct: SiraatColor.accent
        case .uncertain: SiraatColor.warning
        case .missed: SiraatColor.destructive
        }
    }

    private var backgroundColor: Color {
        if word.hasCriticalTajweedViolation {
            return SiraatColor.destructive.opacity(0.18)
        }
        if word.hasAdvisoryTajweedViolation {
            return SiraatColor.warning.opacity(0.18)
        }

        switch word.status {
        case .pending: SiraatColor.secondaryBackground
        case .correct: SiraatColor.accent.opacity(0.18)
        case .uncertain: SiraatColor.warning.opacity(0.18)
        case .missed: SiraatColor.destructive.opacity(0.18)
        }
    }

    private var accessibilityStatus: String {
        guard let violation = word.tajweedViolations.first else {
            return word.status.rawValue
        }

        return "\(violation.rule.displayName), \(violation.severity.displayName), letter \(violation.affectedLetter)"
    }
}

private extension RecitationWord {
    var hasCriticalTajweedViolation: Bool {
        tajweedViolations.contains { $0.severity == .critical }
    }

    var hasAdvisoryTajweedViolation: Bool {
        tajweedViolations.contains { $0.severity == .advisory }
    }

    var primaryFeedbackTip: CorrectionTip? {
        if let violation = tajweedViolations.first {
            return CorrectionTip(
                title: "\(violation.rule.displayName) feedback",
                message: violation.userFacingMessage
            )
        }

        return tip
    }
}
