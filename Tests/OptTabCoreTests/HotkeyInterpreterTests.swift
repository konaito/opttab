import XCTest
@testable import OptTabCore

final class HotkeyInterpreterTests: XCTestCase {
    private func keyDown(_ keyCode: Int64, option: Bool = false, shift: Bool = false,
                         command: Bool = false, control: Bool = false,
                         active: Bool = false) -> HotkeyAction {
        HotkeyInterpreter.actionForKeyDown(
            keyCode: keyCode, optionDown: option, shiftDown: shift,
            commandDown: command, controlDown: control, sessionActive: active)
    }

    // 非アクティブ時: Option+Tab → 発動
    func testOptionTabActivates() {
        XCTAssertEqual(keyDown(48, option: true), .activate(reverse: false))
    }

    // 非アクティブ時: Option+Shift+Tab → 逆方向発動
    func testOptionShiftTabActivatesReverse() {
        XCTAssertEqual(keyDown(48, option: true, shift: true), .activate(reverse: true))
    }

    // Cmd/Ctrlが混ざってたら発動しない（Cmd+Option+Tab等は他機能）
    func testOtherModifiersPassthrough() {
        XCTAssertEqual(keyDown(48, option: true, command: true), .passthrough)
        XCTAssertEqual(keyDown(48, option: true, control: true), .passthrough)
    }

    // Optionなしはpassthrough
    func testPlainTabPassthrough() {
        XCTAssertEqual(keyDown(48), .passthrough)
    }

    // アクティブ中: Tab → 順送り / Shift+Tab → 逆送り
    func testCycleWhileActive() {
        XCTAssertEqual(keyDown(48, option: true, active: true), .cycle(reverse: false))
        XCTAssertEqual(keyDown(48, option: true, shift: true, active: true),
                       .cycle(reverse: true))
    }

    // アクティブ中: Esc → キャンセル
    func testEscCancelsWhileActive() {
        XCTAssertEqual(keyDown(53, option: true, active: true), .cancel)
    }

    // アクティブ中の他キーはpassthrough（誤爆防止）
    func testOtherKeysPassthroughWhileActive() {
        XCTAssertEqual(keyDown(36, option: true, active: true), .passthrough)
    }

    // アクティブ中にOptionが離れたら確定
    func testOptionReleaseCommits() {
        XCTAssertEqual(HotkeyInterpreter.actionForFlagsChanged(
            optionDown: false, sessionActive: true), .commit)
    }

    // 非アクティブ時のflags変化は無視
    func testFlagsChangeInactivePassthrough() {
        XCTAssertEqual(HotkeyInterpreter.actionForFlagsChanged(
            optionDown: false, sessionActive: false), .passthrough)
    }

    // アクティブ中でOptionまだ押されてるなら何もしない
    func testFlagsChangeOptionStillDownPassthrough() {
        XCTAssertEqual(HotkeyInterpreter.actionForFlagsChanged(
            optionDown: true, sessionActive: true), .passthrough)
    }
}
