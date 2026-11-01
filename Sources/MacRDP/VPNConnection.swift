import Foundation
import SystemConfiguration

struct VPNProfile: Identifiable, Equatable {
    let id: String
    let name: String
    var isKerio = false
}

enum VPNStatus { case disconnected, connecting, connected, disconnecting, invalid }

@MainActor
protocol VPNConnecting: AnyObject {
    var status: VPNStatus { get }
}

@MainActor
final class SystemVPNConnection: VPNConnecting {
    private let connection: SCNetworkConnection
    init?(id: String) {
        guard let connection = SCNetworkConnectionCreateWithServiceID(nil, id as CFString, nil, nil) else { return nil }
        self.connection = connection
    }
    var status: VPNStatus {
        switch SCNetworkConnectionGetStatus(connection) {
        case .disconnected: .disconnected
        case .connecting: .connecting
        case .connected: .connected
        case .disconnecting: .disconnecting
        default: .invalid
        }
    }
    static func profiles() -> [VPNProfile] {
        guard let preferences = SCPreferencesCreate(nil, "MacRDP VPN selection" as CFString, nil),
              let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] else { return [] }
        let kerioNames = KerioProfileNames.readNames()
        return services.compactMap { service in
            guard SCNetworkServiceGetEnabled(service),
                  let interface = SCNetworkServiceGetInterface(service),
                  let type = SCNetworkInterfaceGetInterfaceType(interface) as String?,
                  type == "VPN" || type == "IPSec" || (type == "PPP" && {
                      guard let underlying = SCNetworkInterfaceGetInterface(interface),
                            let subtype = SCNetworkInterfaceGetInterfaceType(underlying) as String? else { return false }
                      return subtype == "L2TP" || subtype == "PPTP"
                  }()),
                  let id = SCNetworkServiceGetServiceID(service) as String?,
                  let name = SCNetworkServiceGetName(service) as String?,
                  let connection = SystemVPNConnection(id: id), connection.status != .invalid else { return nil }
            let metadata = SCPreferencesPathGetValue(preferences, ("/NetworkServices/" + id + "/Interface") as CFString) as? [String: Any]
            let isKerio = metadata?["SubType"] as? String == "com.kerio.VPN.ie.agent"
            if isKerio,
               kerioNames?.contains(name) != true { return nil }
            return VPNProfile(id: id, name: name, isKerio: isKerio)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

enum VPNError: LocalizedError {
    case unavailable
    var errorDescription: String? { "The selected VPN is unavailable. Edit this PC and select an installed VPN profile." }
}

@MainActor
final class SessionVPN {
    private let makeConnection: (String) -> (any VPNConnecting)?
    private let pause: () async throws -> Void
    private var generation = UUID()

    init(makeConnection: @escaping (String) -> (any VPNConnecting)? = { SystemVPNConnection(id: $0) },
         pause: @escaping () async throws -> Void = { try await Task.sleep(for: .milliseconds(500)) }) {
        self.makeConnection = makeConnection
        self.pause = pause
    }

    func waitUntilConnected(id: String?) async throws {
        try Task.checkCancellation()
        guard let id else { return }
        guard let connection = makeConnection(id) else { throw VPNError.unavailable }
        let request = generation
        while true {
            try Task.checkCancellation()
            guard request == generation else { throw CancellationError() }
            switch connection.status {
            case .connected: return
            case .invalid: throw VPNError.unavailable
            case .disconnected, .connecting, .disconnecting: break
            }
            try await pause()
        }
    }

    func cancelWait() { generation = UUID() }
}
