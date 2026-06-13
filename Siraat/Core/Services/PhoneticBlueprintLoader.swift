import Foundation

/// Supplies the canonical phonetic blueprint for an ayah, keyed by verse key ("S:A").
protocol PhoneticBlueprintProviding {
    func blueprint(forVerseKey verseKey: String) -> AyahPhonemeMap?
}

/// Loads `TajweedBlueprints.json` from the app bundle once and caches it by verse key.
/// Returns `nil` for any ayah not present — today that is everything except the
/// Al-Fatiha placeholder, so the colored-ayah feature is inert elsewhere.
final class BundledPhoneticBlueprintLoader: PhoneticBlueprintProviding {
    private let maps: [String: AyahPhonemeMap]

    init(bundle: Bundle = .main, resource: String = "TajweedBlueprints") {
        guard
            let url = bundle.url(forResource: resource, withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let file = try? JSONDecoder().decode(PhoneticBlueprintFile.self, from: data)
        else {
            maps = [:]
            return
        }

        maps = Dictionary(file.ayahs.map { ($0.verseKey, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func blueprint(forVerseKey verseKey: String) -> AyahPhonemeMap? {
        maps[verseKey]
    }
}

/// Test/preview double.
final class MockPhoneticBlueprintProvider: PhoneticBlueprintProviding {
    private let maps: [String: AyahPhonemeMap]

    init(maps: [String: AyahPhonemeMap] = [:]) {
        self.maps = maps
    }

    func blueprint(forVerseKey verseKey: String) -> AyahPhonemeMap? {
        maps[verseKey]
    }
}
