import Foundation

public enum WindowsClipboardText {
    public static func decode(_ data: Data) -> String? {
        guard data.count >= 2, data.count <= 16 * 1024 * 1024, data.count.isMultiple(of: 2) else { return nil }
        var end = data.startIndex
        while end < data.endIndex {
            if data[end] == 0 && data[end + 1] == 0 {
                return String(data: data[data.startIndex..<end], encoding: .utf16LittleEndian)?
                    .replacingOccurrences(of: "\r\n", with: "\n")
            }
            end += 2
        }
        return nil
    }
}
