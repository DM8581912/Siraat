import XCTest
@testable import Siraat

final class PhoneticBlueprintLoaderTests: XCTestCase {
    func testLoadsBundledAlFatihaBlueprints() {
        let loader = BundledPhoneticBlueprintLoader()
        XCTAssertNotNil(loader.blueprint(forVerseKey: "1:1"))
        XCTAssertNotNil(loader.blueprint(forVerseKey: "1:7"))
    }

    func testUnknownVerseKeyReturnsNil() {
        let loader = BundledPhoneticBlueprintLoader()
        XCTAssertNil(loader.blueprint(forVerseKey: "2:255"))
    }

    func testPlaceholderIsMarkedUnverified() throws {
        let loader = BundledPhoneticBlueprintLoader()
        let blueprint = try XCTUnwrap(loader.blueprint(forVerseKey: "1:1"))
        // The shipped placeholder must never claim to be verified religious data.
        XCTAssertFalse(blueprint.source.verified)
        XCTAssertFalse(blueprint.phonemes.isEmpty)
    }

    func testPhonemeCountMatchesBaseLetterClusters() throws {
        let loader = BundledPhoneticBlueprintLoader()
        let blueprint = try XCTUnwrap(loader.blueprint(forVerseKey: "1:1"))
        // The blueprint must have exactly one phoneme per base-letter cluster of the
        // authored text, so reading-order alignment lines up.
        let clusters = UthmaniCharacterMapper.clusters(in: blueprint.scriptUthmani)
        XCTAssertEqual(blueprint.phonemes.count, clusters.count)
    }

    func testMissingResourceYieldsEmptyLoader() {
        let loader = BundledPhoneticBlueprintLoader(bundle: .main, resource: "DoesNotExist")
        XCTAssertNil(loader.blueprint(forVerseKey: "1:1"))
    }
}
