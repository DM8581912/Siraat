import SwiftUI
import Translation

struct LiveTranslationView: View {
    @StateObject private var viewModel = LiveTranslationViewModel()

    private var translationUnavailableOnThisOS: Bool {
        if #available(iOS 18, *) { return false } else { return true }
    }

    var body: some View {
        VStack(spacing: 0) {
            transcriptList

            controlBar
        }
        .navigationTitle("Live Translation")
        .background(translationEngine)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    KhutbaLibraryView()
                } label: {
                    Image(systemName: "books.vertical")
                }
                .accessibilityLabel("Khutba library")
            }
        }
        .alert("Translation Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { _ in viewModel.errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Khutba saved", isPresented: $viewModel.didSaveSession) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can revisit it any time from the Khutba Library.")
        }
        .task {
            viewModel.configure()
        }
    }

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if translationUnavailableOnThisOS {
                        InfoBanner(
                            icon: "info.circle",
                            text: "On-device live translation needs iOS 18. Showing the live Arabic transcript."
                        )
                    }

                    if viewModel.segments.isEmpty {
                        EmptyTranslationState()
                            .padding(.top, 60)
                    }

                    ForEach(viewModel.segments) { segment in
                        LiveSegmentView(segment: segment, showsTranslation: !translationUnavailableOnThisOS)
                            .id(segment.id)
                    }

                    if !viewModel.partialTranscript.isEmpty {
                        Text.arabic(viewModel.partialTranscript)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .multilineTextAlignment(.trailing)
                            .environment(\.layoutDirection, .rightToLeft)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.segments.count) {
                if let last = viewModel.segments.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var controlBar: some View {
        VStack(spacing: SiraatSpacing.sm) {
            WaveformView(level: viewModel.waveformLevel)

            HStack {
                Label {
                    Picker("Target language", selection: $viewModel.targetLanguage) {
                        ForEach(TranslationLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(translationUnavailableOnThisOS)
                } icon: {
                    Image(systemName: "globe")
                        .foregroundStyle(SiraatColor.textSecondary)
                }
                .fixedSize()

                Spacer()

                HStack(spacing: SiraatSpacing.xs) {
                    Button {
                        viewModel.saveSession()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canSaveSession)
                    .accessibilityLabel("Save khutba")

                    Button {
                        viewModel.clear()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Clear transcript")

                    Button {
                        viewModel.isRecording ? viewModel.stop() : viewModel.start()
                    } label: {
                        Label(viewModel.isRecording ? "Stop" : "Record", systemImage: viewModel.isRecording ? "stop.fill" : "mic.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isRecording ? SiraatColor.destructive : SiraatColor.accent)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    /// On iOS 18 this hosts the on-device translation driver; on iOS 17 it is empty.
    @ViewBuilder
    private var translationEngine: some View {
        if #available(iOS 18, *) {
            TranslationDriverView(viewModel: viewModel)
        }
    }
}

// MARK: - On-device translation driver (iOS 18+)

@available(iOS 18, *)
private struct TranslationDriverView: View {
    @ObservedObject var viewModel: LiveTranslationViewModel
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(configuration) { session in
                await translate(using: session)
            }
            .onChange(of: viewModel.segments) {
                triggerIfNeeded()
            }
            .onChange(of: viewModel.targetLanguage) {
                viewModel.retranslateAll()
                triggerIfNeeded(force: true)
            }
            .onAppear { triggerIfNeeded() }
    }

    private func triggerIfNeeded(force: Bool = false) {
        guard force || viewModel.hasUntranslated else { return }
        let newConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: "ar"),
            target: Locale.Language(identifier: viewModel.targetLanguage.rawValue)
        )
        if configuration == nil {
            configuration = newConfig
        } else {
            // Re-run the task for newly captured (or reset) segments.
            configuration = newConfig
        }
    }

    private func translate(using session: TranslationSession) async {
        let pending = viewModel.segments.filter { $0.translatedText == nil }
        guard !pending.isEmpty else { return }

        do {
            let requests = pending.map {
                TranslationSession.Request(sourceText: $0.sourceText, clientIdentifier: $0.id.uuidString)
            }
            // translations(from:) returns responses in request order.
            let responses = try await session.translations(from: requests)
            for (segment, response) in zip(pending, responses) {
                viewModel.setTranslation(response.targetText, for: segment.id)
            }
        } catch {
            viewModel.errorMessage = "Translation is downloading its language model or is unavailable. Try again in a moment."
        }
    }
}

// MARK: - Rows

private struct LiveSegmentView: View {
    let segment: LiveSegment
    let showsTranslation: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsTranslation {
                if let translated = segment.translatedText {
                    Text(translated)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Translating…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text.arabic(segment.sourceText)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .padding()
        .background(SiraatColor.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: SiraatRadius.card, style: .continuous))
    }
}

private struct InfoBanner: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SiraatColor.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: SiraatRadius.inner, style: .continuous))
    }
}

private struct EmptyTranslationState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 44))
                .foregroundStyle(SiraatColor.accent)
                .accessibilityHidden(true)
            Text("Ready for Arabic audio")
                .font(.title3.bold())
            Text("Start recording when the khutba begins.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}
