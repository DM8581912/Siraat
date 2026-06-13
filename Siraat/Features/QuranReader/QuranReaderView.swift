import SwiftUI
import UIKit

struct QuranReaderView: View {
    @EnvironmentObject private var services: AppServices
    @StateObject private var viewModel = QuranReaderViewModel()
    @State private var showSurahIndex = false
    @State private var showJuzIndex = false
    @State private var showDisplaySettings = false

    var body: some View {
        VStack(spacing: 0) {
            ReaderToolbar(viewModel: viewModel, showSurahIndex: $showSurahIndex, showJuzIndex: $showJuzIndex, showDisplaySettings: $showDisplaySettings)
                .padding(.horizontal)
                .padding(.bottom, SiraatSpacing.xs)

            Group {
                if viewModel.isLoading {
                    ProgressView("Loading verses")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.displayedVerses.isEmpty {
                    ContentUnavailableView(
                        viewModel.showsBookmarksOnly ? "No bookmarks here" : "No matching verses",
                        systemImage: viewModel.showsBookmarksOnly ? "bookmark" : "magnifyingglass",
                        description: Text("Adjust the search or filter to continue reading.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.settings.readingMode == .continuous {
                    continuousReader
                } else {
                    pageReader
                }
            }

            VStack(spacing: 2) {
                if viewModel.isOfflineTranslationFallback {
                    Label("Offline — showing English. Reconnect for \(viewModel.settings.translationLanguage.displayName).", systemImage: "wifi.slash")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(SiraatColor.warning)
                }
                Text("Translation: \(viewModel.translationCredit)  ·  Arabic: Uthmani (King Fahd Complex)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)

            QuranPlaybackBar(player: services.quranAudioPlayer, verses: viewModel.verses)
                .padding()
                .background(.regularMaterial)
        }
        .navigationTitle("Quran Reader")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    RecitationCorrectionView()
                } label: {
                    Image(systemName: "checkmark.seal")
                }
                .accessibilityLabel("Open recitation correction")
            }
        }
        .alert("Reader Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { _ in viewModel.errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $showSurahIndex) {
            SurahIndexView(surahs: viewModel.surahs) { viewModel.jump(toSurah: $0) }
        }
        .sheet(isPresented: $showJuzIndex) {
            JuzIndexView { juz in
                if let start = viewModel.startOfJuz(juz) {
                    viewModel.jump(toSurah: start.surah, ayah: start.ayah)
                }
            }
        }
        .sheet(isPresented: $showDisplaySettings) {
            DisplaySettingsSheet(viewModel: viewModel)
                .presentationDetents([.medium])
        }
        .task {
            viewModel.configure(databaseManager: services.quranDatabaseManager, audioPlayer: services.quranAudioPlayer)
            viewModel.load()
        }
    }

    private var continuousReader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(viewModel.displayedVerses) { verse in
                        EquatableView(content: QuranVerseRow(
                            verse: verse,
                            settings: viewModel.settings,
                            isBookmarked: viewModel.isBookmarked(verse),
                            isPlaying: services.quranAudioPlayer.currentVerseKey == verse.verseKey,
                            onBookmark: { viewModel.toggleBookmark(for: verse) },
                            onPlay: {
                                viewModel.markAsCurrent(verse)
                                services.quranAudioPlayer.play(verse: verse)
                            },
                            onVisible: { viewModel.markAsCurrent(verse) }
                        ))
                        .id(verse.verseKey)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.scrollTarget) {
                guard let target = viewModel.scrollTarget else { return }
                withAnimation { proxy.scrollTo(target, anchor: .top) }
                viewModel.scrollTarget = nil
            }
        }
    }

    private var pageReader: some View {
        TabView {
            ForEach(viewModel.displayedVerses) { verse in
                ScrollView {
                    QuranVerseRow(
                        verse: verse,
                        settings: viewModel.settings,
                        isBookmarked: viewModel.isBookmarked(verse),
                        isPlaying: services.quranAudioPlayer.currentVerseKey == verse.verseKey,
                        onBookmark: { viewModel.toggleBookmark(for: verse) },
                        onPlay: {
                            viewModel.markAsCurrent(verse)
                            services.quranAudioPlayer.play(verse: verse)
                        },
                        onVisible: { viewModel.markAsCurrent(verse) }
                    )
                    .padding()
                }
            }
        }
        .tabViewStyle(.page)
    }
}

private struct ReaderToolbar: View {
    @ObservedObject var viewModel: QuranReaderViewModel
    @Binding var showSurahIndex: Bool
    @Binding var showJuzIndex: Bool
    @Binding var showDisplaySettings: Bool

    var body: some View {
        VStack(spacing: SiraatSpacing.sm) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SiraatColor.textSecondary)
                TextField("Search ayah, translation, or verse key", text: $viewModel.searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    viewModel.showsBookmarksOnly.toggle()
                } label: {
                    Image(systemName: viewModel.showsBookmarksOnly ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(viewModel.showsBookmarksOnly ? "Show all verses" : "Show bookmarked verses")
            }
            .padding(SiraatSpacing.sm)
            .background(SiraatColor.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: SiraatRadius.inner, style: .continuous))

