import XCTest
@testable import Siraat

final class QuranicDuasTests: XCTestCase {
    /// Verifies every dua's verse reference resolves to a real ayah in the bundled Qur'an,
    /// with non-empty Arabic + translation. This guards against a mistyped reference
    /// pointing the user at the wrong (or a non-existent) verse.
    func testAllDuaReferencesResolve() async {
        let manager = QuranDatabaseManager()
        XCTAssertFalse(QuranicDuas.all.isEmpty)

        for dua in QuranicDuas.all {
            XCTAssertFalse(dua.ayahs.isEmpty, "\(dua.title) has no ayahs")
            for ref in dua.ayahs {
                let verse = await manager.ayah(surah: ref.surah, ayah: ref.ayah)
                XCTAssertNotNil(verse, "\(dua.title): \(ref.surah):\(ref.ayah) does not resolve")
                XCTAssertFalse(verse?.textUthmani.isEmpty ?? true, "\(ref.surah):\(ref.ayah) has empty Arabic")
                XCTAssertFalse(verse?.translation.isEmpty ?? true, "\(ref.surah):\(ref.ayah) has empty translation")
            }
        }
    }
}
