import SwiftUI

struct JuzIndexView: View {
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(1...30, id: \.self) { juz in
                Button {
                    onSelect(juz)
                    dismiss()
                } label: {
                    HStack {
                        Text("\(juz)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(SiraatColor.gold)
                            .frame(width: 34, height: 34)
                            .background(SiraatColor.gold.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: SiraatRadius.inner, style: .continuous))
                        Text("Juz \(juz)")
                            .font(.headline)
                            .foregroundStyle(SiraatColor.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(SiraatColor.textSecondary)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Juz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
