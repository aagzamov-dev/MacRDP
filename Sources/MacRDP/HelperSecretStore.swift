import Foundation
import Security
import CryptoKit

struct HelperSecretStore: SecretStore {
    func read(_ account: String) throws -> Data? {
        try perform(CredentialRequest(operation: .read, account: account)).data
    }
    func write(_ data: Data, account: String) throws {
        _ = try perform(CredentialRequest(operation: .write, account: account, data: data))
    }
    func delete(_ account: String) throws {
        _ = try perform(CredentialRequest(operation: .delete, account: account))
    }
    private func verifyHelper(_ url: URL) throws {
        var ownCode: SecCode?
        var ownStatic: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &ownCode) == errSecSuccess, let ownCode,
              SecCodeCopyStaticCode(ownCode, [], &ownStatic) == errSecSuccess, let ownStatic,
              SecCodeCopySigningInformation(ownStatic, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let certificates = (info as? [String: Any])?[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let certificate = certificates.first else { throw SecretError.keychain(errSecAuthFailed) }
        let fingerprint = Insecure.SHA1.hash(data: SecCertificateCopyData(certificate) as Data).map { String(format: "%02x", $0) }.joined()
        var requirement: SecRequirement?
        var helper: SecStaticCode?
        let expression = "identifier \"uz.macrdp.keychain\" and certificate leaf = H\"\(fingerprint)\""
        guard SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(url as CFURL, [], &helper) == errSecSuccess,
              let helper, let requirement,
              SecStaticCodeCheckValidity(helper, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else { throw SecretError.keychain(errSecAuthFailed) }
    }
    private func perform(_ request: CredentialRequest) throws -> CredentialResponse {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/MacRDPKeychain")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { throw SecretError.keychain(errSecNotAvailable) }
        try verifyHelper(helper)
        let process = Process()
        let input = Pipe(); let output = Pipe()
        process.executableURL = helper
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let encoded = try JSONEncoder().encode(request)
        guard encoded.count <= 131_072 else { throw SecretError.keychain(errSecParam) }
        try process.run()
        do {
            try input.fileHandleForWriting.write(contentsOf: encoded)
            try input.fileHandleForWriting.close()
        } catch {
            try? input.fileHandleForWriting.close()
            process.terminate()
            process.waitUntilExit()
            throw error
        }
        let result = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard result.count <= 131_072,
              let response = try? JSONDecoder().decode(CredentialResponse.self, from: result) else { throw SecretError.keychain(errSecNotAvailable) }
        guard response.status == errSecSuccess else { throw SecretError.keychain(response.status) }
        guard process.terminationStatus == 0 else { throw SecretError.keychain(errSecAuthFailed) }
        return response
    }
}
