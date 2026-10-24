import Foundation
import XCTest
@testable import CaptureCore

final class VaultTests: XCTestCase {

private final class MemoryStore: SecretStore, @unchecked Sendable {
    private let mutex = NSLock()
    private var items: [String: Data] = [:]
    var failWrites = false
    func read(_ account: String) throws -> Data? { mutex.withLock { items[account] } }
    func write(_ data: Data, account: String) throws {
        try mutex.withLock {
            if failWrites { throw SecretError.keychain(-1) }
            items[account] = data
        }
    }
    func delete(_ account: String) throws { _ = mutex.withLock { items.removeValue(forKey: account) } }
}

func testNewVaultAndEveryRelaunchStartLocked() throws {
    let store = MemoryStore()
    let first = try AppVault(store: store)
    XCTAssertTrue(first.needsSetup && !first.isUnlocked)
    try first.setup(pin: "4927")
    XCTAssertTrue(first.isUnlocked)
    let second = try AppVault(store: store)
    XCTAssertTrue(!second.needsSetup && !second.isUnlocked)
    try second.unlock(pin: "4927")
    XCTAssertTrue(second.isUnlocked)
    second.lock()
    XCTAssertTrue(!second.isUnlocked)
}

func testPINValidationRejectsShortAndNonASCIIDigits() {
    for pin in ["", "123", "1234567890123", "12a456", "１２３４５６", "123 456"] {
        XCTAssertTrue(!PINRecord.valid(pin))
    }
    XCTAssertTrue(PINRecord.valid("843925"))
    XCTAssertTrue(PINRecord.valid("4927"))
}

func testSavedPasswordsRequireUnlockAndStayOutOfLockRecord() throws {
    let store = MemoryStore()
    let vault = try AppVault(store: store)
    let id = UUID()
    XCTAssertThrowsError(try vault.savePassword("test-only-placeholder", profile: id))
    try vault.setup(pin: "843925")
    try vault.savePassword("test-only-placeholder", profile: id)
    XCTAssertTrue(try vault.password(profile: id) == "test-only-placeholder")
    let record = try XCTUnwrap(try store.read("app-lock"))
    let text = try XCTUnwrap(String(data: record, encoding: .utf8))
    XCTAssertTrue(!text.contains("843925") && !text.contains("test-only-placeholder"))
    vault.lock()
    XCTAssertThrowsError(try vault.password(profile: id))
    XCTAssertThrowsError(try vault.forgetPassword(profile: id))
    try vault.unlock(pin: "843925")
    try vault.forgetPassword(profile: id)
    XCTAssertTrue(try vault.password(profile: id) == nil)
}

func testFailedAttemptsAreThrottledAcrossRelaunches() throws {
    let store = MemoryStore()
    let vault = try AppVault(store: store)
    try vault.setup(pin: "843925")
    vault.lock()
    let now = Date()
    for _ in 0..<5 { XCTAssertThrowsError(try vault.unlock(pin: "000000", now: now)) }
    let reopened = try AppVault(store: store)
    XCTAssertThrowsError(try reopened.unlock(pin: "843925", now: now))
    XCTAssertTrue(!reopened.isUnlocked)
    try reopened.unlock(pin: "843925", now: now.addingTimeInterval(31))
    XCTAssertTrue(reopened.isUnlocked)
}

func testPINChangeRequiresOldPINAndPreservesSavedCredentials() throws {
    let store = MemoryStore()
    let vault = try AppVault(store: store)
    try vault.setup(pin: "843925")
    let id = UUID()
    try vault.savePassword("test-only-placeholder", profile: id)
    XCTAssertThrowsError(try vault.changePIN(current: "000000", replacement: "951762"))
    try vault.changePIN(current: "843925", replacement: "951762")
    vault.lock()
    XCTAssertThrowsError(try vault.unlock(pin: "843925"))
    try vault.unlock(pin: "951762")
    XCTAssertTrue(try vault.password(profile: id) == "test-only-placeholder")
}

func testKeychainWriteFailureNeverUnlocksOrCreatesUnprotectedFallback() throws {
    let store = MemoryStore()
    let vault = try AppVault(store: store)
    store.failWrites = true
    XCTAssertThrowsError(try vault.setup(pin: "843925"))
    XCTAssertTrue(!vault.isUnlocked && vault.needsSetup)
    XCTAssertTrue(try store.read("app-lock") == nil)
}

func testCorruptKeychainRecordFailsClosed() throws {
    let store = MemoryStore()
    try store.write(Data("broken".utf8), account: "app-lock")
    XCTAssertThrowsError(try AppVault(store: store))
}

}
