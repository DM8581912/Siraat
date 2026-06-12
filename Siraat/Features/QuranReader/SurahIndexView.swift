import SwiftUI

struct SurahIndexView: View {
    let surahs: [BundledSurah]
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [BundledSurah] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return surahs }
        return surahs.filter {
            $0.englishName.localizedCaseInsensitiveContains(trimmed) ||
            $0.englishNameTranslation.localizedCaseInsensitiveContains(trimmed) ||
            "\($0.number)" == trimmed
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { surah in
                Button {
                    onSelect(surah.number)
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Text("\(surah.number)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(SiraatColor.accent)
                            .frame(width: 34, height: 34)
                            .background(SiraatColor.accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(surah.englishName)
                                .font(.headline)
                                .foregroundStyle(SiraatColor.textPrimary)
                            Text("\(surah.englishNameTranslation) · \(surah.ayahs.count) ayahs · \(surah.isMeccan ? "Meccan" : "Medinan")")
                                .font(.caption)
                                .foregroundStyle(SiraatColor.textSecondary)
                        }

                        Spacer()

                        Text.arabic(surah.nameArabic)
                            .font(.system(size: 22, design: .serif))
                            .foregroundStyle(SiraatColor.textPrimary)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Search surah")
            .navigationTitle("Surahs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
