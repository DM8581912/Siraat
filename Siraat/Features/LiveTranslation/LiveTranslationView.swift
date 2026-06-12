import SwiftUI

struct LiveTranslationView: View {
    @EnvironmentObject private var services: AppServices
    @StateObject private var viewModel = LiveTranslationViewModel()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if viewModel.translationSegments.isEmpty {
                            EmptyTranslationState()
                                .padding(.top, 80)
                        }

                        ForEach(viewModel.translationSegments) { segment in
                            TranslationSegmentView(segment: segment)
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
                .onChange(of: viewModel.translationSegments.count) {
                    if let last = viewModel.translationSegments.last {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            VStack(spacing: 12) {
                WaveformView(level: viewModel.waveformLevel)

                HStack(spacing: 12) {
                    Picker("Target language", selection: $viewModel.targetLanguage) {
                        ForEach(TranslationLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()

                    Button {
                        viewModel.clear()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Clear translations")

                    Button {
                        viewModel.isRecording ? viewModel.stop() : viewModel.start()
                    } label: {
                        Label(viewModel.isRecording ? "Stop" : "Record", systemImage: viewModel.isRecording ? "stop.fill" : "mic.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isRecording ? SiraatColor.destructive : SiraatColor.accent)
                }
            }
            .padding()
            .background(.regularMaterial)
        }
        .navigationTitle("Live Translation")
        .alert("Translation Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { _ in viewModel.errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            viewModel.configure(translationService: services.translationService)
        }
    }
}

private struct EmptyTranslationState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 44))
                .foregroundStyle(SiraatColor.accent)
            Text("Ready for Arabic audio")
                .font(.title3.bold())
            Text("Start recording when the khutba begins.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

private struct TranslationSegmentView: View {
    let segment: TranslationSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(segment.translatedText)
                .font(.system(.title2, design: .serif, weight: .semibold))
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text.arabic(segment.sourceText)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .padding()
        .background(SiraatColor.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
