import LocalAuthentication

@MainActor
protocol MacAuthenticating {
    func authenticate(reason: String) async throws
    func cancel()
}

@MainActor
final class MacAuthentication: MacAuthenticating {
    private var context: LAContext?

    func authenticate(reason: String) async throws {
        cancel()
        let context = LAContext()
        self.context = context
        context.localizedFallbackTitle = "Use Mac password"
        defer {
            context.invalidate()
            if self.context === context { self.context = nil }
        }
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? LAError(.authenticationFailed)
        }
        guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
            throw LAError(.authenticationFailed)
        }
    }

    func cancel() {
        context?.invalidate()
        context = nil
    }
}
