import XCTest
@testable import Siraat

final class KhutbaLibraryTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "KhutbaTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSaveAndLoadRoundTrip() {
        let store = KhutbaLibraryStore(userDefaults: defaults)
        let session = KhutbaSession(
            date: Date(),
            title: "Friday Khutba",
            segments: [LiveSegment(sourceText: "الحمد لله", translatedText: "Praise be to Allah")]
        )
        store.save(session)

        let all = store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "Friday Khutba")
        XCTAssertEqual(all.first?.segments.first?.translatedText, "Praise be to Allah")
    }

    func testNewestFirstAndDelete() {
        let store = KhutbaLibraryStore(userDefaults: defaults)
        let first = KhutbaSession(date: Date(), title: "First", segments: [])
        let second = KhutbaSession(date: Date(), title: "Second", segments: [])
        store.save(first)
        store.save(second)

        XCTAssertEqual(store.all().map(\.title), ["Second", "First"])

        let remaining = store.delete(id: first.id)
        XCTAssertEqual(remaining.map(\.title), ["Second"])
    }
}
