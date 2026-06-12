import SwiftUI

struct DuasView: View {
    var body: some View {
        List(QuranicDuas.all) { dua in
            NavigationLink {
                DuaDetailView(dua: dua)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dua.title)
                        .font(.headline)
                        .foregroundStyle(SiraatColor.textPrimary)
                    Text(dua.reference)
                        .font(.caption)
                        .foregroundStyle(SiraatColor.textSecondary)
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Quranic Duas")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DuaDetailView: View {
    @EnvironmentObject private var services: AppServices
    let dua: QuranicDua
    @State private var verses: [QuranVerse] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading dua")
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if verses.isEmpty {
                ContentUnavailableView(
                    "Couldn’t load this dua",
                    systemImage: "wifi.exclamationmark",
                    description: Text("The verses for this dua aren’t available right now. Please try again.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(verses) { verse in
                        VStack(alignment: .leading, spacing: 12) {
                            ArabicText(verse.textUthmani, size: 28, scripture: true)
                                .lineSpacing(8)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .multilineTextAlignment(.trailing)
                                .environment(\.layoutDirection, .rightToLeft)
                            Text(verse.translation)
                                .font(.body)
                                .foregroundStyle(SiraatColor.textSecondary)
                        }
                        .padding()
                        .background(SiraatColor.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: SiraatRadius.card, style: .continuous))
                    }

                    Text("\(dua.reference) · Saheeh International")
                        .font(.caption2)
                        .foregroundStyle(SiraatColor.textSecondary)
                }
                .padding()
            }
        }
        .background(SiraatColor.background.ignoresSafeArea())
        .navigationTitle(dua.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            var loaded: [QuranVerse] = []
            for ref in dua.ayahs {
                if let verse = await services.quranDatabaseManager.ayah(surah: ref.surah, ayah: ref.ayah) {
                    loaded.append(verse)
                }
            }
            verses = loaded
            isLoading = false
        }
    }
}
