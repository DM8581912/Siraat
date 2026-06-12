import SwiftUI
import UIKit

private struct Dhikr: Identifiable, Hashable {
    let id: Int
    let arabic: String
    let transliteration: String
    let meaning: String
}

private let dhikrList: [Dhikr] = [
    Dhikr(id: 0, arabic: "سُبْحَانَ ٱللَّٰه", transliteration: "SubhanAllah", meaning: "Glory be to Allah"),
    Dhikr(id: 1, arabic: "ٱلْحَمْدُ لِلَّٰه", transliteration: "Alhamdulillah", meaning: "All praise is due to Allah"),
    Dhikr(id: 2, arabic: "ٱللَّٰهُ أَكْبَر", transliteration: "Allahu Akbar", meaning: "Allah is the Greatest"),
    Dhikr(id: 3, arabic: "لَا إِلَٰهَ إِلَّا ٱللَّٰه", transliteration: "La ilaha illAllah", meaning: "There is no god but Allah"),
    Dhikr(id: 4, arabic: "أَسْتَغْفِرُ ٱللَّٰه", transliteration: "Astaghfirullah", meaning: "I seek forgiveness from Allah")
]

struct TasbihView: View {
    @AppStorage("tasbih.count") private var count = 0
    @AppStorage("tasbih.rounds") private var rounds = 0
    @AppStorage("tasbih.dhikrIndex") private var dhikrIndex = 0
    @AppStorage("tasbih.target") private var target = 33

    private var dhikr: Dhikr { dhikrList[min(dhikrIndex, dhikrList.count - 1)] }
    private var progress: Double { target > 0 ? Double(count) / Double(target) : 0 }

    var body: some View {
        VStack(spacing: 24) {
            dhikrPicker

            VStack(spacing: 6) {
                Text.arabic(dhikr.arabic)
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .foregroundStyle(SiraatColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(dhikr.transliteration)
                    .font(.headline)
                    .foregroundStyle(SiraatColor.accent)
                Text(dhikr.meaning)
                    .font(.subheadline)
                    .foregroundStyle(SiraatColor.textSecondary)
            }

            Spacer()

            counterButton

            Text("Round \(rounds) · Target \(target)")
                .font(.subheadline)
                .foregroundStyle(SiraatColor.textSecondary)

            HStack(spacing: 12) {
                ForEach([33, 99, 100], id: \.self) { value in
                    Button("\(value)") { target = value }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(target == value ? SiraatColor.accent.opacity(0.15) : SiraatColor.secondaryBackground)
                        .foregroundStyle(target == value ? SiraatColor.accent : SiraatColor.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button {
                    reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .foregroundStyle(SiraatColor.destructive)
                .background(SiraatColor.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SiraatColor.background.ignoresSafeArea())
        .navigationTitle("Tasbih")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dhikrPicker: some View {
        Menu {
            ForEach(dhikrList) { item in
                Button(item.transliteration) { dhikrIndex = item.id }
            }
        } label: {
            HStack {
                Text("Dhikr: \(dhikr.transliteration)")
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(SiraatColor.textSecondary)
        }
    }

    private var counterButton: some View {
        Button {
            increment()
        } label: {
            ZStack {
                Circle()
                    .stroke(SiraatColor.hairline, lineWidth: 14)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(SiraatColor.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.2), value: progress)
                VStack(spacing: 2) {
                    Text("\(count)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(SiraatColor.textPrimary)
                        .monospacedDigit()
                    Text("of \(target)")
                        .font(.subheadline)
                        .foregroundStyle(SiraatColor.textSecondary)
                }
            }
            .frame(width: 260, height: 260)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tap to count \(dhikr.transliteration). Count \(count) of \(target), round \(rounds).")
    }

    private func increment() {
        count += 1
        if count >= target {
            count = 0
            rounds += 1
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func reset() {
        count = 0
        rounds = 0
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
