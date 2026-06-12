import Foundation

/// A reference to one ayah (surah:ayah).
struct AyahRef: Hashable {
    let surah: Int
    let ayah: Int
}

/// A well-known supplication taken directly from the Qur'an. Text is resolved at runtime
/// from the bundled Qur'an (verified Uthmani Arabic + Saheeh International translation), so
/// nothing here is hand-written scripture — only the references and human-readable titles.
struct QuranicDua: Identifiable, Hashable {
    let id: Int
    let title: String
    let ayahs: [AyahRef]

    var reference: String {
        guard let first = ayahs.first, let last = ayahs.last else { return "" }
        if ayahs.count == 1 { return "Qur'an \(first.surah):\(first.ayah)" }
        return "Qur'an \(first.surah):\(first.ayah)-\(last.ayah)"
    }
}

enum QuranicDuas {
    static let all: [QuranicDua] = [
        QuranicDua(id: 1, title: "Guidance to the straight path", ayahs: [AyahRef(surah: 1, ayah: 6), AyahRef(surah: 1, ayah: 7)]),
        QuranicDua(id: 2, title: "The best of this world and the next", ayahs: [AyahRef(surah: 2, ayah: 201)]),
        QuranicDua(id: 3, title: "Patience and firm footing", ayahs: [AyahRef(surah: 2, ayah: 250)]),
        QuranicDua(id: 4, title: "Forgiveness, mercy, and our burdens", ayahs: [AyahRef(surah: 2, ayah: 286)]),
        QuranicDua(id: 5, title: "Keep our hearts firm upon guidance", ayahs: [AyahRef(surah: 3, ayah: 8)]),
        QuranicDua(id: 6, title: "Forgive our sins and save us from the Fire", ayahs: [AyahRef(surah: 3, ayah: 16)]),
        QuranicDua(id: 7, title: "Allah is sufficient for us", ayahs: [AyahRef(surah: 3, ayah: 173)]),
        QuranicDua(id: 8, title: "Mercy and right guidance in our affair", ayahs: [AyahRef(surah: 18, ayah: 10)]),
        QuranicDua(id: 9, title: "Lord, increase me in knowledge", ayahs: [AyahRef(surah: 20, ayah: 114)]),
        QuranicDua(id: 10, title: "Ease for the task ahead", ayahs: [AyahRef(surah: 20, ayah: 25), AyahRef(surah: 20, ayah: 26), AyahRef(surah: 20, ayah: 27), AyahRef(surah: 20, ayah: 28)]),
        QuranicDua(id: 11, title: "Comfort in spouse and children", ayahs: [AyahRef(surah: 25, ayah: 74)]),
        QuranicDua(id: 12, title: "The supplication of Yunus in distress", ayahs: [AyahRef(surah: 21, ayah: 87)]),
        QuranicDua(id: 13, title: "Forgive me, my parents, and the believers", ayahs: [AyahRef(surah: 14, ayah: 41)])
    ]
}
