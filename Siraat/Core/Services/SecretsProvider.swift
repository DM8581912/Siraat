import Foundation
import Security

protocol SecretsProviding {
    func value(for key: SecretKey) -> String?
    func store(_ value: String, for key: SecretKey) throws
}

enum SecretKey: String {
    case deeplAPIKey = "DEEPL_API_KEY"
    case googleTranslateAPIKey = "GOOGLE_TRANSLATE_API_KEY"
    case whisperAPIKey = "WHISPER_API_KEY"
    case quranContentAPIBaseURL = "QURAN_CONTENT_API_BASE_URL"
}

enum SecretsError: Error {
    case keychainWriteFailed(OSStatus)
}

final class SecretsProvider: SecretsProviding {
    func value(for key: SecretKey) -> String? {
        if let runtimeValue = keychainValue(for: key), !runtimeValue.isEmpty {
            return runtimeValue
        }

        if let infoValue = Bundle.main.object(forInfoDictionaryKey: key.rawValue) as? String,
           !infoValue.isEmpty,
           !infoValue.contains("$(") {
            return infoValue
        }

        if let environmentValue = ProcessInfo.processInfo.environment[key.rawValue], !environmentValue.isEmpty {
            return environmentValue
        }

        return nil
    }

    func store(_ value: String, for key: SecretKey) throws {
        let data = Data(value.utf8)
        let query = keychainQuery(for: key)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecretsError.keychainWriteFailed(status)
        }
    }

    private func keychainValue(for key: SecretKey) -> String? {
        var query = keychainQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private func keychainQuery(for key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrService as String: "Siraat.Secrets",
            kSecAttrAccount as String: key.rawValue
        ]
    }
}
