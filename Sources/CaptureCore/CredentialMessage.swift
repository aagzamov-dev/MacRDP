import Foundation

public struct CredentialRequest: Codable, Sendable {
    public enum Operation: String, Codable, Sendable { case read, write, delete }
    public let operation: Operation
    public let account: String
    public let data: Data?
    public init(operation: Operation, account: String, data: Data? = nil) {
        self.operation = operation; self.account = account; self.data = data
    }
}

public struct CredentialResponse: Codable, Sendable {
    public let status: Int32
    public let data: Data?
    public init(status: Int32, data: Data? = nil) { self.status = status; self.data = data }
}
