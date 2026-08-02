import XCTest
@testable import OptTabCore

final class WindowMatcherTests: XCTestCase {
    private func win(_ id: UInt32, _ title: String,
                     x: CGFloat = 0, y: CGFloat = 0) -> WindowInfo {
        WindowInfo(id: id, title: title,
                   frame: CGRect(x: x, y: y, width: 800, height: 600),
                   layer: 0, isOnScreen: true, isMinimized: false)
    }
    private func ax(_ title: String, x: CGFloat = 0, y: CGFloat = 0,
                    minimized: Bool = false) -> AXWindowDescriptor {
        AXWindowDescriptor(title: title,
                           frame: CGRect(x: x, y: y, width: 800, height: 600),
                           isMinimized: minimized)
    }

    // タイトル完全一致で対応付け
    func testMatchByTitle() {
        let m = WindowMatcher.match(cg: [win(10, "Alpha"), win(20, "Beta")],
                                    ax: [ax("Beta"), ax("Alpha")])
        XCTAssertEqual(m, [10: 1, 20: 0])
    }

    // 同名タイトルが2枚 → フレームで区別
    func testDuplicateTitlesFallBackToFrame() {
        let m = WindowMatcher.match(
            cg: [win(10, "Same", x: 0), win(20, "Same", x: 1000)],
            ax: [ax("Same", x: 1000), ax("Same", x: 0)])
        XCTAssertEqual(m[10], 1)
        XCTAssertEqual(m[20], 0)
    }

    // タイトルもフレームも合わない残り物は前面順で割り当て
    func testLeftoversAssignedInOrder() {
        let m = WindowMatcher.match(cg: [win(10, "A", x: 0)],
                                    ax: [ax("違うタイトル", x: 5000)])
        XCTAssertEqual(m, [10: 0])
    }

    // AXが足りない場合、余ったCGウィンドウは対応なし
    func testUnmatchedCGWindowHasNoEntry() {
        let m = WindowMatcher.match(cg: [win(10, "A"), win(20, "B")],
                                    ax: [ax("A")])
        XCTAssertEqual(m[10], 0)
        XCTAssertNil(m[20])
    }

    // フレーム近似（20pt未満のズレは同一視）
    func testFrameApproximateMatch() {
        let m = WindowMatcher.match(cg: [win(10, "X", x: 0)],
                                    ax: [ax("", x: 10)])
        XCTAssertEqual(m, [10: 0])
    }
}
