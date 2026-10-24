import Foundation
import Security

#if BUILD_TWO
let buildVersion = 2
#else
let buildVersion = 1
#endif

let args = CommandLine.arguments
guard args.count == 4 else { exit(2) }
let operation = args[3]
let payload = Data("synthetic-credential-only".utf8)
let request = CredentialRequest(operation: operation == "denied" ? .read : CredentialRequest.Operation(rawValue: operation)!, account: args[2], data: operation == "write" ? payload : nil)
let process = Process()
process.executableURL = URL(fileURLWithPath: args[1])
let input = Pipe(); let output = Pipe()
process.standardInput = input; process.standardOutput = output
try process.run()
try input.fileHandleForWriting.write(contentsOf: JSONEncoder().encode(request))
try input.fileHandleForWriting.close()
let result = output.fileHandleForReading.readDataToEndOfFile()
process.waitUntilExit()
let response = try JSONDecoder().decode(CredentialResponse.self, from: result)
if operation == "denied" {
    guard response.status == errSecAuthFailed && response.data == nil else { fatalError("Untrusted caller was accepted") }
} else {
    guard response.status == errSecSuccess, process.terminationStatus == 0 else { fatalError("Fixture host v\(buildVersion): \(response.status)") }
    if operation == "read" { guard response.data == payload else { fatalError("Synthetic data was not preserved") } }
}
