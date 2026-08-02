import XCTest
@testable import OptTabCore

final class WindowOrderingTests: XCTestCase {
    func testScaffold() {
        XCTAssertEqual(WindowInfo(id: 1, title: "a", frame: .zero, layer: 0,
                                  isOnScreen: true, isMinimized: false).id, 1)
    }
}
