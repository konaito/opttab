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
}
