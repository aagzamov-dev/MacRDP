import Foundation

public struct PCProfile: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name = "Windows PC"
    public var host = ""
    public var port = "3389"
    public var username = ""
    public var domain = ""
    public var rememberPassword = true
    public var optimizeRetina = true
    public var desktopScale = 0
    public var openFullScreen = true

    public init() {}
    public var endpoint: String { "\(host.lowercased()):\(port)" }
    public var credentialIdentity: String { "\(endpoint)|\(domain.lowercased())|\(username.lowercased())" }
    public var validationError: String? {
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a PC address or hostname." }
        if host.contains("://") || host.contains("/") { return "Enter a hostname or IP address without a URL or path." }
        guard let value = UInt16(port), value > 0 else { return "Use a port between 1 and 65535." }
        if desktopScale != 0 && !(100...500).contains(desktopScale) { return "Windows scaling must be between 100% and 500%." }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, domain, rememberPassword, optimizeRetina, desktopScale, openFullScreen
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Windows PC"
        host = try c.decode(String.self, forKey: .host)
        port = try c.decodeIfPresent(String.self, forKey: .port) ?? "3389"
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        domain = try c.decodeIfPresent(String.self, forKey: .domain) ?? ""
        rememberPassword = try c.decodeIfPresent(Bool.self, forKey: .rememberPassword) ?? true
        optimizeRetina = try c.decodeIfPresent(Bool.self, forKey: .optimizeRetina) ?? true
        desktopScale = try c.decodeIfPresent(Int.self, forKey: .desktopScale) ?? 0
        openFullScreen = try c.decodeIfPresent(Bool.self, forKey: .openFullScreen) ?? true
    }
}

public struct PCStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() throws -> [PCProfile] {
        if let data = defaults.data(forKey: "pcs") { return try JSONDecoder().decode([PCProfile].self, from: data) }
        if let legacy = defaults.data(forKey: "savedPC") {
            let pc = try JSONDecoder().decode(PCProfile.self, from: legacy)
            try save([pc])
            return [pc]
        }
        return []
    }
    public func save(_ profiles: [PCProfile]) throws {
        defaults.set(try JSONEncoder().encode(profiles), forKey: "pcs")
    }
}

public struct DisplayLayout: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var desktopScale: Int
    public let deviceScale = 100
    public init(points: CGSize, backing: CGSize, retina: Bool, scale: Int) {
        let pixels = retina ? backing : points
        width = Int(max(200, min(8192, pixels.width.isFinite ? pixels.width : 200))) / 2 * 2
        height = Int(max(200, min(8192, pixels.height.isFinite ? pixels.height : 200)))
        let factor = points.width > 0 ? backing.width / points.width : 1
        let automatic = factor.isFinite ? Int(max(100, min(500, (factor * 100).rounded()))) : 100
        desktopScale = scale == 0 ? (retina ? automatic : 100) : max(100, min(500, scale))
    }
}

public struct RemoteGeometry: Sendable {
    public var bounds: CGRect
    public var remote: CGSize
    public init(bounds: CGRect, remote: CGSize) { self.bounds = bounds; self.remote = remote }
    public var imageRect: CGRect {
        guard remote.width > 0, remote.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let ratio = min(bounds.width / remote.width, bounds.height / remote.height)
        let size = CGSize(width: remote.width * ratio, height: remote.height * ratio)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
    public func point(_ local: CGPoint, clamp: Bool = false) -> CGPoint? {
        let rect = imageRect
        guard rect.width > 0, rect.height > 0, clamp || rect.contains(local) else { return nil }
        return CGPoint(x: max(0, min(remote.width - 1, floor((local.x - rect.minX) / rect.width * remote.width))),
                       y: max(0, min(remote.height - 1, floor((local.y - rect.minY) / rect.height * remote.height))))
    }
}

public enum GestureMapping: String, CaseIterable, Codable, Sendable {
    case disabled, macDesktops, windowsDesktops, taskView
    public var title: String {
        switch self {
        case .disabled: return "Disabled"
        case .macDesktops: return "Mac desktops / release input"
        case .windowsDesktops: return "Windows desktops (left/right)"
        case .taskView: return "Windows Task View"
        }
    }
}

public enum MacScanCode {
    private static let values: [UInt16: UInt32] = [
            0:0x1e,1:0x1f,2:0x20,3:0x21,4:0x23,5:0x22,6:0x2c,7:0x2d,8:0x2e,9:0x2f,
            11:0x30,12:0x10,13:0x11,14:0x12,15:0x13,16:0x15,17:0x14,18:0x02,19:0x03,
            20:0x04,21:0x05,22:0x07,23:0x06,24:0x0d,25:0x0a,26:0x08,27:0x0c,28:0x09,
            29:0x0b,30:0x1b,31:0x18,32:0x16,33:0x1a,34:0x17,35:0x19,36:0x1c,37:0x26,
            38:0x24,39:0x28,40:0x25,41:0x27,42:0x2b,43:0x33,44:0x35,45:0x31,46:0x32,
            47:0x34,48:0x0f,49:0x39,50:0x29,51:0x0e,53:0x01,54:0x15c,55:0x15b,56:0x2a,
            57:0x3a,58:0x38,59:0x1d,60:0x36,61:0x138,62:0x11d,65:0x53,67:0x37,
            69:0x4e,71:0x45,75:0x135,76:0x11c,78:0x4a,81:0x59,82:0x52,83:0x4f,
            84:0x50,85:0x51,86:0x4b,87:0x4c,88:0x4d,89:0x47,91:0x48,92:0x49,
            96:0x3f,97:0x40,98:0x41,99:0x3d,100:0x42,101:0x43,103:0x57,109:0x44,
            111:0x58,114:0x152,115:0x147,116:0x149,117:0x153,118:0x3e,119:0x14f,
            120:0x3c,121:0x151,122:0x3b,123:0x14b,124:0x14d,125:0x150,126:0x148]
    public static func code(_ key: UInt16) -> UInt32? { values[key] }
}
