import Foundation
import Security

public protocol SecretStore: Sendable {
    func read(_ account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
    func delete(_ account: String) throws
}

public struct KeychainStore: SecretStore {
    private let service: String
    public init(service: String = "uz.macrdp.credentials") { self.service = service }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    public func read(_ account: String) throws -> Data? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw SecretError.keychain(status) }
        return data
    }

    public func write(_ data: Data, account: String) throws {
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query(account) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw SecretError.keychain(status) }
        var request = query(account)
        request[kSecValueData as String] = data
        request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(request as CFDictionary, nil)
        guard added == errSecSuccess else { throw SecretError.keychain(added) }
    }

    public func delete(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretError.keychain(status) }
    }
}

public enum SecretError: LocalizedError {
    case keychain(OSStatus), invalidPIN, corruptRecord, randomFailure, derivationFailure, wrongPIN, throttled(Int)
    public var errorDescription: String? {
        switch self {
        case .keychain(let code): return "Keychain could not complete the request (\(code)). Unlock your Mac login keychain and try again."
        case .invalidPIN: return "Use a PIN with 4–12 digits."
        case .corruptRecord: return "The saved app lock could not be read. No credentials have been opened."
        case .randomFailure, .derivationFailure: return "macOS could not prepare the app lock. Please try again."
        case .wrongPIN: return "Incorrect PIN. Try again."
        case .throttled(let seconds): return "Try again in \(seconds) seconds."
        }
    }
}
