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
        VStack(spacing: SiraatSpacing.xl) {
            dhikrPicker

            VStack(spacing: SiraatSpacing.xs) {
                ArabicText(dhikr.arabic, size: SiraatType.Arabic.dhikr, weight: .semibold)
                    .foregroundStyle(SiraatColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(dhikr.transliteration)
                    .font(SiraatType.heading)
                    .foregroundStyle(SiraatColor.accent)
                Text(dhikr.meaning)
                    .font(SiraatType.callout)
                    .foregroundStyle(SiraatColor.textSecondary)
            }

            Spacer()

            counterButton

            Text("Round \(rounds) · Target \(target)")
                .font(SiraatType.callout)
                .foregroundStyle(SiraatColor.textSecondary)

            HStack(spacing: SiraatSpacing.sm) {
                ForEach([33, 99, 100], id: \.self) { value in
                    Button("\(value)") { target = value }
                        .font(SiraatType.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SiraatSpacing.sm)
                        .background(target == value ? SiraatColor.accent.opacity(0.15) : SiraatColor.secondaryBackground)
                        .foregroundStyle(target == value ? SiraatColor.accent : SiraatColor.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: SiraatRadius.inner, style: .continuous))
                }

                Button {
                    reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(SiraatType.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SiraatSpacing.sm)
                }
                .foregroundStyle(SiraatColor.destructive)
                .background(SiraatColor.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: SiraatRadius.inner, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(SiraatSpacing.lg)
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
                Image(systemName: "chevron.up.chevron.down").font(SiraatType.caption)
            }
            .font(SiraatType.callout.weight(.medium))
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
                VStack(spacing: SiraatSpacing.xxs) {
                    Text("\(count)")
                        .font(SiraatType.heroNumeral)
                        .foregroundStyle(SiraatColor.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(count)))
                    Text("of \(target)")
                        .font(SiraatType.callout)
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
        withAnimation(.snappy(duration: 0.18)) {
            if count + 1 >= target {
                count = 0
                rounds += 1
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            } else {
                count += 1
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func reset() {
        count = 0
        rounds = 0
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
