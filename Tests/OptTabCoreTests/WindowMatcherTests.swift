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

    // タイトルもフレームも合わない残り物は割り当てない（誤マッチで無関係な要素を
    // Raiseするより、未対応としてメニュー/除外フォールバックに回す方が安全）
    func testLeftoversAreNotAssigned() {
        let m = WindowMatcher.match(cg: [win(10, "A", x: 0)],
                                    ax: [ax("違うタイトル", x: 5000)])
        XCTAssertTrue(m.isEmpty)
    }

    // eligibleAXIndices: タイトル空かつ極小のAXウィンドウ（タブバー等の付属要素）を除外
    func testEligibleAXIndicesExcludesTinyUntitled() {
        let tabbar = AXWindowDescriptor(title: "",
                                        frame: CGRect(x: 0, y: 0, width: 1512, height: 33),
                                        isMinimized: false)
        let real = ax("Terminal")
        XCTAssertEqual(WindowMatcher.eligibleAXIndices([tabbar, real]), [1])
    }

    // eligibleAXIndices: タイトル空でも大きければ残す
    func testEligibleAXIndicesKeepsLargeUntitled() {
        let big = AXWindowDescriptor(title: "",
                                     frame: CGRect(x: 0, y: 0, width: 1200, height: 800),
                                     isMinimized: false)
        XCTAssertEqual(WindowMatcher.eligibleAXIndices([big]), [0])
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