            HStack(spacing: SiraatSpacing.sm) {
                Button { showSurahIndex = true } label: {
                    Label(viewModel.selectedChapter.transliteratedName, systemImage: "list.bullet")
                        .font(SiraatType.callout.weight(.semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .tint(SiraatColor.accent)

                Button { showJuzIndex = true } label: {
                    Label("Juz", systemImage: "square.stack.3d.up")
                        .font(SiraatType.callout.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(SiraatColor.gold)

                Spacer()

                Text(viewModel.selectedChapter.detailName)
                    .font(SiraatType.caption)
                    .foregroundStyle(SiraatColor.textSecondary)
                    .lineLimit(1)

                Button { showDisplaySettings = true } label: {
                    Image(systemName: "textformat.size")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Display settings")
            }
        }
    }
}

private struct DisplaySettingsSheet: View {
    @ObservedObject var viewModel: QuranReaderViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: SiraatSpacing.xl) {
                VStack(alignment: .leading, spacing: SiraatSpacing.xs) {
                    Text("Reading Mode")
                        .font(SiraatType.caption.weight(.semibold))
                        .foregroundStyle(SiraatColor.textSecondary)
                    Picker("Mode", selection: settingsBinding(\.readingMode)) {
                        ForEach(ReadingMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: SiraatSpacing.xs) {
                    Text("Script")
                        .font(SiraatType.caption.weight(.semibold))
                        .foregroundStyle(SiraatColor.textSecondary)
                    Picker("Script", selection: settingsBinding(\.script)) {
                        ForEach(QuranScript.allCases) { script in
                            Text(script.displayName).tag(script)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: SiraatSpacing.xs) {
                    Text("Arabic Font Size")
                        .font(SiraatType.caption.weight(.semibold))
                        .foregroundStyle(SiraatColor.textSecondary)
                    Slider(value: settingsBinding(\.fontSize), in: 22...42, step: 1) {
                        Text("Arabic font size")
                    } minimumValueLabel: {
                        Image(systemName: "textformat.size.smaller")
                            .foregroundStyle(SiraatColor.textSecondary)
                    } maximumValueLabel: {
                        Image(systemName: "textformat.size.larger")
                            .foregroundStyle(SiraatColor.textSecondary)
                    }
                }

                Spacer()
            }
            .padding(SiraatSpacing.lg)
            .navigationTitle("Display")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<ReaderSettings, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.settings[keyPath: keyPath] },
            set: { value in
                var updated = viewModel.settings
                updated[keyPath: keyPath] = value
                viewModel.updateSettings(updated)
            }
        )
    }
}

private struct QuranVerseRow: View, Equatable {
    let verse: QuranVerse
    let settings: ReaderSettings
    let isBookmarked: Bool
    let isPlaying: Bool
    let onBookmark: () -> Void
    let onPlay: () -> Void
    let onVisible: () -> Void

    // Closures can't be compared — diff only the data that drives the visual output.
    static func == (lhs: QuranVerseRow, rhs: QuranVerseRow) -> Bool {
        lhs.verse == rhs.verse
            && lhs.settings == rhs.settings
            && lhs.isBookmarked == rhs.isBookmarked
            && lhs.isPlaying == rhs.isPlaying
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SiraatSpacing.sm) {
            HStack {
                Text(verse.verseKey)
                    .font(SiraatType.caption.weight(.semibold))
                    .padding(.horizontal, SiraatSpacing.xs)
                    .padding(.vertical, SiraatSpacing.xxs)
                    .foregroundStyle(isPlaying ? SiraatColor.gold : SiraatColor.textSecondary)
                    .background(isPlaying ? SiraatColor.gold.opacity(0.15) : SiraatColor.background)
                    .clipShape(Capsule())

                Spacer()

                HStack(spacing: SiraatSpacing.md) {
                    Button(action: onPlay) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(SiraatType.caption)
                    }
                    .accessibilityLabel(isPlaying ? "Pause verse \(verse.verseKey)" : "Play verse \(verse.verseKey)")

                    Button(action: onBookmark) {
                        Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                            .font(SiraatType.caption)
                    }
                    .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark verse")

                    Button {
                        UIPasteboard.general.string = "\(verse.text(for: settings.script))\n\n\(verse.translation)\n\n— Quran \(verse.verseKey), \(settings.translationLanguage.quranTranslationCredit)"
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(SiraatType.caption)
                    }
                    .accessibilityLabel("Copy verse")

                    ShareLink(item: "\(verse.verseKey)\n\(verse.text(for: settings.script))\n\(verse.translation)") {
                        Image(systemName: "square.and.arrow.up")
                            .font(SiraatType.caption)
                    }
                    .accessibilityLabel("Share verse")
                }
                .foregroundStyle(SiraatColor.textSecondary)
            }

            ArabicText(
                verse.text(for: settings.script),
                size: CGFloat(settings.fontSize),
                scripture: settings.script == .uthmani
            )
            .lineSpacing(SiraatSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .multilineTextAlignment(.trailing)
            .environment(\.layoutDirection, .rightToLeft)

            if !verse.translation.isEmpty {
                Text(verse.translation)
                    .font(SiraatType.body)
                    .foregroundStyle(SiraatColor.textSecondary)
            }
        }
        .padding(SiraatSpacing.md)
        .background(isPlaying ? SiraatColor.accent.opacity(0.08) : SiraatColor.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: SiraatRadius.inner, style: .continuous))
        .onAppear(perform: onVisible)
    }
}

private struct QuranPlaybackBar: View {
    @ObservedObject var player: QuranAudioPlayer
    let verses: [QuranVerse]

    var body: some View {
        HStack(spacing: SiraatSpacing.lg) {
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
            }
            .accessibilityLabel("Previous verse")

            Button {
                if player.isPlaying {
                    player.pause()
                } else if let current = verses.first(where: { $0.verseKey == player.currentVerseKey }) ?? verses.first {
                    player.play(verse: current)
                }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderedProminent)
            .tint(SiraatColor.accent)
            .accessibilityLabel(player.isPlaying ? "Pause recitation" : "Play recitation")

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
            }
            .accessibilityLabel("Next verse")

            Spacer()

            Toggle(isOn: $player.isRepeatEnabled) {
                Image(systemName: "repeat")
            }
            .labelsHidden()
            .accessibilityLabel("Repeat verse")
        }
    }
}
