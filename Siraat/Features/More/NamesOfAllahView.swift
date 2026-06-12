import SwiftUI

struct NamesOfAllahView: View {
    @State private var query = ""

    private var filtered: [NameOfAllah] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return AsmaulHusna.all }
        return AsmaulHusna.all.filter {
            $0.transliteration.localizedCaseInsensitiveContains(trimmed) ||
            $0.meaning.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        List(filtered) { name in
            HStack(spacing: 14) {
                Text("\(name.id)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(SiraatColor.accent)
                    .frame(width: 36, height: 36)
                    .background(SiraatColor.accent.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(name.transliteration)
                        .font(.headline)
                        .foregroundStyle(SiraatColor.textPrimary)
                    Text(name.meaning)
                        .font(.caption)
                        .foregroundStyle(SiraatColor.textSecondary)
                }

                Spacer()

                Text.arabic(name.arabic)
                    .font(.system(size: 26, design: .serif))
                    .foregroundStyle(SiraatColor.accentDeep)
            }
            .padding(.vertical, 4)
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "Search by name or meaning")
        .navigationTitle("99 Names of Allah")
        .navigationBarTitleDisplayMode(.inline)
    }
}
