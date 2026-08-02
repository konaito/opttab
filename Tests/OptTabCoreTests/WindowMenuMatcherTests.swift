import XCTest
@testable import OptTabCore

final class WindowMenuMatcherTests: XCTestCase {
    // 完全一致
    func testExactMatch() {
        XCTAssertTrue(WindowMenuMatcher.matches(windowTitle: "naito0219@outlook.jp: Ne…",
                                                menuTitle: "naito0219@outlook.jp: Ne…"))
    }

    // メニュー側が「…」で省略されている（メニューの方が短い）
    func testMenuEllipsisPrefixMatch() {
        XCTAssertTrue(WindowMenuMatcher.matches(windowTitle: "naito0219@outlook.jp: 受信トレイ",
                                                menuTitle: "naito0219@outlook.jp: 受信…"))
    }

    // ウィンドウ側が「…」で省略されている
    func testWindowEllipsisPrefixMatch() {
        XCTAssertTrue(WindowMenuMatcher.matches(windowTitle: "Personal: RustDesk for R…",
                                                menuTitle: "Personal: RustDesk for Remote"))
    }

    // 不一致
    func testNoMatch() {
        XCTAssertFalse(WindowMenuMatcher.matches(windowTitle: "Alpha", menuTitle: "Beta"))
    }

    // 空タイトルは常に不一致（誤爆防止）
    func testEmptyTitlesNeverMatch() {
        XCTAssertFalse(WindowMenuMatcher.matches(windowTitle: "", menuTitle: ""))
        XCTAssertFalse(WindowMenuMatcher.matches(windowTitle: "A", menuTitle: ""))
        XCTAssertFalse(WindowMenuMatcher.matches(windowTitle: "", menuTitle: "A"))
    }

    // 「…」だけのタイトルは不一致（dropLastで空になるケース）
    func testEllipsisOnlyNeverMatches() {
        XCTAssertFalse(WindowMenuMatcher.matches(windowTitle: "…", menuTitle: "…"))
    }

    // bestIndex: 末尾側（ウィンドウ一覧項目）を優先して返す
    func testBestIndexPrefersLastMatch() {
        let titles = ["naito0219@outlook.jp: Ne…", "Downloads", "naito0219@outlook.jp: Ne…"]
        XCTAssertEqual(WindowMenuMatcher.bestIndex(windowTitle: "naito0219@outlook.jp: Ne…",
                                                   menuTitles: titles), 2)
    }

    // bestIndex: 一致なしはnil、空ウィンドウタイトルもnil
    func testBestIndexNil() {
        XCTAssertNil(WindowMenuMatcher.bestIndex(windowTitle: "X", menuTitles: ["A", "B"]))
        XCTAssertNil(WindowMenuMatcher.bestIndex(windowTitle: "", menuTitles: ["", "A"]))
    }

    // --- reachableWindows（メニュー項目の消費制） ---

    private func rw(_ id: UInt32, _ title: String) -> WindowInfo {
        WindowInfo(id: id, title: title,
                   frame: CGRect(x: 0, y: 0, width: 1800, height: 1100),
                   layer: 0, isOnScreen: false, isMinimized: false)
    }

    // AXハンドル持ちと同タイトルの裏タブは、メニュー項目が消費済みになり除外される
    func testTabWithSameTitleAsRealWindowExcluded() {
        let windows = [rw(155, "✳ Claude"), rw(5930, "konaito@Mac:/tmp"),
                       rw(4549, "konaito@Mac:/tmp")]  // 4549は裏タブ
        let result = WindowMenuMatcher.reachableWindows(
            windows,
            hasAXHandle: { $0 == 155 || $0 == 5930 },
            menuTitles: ["Merge All Windows", "✳ Claude", "konaito@Mac:/tmp"])
        XCTAssertEqual(result.map(\.id), [155, 5930])
    }

    // 別Spaceの実ウィンドウ（AXなし）は未消費のメニュー項目で通る
    func testOtherSpaceWindowWithMenuItemIncluded() {
        let windows = [rw(1, "Personal"), rw(2, "Outlook")]
        let result = WindowMenuMatcher.reachableWindows(
            windows,
            hasAXHandle: { $0 == 1 },
            menuTitles: ["Personal", "Outlook"])
        XCTAssertEqual(result.map(\.id), [1, 2])
    }

    // メニュー項目が無ければAXなしウィンドウは全部除外
    func testNoMenuItemsExcludesAXless() {
        let windows = [rw(1, "A"), rw(2, "B")]
        let result = WindowMenuMatcher.reachableWindows(
            windows, hasAXHandle: { $0 == 1 }, menuTitles: [])
        XCTAssertEqual(result.map(\.id), [1])
    }

    // 同タイトルのAXなしウィンドウ2枚に対して未消費項目が1つ → 1枚だけ通る
    func testOneMenuItemAdmitsOnlyOneAXlessWindow() {
        let windows = [rw(1, "same"), rw(2, "same")]
        let result = WindowMenuMatcher.reachableWindows(
            windows, hasAXHandle: { _ in false }, menuTitles: ["same"])
        XCTAssertEqual(result.map(\.id), [1])
    }
}
