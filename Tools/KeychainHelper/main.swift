import Foundation
import Security
import CryptoKit
import Darwin

func authorizedParent() -> Bool {
    let parentPID = getppid()
    guard parentPID > 1 else { return false }
    var ownCode: SecCode?
    var ownStatic: SecStaticCode?
    var info: CFDictionary?
    guard SecCodeCopySelf([], &ownCode) == errSecSuccess, let ownCode,
          SecCodeCopyStaticCode(ownCode, [], &ownStatic) == errSecSuccess, let ownStatic,
          SecCodeCopySigningInformation(ownStatic, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let certificates = (info as? [String: Any])?[kSecCodeInfoCertificates as String] as? [SecCertificate],
          let certificate = certificates.first else { return false }
    let fingerprint = Insecure.SHA1.hash(data: SecCertificateCopyData(certificate) as Data).map { String(format: "%02x", $0) }.joined()
    let expression = "identifier \"uz.macrdp.app\" and certificate leaf = H\"\(fingerprint)\""
    var requirement: SecRequirement?
    var parent: SecCode?
    guard SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
          SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: parentPID] as CFDictionary, [], &parent) == errSecSuccess,
          let parent, let requirement,
          SecCodeCheckValidity(parent, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else { return false }
    return getppid() == parentPID
}

func respond(_ response: CredentialResponse) {
    if let data = try? JSONEncoder().encode(response) { try? FileHandle.standardOutput.write(contentsOf: data) }
}

guard authorizedParent() else { respond(CredentialResponse(status: errSecAuthFailed)); exit(1) }
#if SIGNING_TEST
SecKeychainSetUserInteractionAllowed(false)
let store = KeychainStore(service: "uz.macrdp.signing-helper-test")
#else
let store = KeychainStore()
#endif

do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard input.count <= 131_072 else { throw SecretError.keychain(errSecParam) }
    let request = try JSONDecoder().decode(CredentialRequest.self, from: input)
    let validAccount = request.account == "app-lock" || (request.account.hasPrefix("pc-") && UUID(uuidString: String(request.account.dropFirst(3))) != nil)
    guard validAccount else { throw SecretError.keychain(errSecParam) }
    switch request.operation {
    case .read: respond(CredentialResponse(status: errSecSuccess, data: try store.read(request.account)))
    case .write:
        guard let data = request.data, data.count <= 65_536 else { throw SecretError.keychain(errSecParam) }
        try store.write(data, account: request.account)
        respond(CredentialResponse(status: errSecSuccess))
    case .delete:
        try store.delete(request.account)
        respond(CredentialResponse(status: errSecSuccess))
    }
} catch SecretError.keychain(let status) {
    respond(CredentialResponse(status: status))
} catch {
    respond(CredentialResponse(status: errSecParam))
}
