import SwiftUI
import Translation

struct LiveTranslationView: View {
    @StateObject private var viewModel = LiveTranslationViewModel()

    var body: some View {
        VStack(spacing: 0) {
            transcriptList

            controlBar
        }
        .navigationTitle("Live Translation")
        .background(TranslationDriverView(viewModel: viewModel))
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
        Group {
            if viewModel.segments.isEmpty && viewModel.partialTranscript.isEmpty {
                VStack {
                    if let notice = viewModel.translationNotice {
                        InfoBanner(icon: "globe", text: notice)
                            .padding(.horizontal, SiraatSpacing.md)
                    }
                    Spacer()
                    EmptyTranslationState()
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: SiraatSpacing.md) {
                            if let notice = viewModel.translationNotice {
                                InfoBanner(icon: "globe", text: notice)
                            }

                            ForEach(viewModel.segments) { segment in
                                LiveSegmentView(segment: segment)
                                    .id(segment.id)
                            }

                            if !viewModel.partialTranscript.isEmpty {
                                Text.arabic(viewModel.partialTranscript)
                                    .font(SiraatType.body)
                                    .foregroundStyle(SiraatColor.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .multilineTextAlignment(.trailing)
                                    .environment(\.layoutDirection, .rightToLeft)
                            }
                        }
                        .padding(SiraatSpacing.md)
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
}

// MARK: - On-device translation driver

/// Hosts Apple's on-device Translation framework. A zero-size background view drives a
/// `translationTask`: it ensures the Arabic to target-language pack is downloaded (surfacing a
/// "downloading" notice), then translates every captured segment. Re-runs are forced with
/// `Configuration.invalidate()` because assigning an equal configuration does not re-fire the
/// task, which is why only the first sentence (or none) was translating before.
private struct TranslationDriverView: View {
    @ObservedObject var viewModel: LiveTranslationViewModel
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(configuration) { session in
                await run(session)
            }
            .onChange(of: viewModel.segments) {
                triggerIfNeeded()
            }
            .onChange(of: viewModel.targetLanguage) {
                viewModel.retranslateAll()
                rebuildConfiguration()
            }
            .onAppear { rebuildConfiguration() }
    }

    /// Builds (or replaces) the configuration for the current target language. A new value
    /// re-fires `translationTask`; used on first appearance and when the language changes.
    private func rebuildConfiguration() {
        configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: "ar"),
            target: Locale.Language(identifier: viewModel.targetLanguage.rawValue)
        )
    }

    /// Re-runs the translation task for newly captured (or reset) segments.
    private func triggerIfNeeded() {
        guard viewModel.hasUntranslated else { return }
        if configuration == nil {
            rebuildConfiguration()
        } else {
            configuration?.invalidate()
        }
    }

    private func run(_ session: TranslationSession) async {
        let target = Locale.Language(identifier: viewModel.targetLanguage.rawValue)
        let source = Locale.Language(identifier: "ar")

        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed:
            break
        case .supported:
            // Pack is supported but not on the device yet: prepareTranslation downloads it,
            // showing the system consent sheet. Tell the user why translations are pending.
            viewModel.translationNotice = "Downloading the \(viewModel.targetLanguage.displayName) language model. This happens once."
        case .unsupported:
            viewModel.translationNotice = "On-device translation to \(viewModel.targetLanguage.displayName) is not available on this device."
            return
        @unknown default:
            break
        }

        do {
            try await session.prepareTranslation()
        } catch {
            viewModel.translationNotice = "The translation language model could not be prepared. Check your connection and storage, then try again."
            return
        }

        viewModel.translationNotice = nil
        await translatePending(using: session)
    }

    private func translatePending(using session: TranslationSession) async {
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
            viewModel.errorMessage = "Translation failed for the latest sentence. It will retry as you keep recording."
        }
    }
}

// MARK: - Rows

private struct LiveSegmentView: View {
    let segment: LiveSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
