import XCTest
@testable import OptTabCore

final class WindowOrderingTests: XCTestCase {
    private func win(_ id: UInt32, _ title: String = "w",
                     w: CGFloat = 800, h: CGFloat = 600,
                     layer: Int = 0) -> WindowInfo {
        WindowInfo(id: id, title: title,
                   frame: CGRect(x: 0, y: 0, width: w, height: h),
                   layer: layer, isOnScreen: true, isMinimized: false)
    }

    // eligible: レイヤー0以外を除外
    func testEligibleExcludesNonZeroLayer() {
        let ws = [win(1), win(2, layer: 25)]
        XCTAssertEqual(WindowOrdering.eligible(ws).map(\.id), [1])
    }

    // eligible: タイトル空かつ極小（ツールチップ類）を除外
    func testEligibleExcludesTinyUntitled() {
        let ws = [win(1), win(2, "", w: 100, h: 40)]
        XCTAssertEqual(WindowOrdering.eligible(ws).map(\.id), [1])
    }

    // eligible: タイトル空でも大きければ残す（作業中ウィンドウの可能性）
    func testEligibleKeepsLargeUntitled() {
        let ws = [win(1, "", w: 1200, h: 800)]
        XCTAssertEqual(WindowOrdering.eligible(ws).map(\.id), [1])
    }

    // sortedByFrontOrder: 前面順リストにあるものはその順、無いもの（別Space等）は後ろにタイトル順
    func testSortedByFrontOrder() {
        let ws = [win(3, "c"), win(1, "b"), win(2, "a")]
        let sorted = WindowOrdering.sortedByFrontOrder(ws, frontOrder: [1, 3])
        XCTAssertEqual(sorted.map(\.id), [1, 3, 2])
    }

    func testSortedByFrontOrderTitleTiebreak() {
        let ws = [win(5, "zeta"), win(4, "alpha")]
        let sorted = WindowOrdering.sortedByFrontOrder(ws, frontOrder: [])
        XCTAssertEqual(sorted.map(\.id), [4, 5])
    }

    // ordered: frontIDを先頭に移動、他の相対順は維持
    func testOrderedMovesFrontToHead() {
        let ws = [win(1), win(2), win(3)]
        XCTAssertEqual(WindowOrdering.ordered(ws, frontID: 2).map(\.id), [2, 1, 3])
    }

    func testOrderedNilFrontIDKeepsOrder() {
        let ws = [win(1), win(2)]
        XCTAssertEqual(WindowOrdering.ordered(ws, frontID: nil).map(\.id), [1, 2])
    }

    func testOrderedUnknownFrontIDKeepsOrder() {
        let ws = [win(1), win(2)]
        XCTAssertEqual(WindowOrdering.ordered(ws, frontID: 99).map(\.id), [1, 2])
    }
}
