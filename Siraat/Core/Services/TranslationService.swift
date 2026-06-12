import Foundation

protocol TranslationServicing {
    func translate(_ text: String, to language: TranslationLanguage) async throws -> String
}

enum TranslationProviderKind: String {
    case mock
    case deepL
}

enum TranslationServiceFactory {
    static func makeDefault(secretsProvider: SecretsProviding = SecretsProvider()) -> TranslationServicing {
        if let apiKey = secretsProvider.value(for: .deeplAPIKey), !apiKey.isEmpty {
            return DeepLTranslationService(secretsProvider: secretsProvider)
        }

        return MockTranslationService()
    }
}

enum TranslationError: LocalizedError {
    case emptyInput
    case providerNotConfigured
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "There is no text to translate yet."
        case .providerNotConfigured:
            "No translation provider is configured."
        case .invalidResponse:
            "The translation provider returned an invalid response."
        }
    }
}

final class MockTranslationService: TranslationServicing {
    private let phrasebook: [String: String] = [
        "الحمد لله": "All praise is due to Allah.",
        "بسم الله": "In the name of Allah.",
        "اتقوا الله": "Be mindful of Allah.",
        "الصلاة والسلام على رسول الله": "Peace and blessings be upon the Messenger of Allah."
    ]

    func translate(_ text: String, to language: TranslationLanguage) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyInput }

        try await Task.sleep(nanoseconds: 180_000_000)

        let normalized = ArabicTextNormalizer.normalize(trimmed)
        if language == .english,
           let match = phrasebook.first(where: { normalized.contains(ArabicTextNormalizer.normalize($0.key)) }) {
            return match.value
        }

        return "[\(language.displayName)] \(trimmed)"
    }
}

final class DeepLTranslationService: TranslationServicing {
    private let apiKey: String?
    private let session: URLSession

    init(secretsProvider: SecretsProviding = SecretsProvider(), session: URLSession = .shared) {
        self.apiKey = secretsProvider.value(for: .deeplAPIKey)
        self.session = session
    }

    func translate(_ text: String, to language: TranslationLanguage) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else {
            throw TranslationError.providerNotConfigured
        }

        var request = URLRequest(url: URL(string: "https://api-free.deepl.com/v2/translate")!)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let targetLanguage = language == .english ? "EN-US" : language.rawValue.uppercased()
        let body = "text=\(text.urlFormEncoded)&target_lang=\(targetLanguage)"
        request.httpBody = Data(body.utf8)

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(DeepLResponse.self, from: data)
        guard let translated = response.translations.first?.text else {
            throw TranslationError.invalidResponse
        }

        return translated
    }
}

private struct DeepLResponse: Decodable {
    struct Translation: Decodable {
        let text: String
    }

    let translations: [Translation]
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
