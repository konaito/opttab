import XCTest
@testable import OptTabCore

final class SwitcherStateTests: XCTestCase {
    private func wins(_ n: Int) -> [WindowInfo] {
        (1...n).map { WindowInfo(id: UInt32($0), title: "w\($0)",
                                 frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                                 layer: 0, isOnScreen: true, isMinimized: false) }
    }

    // 2枚未満では発動しない
    func testInitFailsWithFewerThanTwoWindows() {
        XCTAssertNil(SwitcherState(windows: wins(1)))
        XCTAssertNil(SwitcherState(windows: []))
    }

    // 初期選択は2番目（=直前のウィンドウ）→即離しでトグルになる
    func testInitialSelectionIsSecond() {
        XCTAssertEqual(SwitcherState(windows: wins(3))?.selectedIndex, 1)
    }

    // 逆方向発動（Option+Shift+Tab）は末尾から
    func testReverseInitialSelectionIsLast() {
        XCTAssertEqual(SwitcherState(windows: wins(3), reverse: true)?.selectedIndex, 2)
    }

    func testSelectNextWrapsAround() {
        var s = SwitcherState(windows: wins(3))!
        s.selectNext()   // 1 -> 2
        s.selectNext()   // 2 -> 0 (wrap)
        XCTAssertEqual(s.selectedIndex, 0)
    }

    func testSelectPreviousWrapsAround() {
        var s = SwitcherState(windows: wins(3))!
        s.selectPrevious()  // 1 -> 0
        s.selectPrevious()  // 0 -> 2 (wrap)
        XCTAssertEqual(s.selectedIndex, 2)
    }

    func testSelectedReturnsWindow() {
        let s = SwitcherState(windows: wins(2))!
        XCTAssertEqual(s.selected.id, 2)
    }

    // 範囲外indexは無視（クリック選択の防御）
    func testSelectIgnoresOutOfRange() {
        var s = SwitcherState(windows: wins(2))!
        s.select(99)
        XCTAssertEqual(s.selectedIndex, 1)
        s.select(0)
        XCTAssertEqual(s.selectedIndex, 0)
    }
}
