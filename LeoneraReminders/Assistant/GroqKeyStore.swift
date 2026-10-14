import Foundation
import Observation
import Security

/// La clave de API de Groq, guardada en el llavero (sólo en este dispositivo, no va en copias de seguridad).
@MainActor
@Observable
final class GroqKeyStore {
    static let shared = GroqKeyStore()

    private(set) var hasKey: Bool
    private(set) var lastError: String?

    private static let service = "LeoneraReminders.groq"
    private static let account = "apiKey"

    private init() {
        hasKey = Self.read() != nil
    }

    var key: String? { Self.read() }

    /// Guarda (o reemplaza) la clave. Devuelve `false` si está vacía o el llavero la rechazó.
    @discardableResult
    func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        SecItemDelete(Self.query as CFDictionary)
        var attributes = Self.query
        attributes[kSecValueData as String] = Data(trimmed.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        hasKey = status == errSecSuccess
        lastError = hasKey ? nil : "No se pudo guardar la clave en el llavero (error \(status))."
        return hasKey
    }

    func delete() {
        SecItemDelete(Self.query as CFDictionary)
        hasKey = false
        lastError = nil
    }

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read() -> String? {
        var query = Self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else { return nil }
        return key
    }
}
