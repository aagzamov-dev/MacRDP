import AVFoundation

@MainActor
struct MicrophoneAccess {
    var authorizationStatus: () -> AVAuthorizationStatus
    var request: () async -> Bool

    static let live = MicrophoneAccess(
        authorizationStatus: { AVCaptureDevice.authorizationStatus(for: .audio) },
        request: {
            await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    )

    func authorize() async -> Bool {
        switch authorizationStatus() {
        case .authorized: return true
        case .notDetermined: return await request()
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }

    static let recoveryMessage = "Mac microphone access is unavailable. Enable Microphone for this app in System Settings → Privacy & Security → Microphone, then reconnect. To connect without a microphone, turn off ‘Use Mac microphone in Windows’ in this PC’s settings."
}
