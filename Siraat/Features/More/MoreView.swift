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

            Section("Library") {
                MoreRow(icon: "books.vertical.fill", tint: SiraatColor.accent,
                        title: "Khutba Library", subtitle: "Saved sermon translations") { KhutbaLibraryView() }
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
            HStack(spacing: SiraatSpacing.sm) {
                Image(systemName: icon)
                    .font(SiraatType.heading)
                    .foregroundStyle(tint)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: SiraatSpacing.xxs) {
                    Text(title)
                        .font(SiraatType.heading)
                        .foregroundStyle(SiraatColor.textPrimary)
                    Text(subtitle)
                        .font(SiraatType.caption)
                        .foregroundStyle(SiraatColor.textSecondary)
                }
            }
            .padding(.vertical, SiraatSpacing.xxs)
        }
    }
}
