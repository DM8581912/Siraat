import SwiftUI

struct MoreView: View {
    var body: some View {
        List {
            Section("Worship") {
                MoreRow(icon: "circle.hexagongrid.fill", tint: SiraatColor.accent,
                        title: "Tasbih", subtitle: "Digital dhikr counter") { TasbihView() }
                MoreRow(icon: "sparkles", tint: SiraatColor.gold,
                        title: "99 Names of Allah", subtitle: "Asma ul-Husna") { NamesOfAllahView() }
                MoreRow(icon: "hands.and.sparkles.fill", tint: SiraatColor.accentDeep,
                        title: "Quranic Duas", subtitle: "Supplications from the Qur'an") { DuasView() }
            }
        }
        .navigationTitle("More")
        .background(SiraatColor.background)
    }
}

private struct MoreRow<Destination: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(SiraatColor.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(SiraatColor.textSecondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
