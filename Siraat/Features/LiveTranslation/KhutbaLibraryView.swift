import SwiftUI

struct KhutbaLibraryView: View {
    @State private var sessions: [KhutbaSession] = []
    private let store = KhutbaLibraryStore()

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No saved khutbas yet",
                    systemImage: "books.vertical",
                    description: Text("Record a khutba translation and tap Save to keep it here.")
                )
            } else {
                List {
                    ForEach(sessions) { session in
                        NavigationLink {
                            KhutbaDetailView(session: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.title)
                                    .font(.headline)
                                    .foregroundStyle(SiraatColor.textPrimary)
                                Text("\(session.segments.count) passages")
                                    .font(.caption)
                                    .foregroundStyle(SiraatColor.textSecondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            sessions = store.delete(id: sessions[index].id)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Khutba Library")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { sessions = store.all() }
    }
}

private struct KhutbaDetailView: View {
    let session: KhutbaSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(session.segments) { segment in
                    VStack(alignment: .leading, spacing: 8) {
                        if let translated = segment.translatedText {
                            Text(translated)
                                .font(.system(.body, design: .serif, weight: .medium))
                                .foregroundStyle(SiraatColor.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text.arabic(segment.sourceText)
                            .font(.body)
                            .foregroundStyle(SiraatColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .multilineTextAlignment(.trailing)
                            .environment(\.layoutDirection, .rightToLeft)
                    }
                    .padding()
                    .background(SiraatColor.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding()
        }
        .background(SiraatColor.background.ignoresSafeArea())
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
