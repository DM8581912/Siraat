import SwiftUI
import UIKit

struct QuranReaderView: View {
    @EnvironmentObject private var services: AppServices
    @StateObject private var viewModel = QuranReaderViewModel()
    @State private var showSurahIndex = false
    @State private var showJuzIndex = false

    var body: some View {
        VStack(spacing: 0) {
            ReaderToolbar(viewModel: viewModel, showSurahIndex: $showSurahIndex, showJuzIndex: $showJuzIndex)
                .padding(.horizontal)
                .padding(.bottom, 8)

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

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
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
            .padding(10)
            .background(SiraatColor.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: SiraatRadius.inner, style: .continuous))

            HStack(spacing: 10) {
                Button { showSurahIndex = true } label: {
                    Label(viewModel.selectedChapter.transliteratedName, systemImage: "list.bullet")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .tint(SiraatColor.accent)

                Button { showJuzIndex = true } label: {
                    Label("Juz", systemImage: "square.stack.3d.up")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(SiraatColor.gold)

                Spacer()

                Picker("Mode", selection: settingsBinding(\.readingMode)) {
                    ForEach(ReadingMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 150)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.selectedChapter.detailName)
                        .font(.caption.weight(.semibold))
                    Text("\(viewModel.selectedChapter.verseCount) ayahs")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Script", selection: settingsBinding(\.script)) {
                    ForEach(QuranScript.allCases) { script in
                        Text(script.displayName).tag(script)
                    }
                }
                .pickerStyle(.menu)

                Slider(value: settingsBinding(\.fontSize), in: 22...42, step: 1) {
                    Text("Arabic font size")
                } minimumValueLabel: {
                    Image(systemName: "textformat.size.smaller")
                } maximumValueLabel: {
                    Image(systemName: "textformat.size.larger")
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

private struct QuranVerseRow: View {
    let verse: QuranVerse
    let settings: ReaderSettings
    let isBookmarked: Bool
    let isPlaying: Bool
    let onBookmark: () -> Void
    let onPlay: () -> Void
    let onVisible: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(verse.verseKey)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isPlaying ? SiraatColor.gold.opacity(0.25) : SiraatColor.secondaryBackground)
                    .clipShape(Capsule())

                Spacer()

                Button(action: onPlay) {
                    Image(systemName: "play.fill")
                }
                .accessibilityLabel("Play verse \(verse.verseKey)")

                Button(action: onBookmark) {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark verse")

                Button {
                    UIPasteboard.general.string = "\(verse.text(for: settings.script))\n\n\(verse.translation)\n\n— Quran \(verse.verseKey), \(settings.translationLanguage.quranTranslationCredit)"
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Copy verse")

                ShareLink(item: "\(verse.verseKey)\n\(verse.text(for: settings.script))\n\(verse.translation)") {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share verse")
            }

            ArabicText(
                verse.text(for: settings.script),
                size: CGFloat(settings.fontSize),
                scripture: settings.script == .uthmani
            )
            .lineSpacing(8)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .multilineTextAlignment(.trailing)
            .environment(\.layoutDirection, .rightToLeft)

            if !verse.translation.isEmpty {
                Text(verse.translation)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(isPlaying ? SiraatColor.gold.opacity(0.12) : SiraatColor.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: SiraatRadius.inner, style: .continuous))
        .onAppear(perform: onVisible)
    }
}

private struct QuranPlaybackBar: View {
    @ObservedObject var player: QuranAudioPlayer
    let verses: [QuranVerse]

    var body: some View {
        HStack(spacing: 18) {
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
