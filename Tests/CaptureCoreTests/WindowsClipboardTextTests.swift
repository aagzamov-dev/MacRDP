import XCTest
@testable import CaptureCore

final class WindowsClipboardTextTests: XCTestCase {
    func testUnicodeAndWindowsNewlines() throws {
        let text = "Hello, O‘zbekcha — Привет — 你好 👋\r\nSecond line\r\n"
        let data = try XCTUnwrap((text + "\0").data(using: .utf16LittleEndian))
        XCTAssertEqual(WindowsClipboardText.decode(data), text.replacingOccurrences(of: "\r\n", with: "\n"))
    }

    func testTerminatorAndEmptyText() throws {
        XCTAssertEqual(WindowsClipboardText.decode(Data([0, 0])), "")
        let data = try XCTUnwrap("A\0ignored".data(using: .utf16LittleEndian))
        XCTAssertEqual(WindowsClipboardText.decode(data), "A")
        XCTAssertEqual(WindowsClipboardText.decode(Data([0, 1, 0, 0])), "Ā")
    }

    func testMalformedAndOversizedResponses() {
        for data in [Data(), Data([65]), Data([65, 0]), Data([65, 0, 0]),
                     Data([0, 0xD8, 0, 0]), Data([0, 0xDC, 0, 0]),
                     Data(repeating: 0, count: 16 * 1024 * 1024 + 2)] {
            XCTAssertNil(WindowsClipboardText.decode(data))
        }
    }
}
