import SwiftUI

struct RecitationCorrectionView: View {
    @EnvironmentObject private var services: AppServices
    @StateObject private var viewModel = RecitationCorrectionViewModel()
    @State private var selectedTip: CorrectionTip?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    correctionControls

                    SectionBand(title: viewModel.selectedVerse?.verseKey ?? "Selected Verse") {
                        Text("Analysis: \(viewModel.analysisEngine.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: 8) {
                            ForEach(viewModel.words) { word in
                                WordChip(word: word)
                                    .onTapGesture {
                                        selectedTip = word.tip
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
                        viewModel.isListening ? viewModel.stopListening() : viewModel.startListening()
                    } label: {
                        Label(viewModel.isListening ? "Stop" : "Listen", systemImage: viewModel.isListening ? "stop.fill" : "mic.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isListening ? SiraatColor.destructive : SiraatColor.accent)
                }
            }
            .padding()
            .background(.regularMaterial)
        }
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
                analysisProvider: services.recitationAnalysisProvider
            )
            viewModel.loadVerse()
        }
    }

    private var correctionControls: some View {
        SectionBand(title: "Practice") {
            HStack {
                Picker("Surah", selection: Binding(get: { viewModel.selectedSurah }, set: { viewModel.selectSurah($0) })) {
                    ForEach(QuranChapter.all) { chapter in
                        Text(chapter.displayName).tag(chapter.number)
                    }
                }
                .pickerStyle(.menu)

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
        HStack(spacing: 6) {
            // A non-color status signal so color-blind users (who can't tell green
            // from orange/red) still get feedback. Hidden from VoiceOver because the
            // status is already spoken in the accessibilityLabel below.
            if let symbol = statusSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text.arabic(word.originalText)
                .font(.system(size: 28, weight: .semibold, design: .serif))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.18))
        .foregroundStyle(color)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(word.originalText), \(word.status.rawValue)")
    }

    private var statusSymbol: String? {
        switch word.status {
        case .pending: nil
        case .correct: "checkmark"
        case .uncertain: "questionmark"
        case .missed: "exclamationmark"
        }
    }

    private var color: Color {
        switch word.status {
        case .pending: .primary
        case .correct: SiraatColor.accent
        case .uncertain: SiraatColor.warning
        case .missed: SiraatColor.destructive
        }
    }
}
