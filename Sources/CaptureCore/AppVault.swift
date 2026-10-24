import Foundation
import CommonCrypto
import Security

public struct PINRecord: Codable, Sendable {
    public let salt: Data
    public let digest: Data
    public let rounds: UInt32

    public static func create(_ pin: String) throws -> PINRecord {
        guard valid(pin) else { throw SecretError.invalidPIN }
        var salt = Data(count: 32)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard status == errSecSuccess else { throw SecretError.randomFailure }
        let rounds: UInt32 = 600_000
        return PINRecord(salt: salt, digest: try derive(pin, salt: salt, rounds: rounds), rounds: rounds)
    }

    public static func valid(_ pin: String) -> Bool {
        (4...12).contains(pin.utf8.count) && pin.utf8.allSatisfy { (48...57).contains($0) }
    }

    public func matches(_ pin: String) throws -> Bool {
        guard salt.count == 32, digest.count == 32, (600_000...2_000_000).contains(rounds) else {
            throw SecretError.corruptRecord
        }
        guard Self.valid(pin) else { return false }
        let candidate = try Self.derive(pin, salt: salt, rounds: rounds)
        return zip(candidate, digest).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func derive(_ pin: String, salt: Data, rounds: UInt32) throws -> Data {
        var result = Data(count: 32)
        let count = pin.utf8.count
        let status = pin.withCString { password in
            salt.withUnsafeBytes { bytes in
                result.withUnsafeMutableBytes { output in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, count,
                        bytes.bindMemory(to: UInt8.self).baseAddress!, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                        output.bindMemory(to: UInt8.self).baseAddress!, 32)
                }
            }
        }
        guard status == kCCSuccess else { throw SecretError.derivationFailure }
        return result
    }
}

public struct LockRecord: Codable, Sendable {
    public var pin: PINRecord
    public var failures = 0
    public var nextAttempt = Date.distantPast
}

public final class AppVault {
    private let store: any SecretStore
    private var record: LockRecord?
    public private(set) var isUnlocked = false
    public var needsSetup: Bool { record == nil }

    public init(store: any SecretStore = KeychainStore()) throws {
        self.store = store
        if let data = try store.read("app-lock") {
            do { record = try JSONDecoder().decode(LockRecord.self, from: data) }
            catch { throw SecretError.corruptRecord }
        }
    }

    public func setup(pin: String) throws {
        guard needsSetup else { throw SecretError.corruptRecord }
        let newRecord = LockRecord(pin: try PINRecord.create(pin))
        try save(newRecord)
        isUnlocked = true
    }

    public func unlock(pin: String, now: Date = Date()) throws {
        guard var record else { throw SecretError.corruptRecord }
        guard now >= record.nextAttempt else {
            throw SecretError.throttled(Int(ceil(record.nextAttempt.timeIntervalSince(now))))
        }
        if try record.pin.matches(pin) {
            record.failures = 0
            record.nextAttempt = .distantPast
            try save(record)
            isUnlocked = true
        } else {
            record.failures = min(record.failures + 1, 20)
            let delay = record.failures < 5 ? 0 : min(300, pow(2, Double(record.failures - 5)) * 30)
            record.nextAttempt = now.addingTimeInterval(delay)
            try save(record)
            throw SecretError.wrongPIN
        }
    }

    public func lock() { isUnlocked = false }

    public func savePassword(_ password: String, profile: UUID) throws {
        guard isUnlocked else { throw SecretError.wrongPIN }
        try store.write(Data(password.utf8), account: "pc-\(profile.uuidString)")
    }

    public func password(profile: UUID) throws -> String? {
        guard isUnlocked else { throw SecretError.wrongPIN }
        guard let data = try store.read("pc-\(profile.uuidString)") else { return nil }
        guard let value = String(data: data, encoding: .utf8) else { throw SecretError.corruptRecord }
        return value
    }

    public func forgetPassword(profile: UUID) throws {
        guard isUnlocked else { throw SecretError.wrongPIN }
        try store.delete("pc-\(profile.uuidString)")
    }

    public func changePIN(current: String, replacement: String) throws {
        guard isUnlocked else { throw SecretError.wrongPIN }
        try unlock(pin: current)
        let newRecord = LockRecord(pin: try PINRecord.create(replacement))
        try save(newRecord)
    }

    private func save(_ record: LockRecord) throws {
        try store.write(JSONEncoder().encode(record), account: "app-lock")
        self.record = record
    }
}
