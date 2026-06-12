import XCTest
@testable import Siraat

final class TranslationServiceTests: XCTestCase {
    func testMockTranslationUsesPhrasebook() async throws {
        let service = MockTranslationService()

        let translated = try await service.translate("الحمد لله رب العالمين", to: .english)

        XCTAssertEqual(translated, "All praise is due to Allah.")
    }

    func testMockTranslationRejectsEmptyInput() async {
        let service = MockTranslationService()

        do {
            _ = try await service.translate("   ", to: .english)
            XCTFail("Expected empty input to throw")
        } catch TranslationError.emptyInput {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFactoryUsesMockWhenNoProviderKeyExists() {
        let service = TranslationServiceFactory.makeDefault(secretsProvider: FakeSecretsProvider(values: [:]))

        XCTAssertTrue(service is MockTranslationService)
    }

    func testFactoryUsesDeepLWhenKeyExists() {
        let service = TranslationServiceFactory.makeDefault(
            secretsProvider: FakeSecretsProvider(values: [.deeplAPIKey: "test-key"])
        )

        XCTAssertTrue(service is DeepLTranslationService)
    }
}

private struct FakeSecretsProvider: SecretsProviding {
    let values: [SecretKey: String]

    func value(for key: SecretKey) -> String? {
        values[key]
    }

    func store(_ value: String, for key: SecretKey) throws {}
}
