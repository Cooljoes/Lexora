import XCTest
@testable import Lexora

final class InputTests: XCTestCase {
    func testInputValidation() throws {
        XCTAssertEqual(try PassageInput.clean("  leaf\n"), "leaf")
        for value in [" ", "中文", String(repeating: "a", count: 12_001)] {
            XCTAssertThrowsError(try PassageInput.clean(value))
        }
    }
    func testIndependentShareFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = ShareInbox(directory: directory)
        try inbox.enqueue("The first leaf.")
        try inbox.enqueue("The second leaf.")
        let texts = try inbox.files().map { try JSONDecoder().decode(SharedPassage.self, from: Data(contentsOf: $0)).text }
        XCTAssertEqual(Set(texts), ["The first leaf.", "The second leaf."])
    }
}
