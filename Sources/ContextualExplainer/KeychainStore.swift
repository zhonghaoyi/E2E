import Foundation
import Security

struct KeychainStore {
    private let service = "com.zhonghaoyi.contextual-explainer"
    private let legacyAccount = "llm-api-key"

    func loadAPIKey(for provider: LLMProvider) -> String {
        let providerKey = loadAPIKey(account: account(for: provider))
        if !providerKey.isEmpty {
            return providerKey
        }

        let legacyKey = loadAPIKey(account: legacyAccount)
        guard !legacyKey.isEmpty else { return "" }

        if provider == .openRouter, legacyKey.hasPrefix("sk-or-") {
            return legacyKey
        }

        if provider == .openAI, !legacyKey.hasPrefix("sk-or-") {
            return legacyKey
        }

        return ""
    }

    func saveAPIKey(_ apiKey: String, for provider: LLMProvider) throws {
        try saveAPIKey(apiKey, account: account(for: provider))
    }

    func loadAPIKey() -> String {
        loadAPIKey(account: legacyAccount)
    }

    func saveAPIKey(_ apiKey: String) throws {
        try saveAPIKey(apiKey, account: legacyAccount)
    }

    func deleteAPIKey(for provider: LLMProvider) {
        deleteAPIKey(account: account(for: provider))
    }

    func deleteAPIKey() {
        deleteAPIKey(account: legacyAccount)
    }

    private func loadAPIKey(account: String) -> String {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func saveAPIKey(_ apiKey: String, account: String) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            deleteAPIKey(account: account)
            return
        }

        let data = Data(trimmedKey.utf8)
        var query = baseQuery(account: account)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw keychainError(addStatus)
            }
            return
        }

        if status != errSecSuccess {
            throw keychainError(status)
        }
    }

    private func deleteAPIKey(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private func account(for provider: LLMProvider) -> String {
        switch provider {
        case .openRouter:
            return "openrouter-api-key"
        case .openAI:
            return "openai-api-key"
        case .deepSeek:
            return "deepseek-api-key"
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
    }

    private func keychainError(_ status: OSStatus) -> NSError {
        NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"]
        )
    }
}
