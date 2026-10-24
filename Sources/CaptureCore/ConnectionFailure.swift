import Foundation

public enum ConnectionFailure {
    public static func message(_ code: UInt32) -> String {
        guard code != 0 else { return "The remote PC ended the connection." }
        let reason: String
        switch code {
        case 0x20004, 0x20005: reason = "The PC hostname could not be found. Check its address and VPN connection."
        case 0x20006, 0x2000d: reason = "The PC could not be reached, or the connection was interrupted. Check the address, VPN and RDP port."
        case 0x20008: reason = "The secure connection was not established. Check the PC certificate and TLS configuration."
        case 0x20009, 0x20014, 0x20015, 0x2001b: reason = "Windows rejected the login. Use Enter login to check your username, domain and account password. Windows Hello PINs cannot be used."
        case 0x2000a, 0x20016, 0x20017, 0x2001a: reason = "This Windows account is not allowed to sign in through Remote Desktop."
        case 0x2000e, 0x2000f, 0x20013: reason = "Your Windows password has expired or must be changed. Change it on Windows before reconnecting."
        case 0x20012, 0x20018, 0x20019: reason = "Your Windows account is disabled, locked or expired. Check the account before trying again."
        case 0x2000b: reason = "The connection was cancelled."
        case 0x2000c, 0x2001e: reason = "The PC requires a security configuration that could not be negotiated. TLS and NLA remain enabled."
        case 0x2001c, 0x2001d: reason = "Windows is starting or did not finish opening the desktop. Try again shortly."
        default: reason = "The remote PC ended or refused the connection. Check its RDP availability and Windows account."
        }
        return "\(reason) (0x\(String(code, radix: 16)))"
    }
}
