import Foundation

@MainActor
enum AppRestart {
    static let waitForExitScript = """
    attempts=0
    while kill -0 "$1" 2>/dev/null; do
        attempts=$((attempts + 1))
        [ "$attempts" -lt 300 ] || exit 75
        sleep 0.1
    done
    shift
    exec "$@"
    """

    static func schedule(bundleURL: URL, parentPID: Int32 = ProcessInfo.processInfo.processIdentifier) throws {
        guard bundleURL.pathExtension == "app", FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", waitForExitScript, "MacRDP restart", String(parentPID), "/usr/bin/open", "-n", bundleURL.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
