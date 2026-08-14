import XCTest
@testable import OptTabCore

final class DaemonLaunchCheckTests: XCTestCase {
    // Apple Silicon の標準prefix
    func testAcceptsHomebrewPrefix() {
        XCTAssertTrue(DaemonLaunchCheck.isSupportedDaemonPath(
            "/opt/homebrew/var/opttab/opttab"))
    }

    // Intel の標準prefix
    func testAcceptsIntelPrefix() {
        XCTAssertTrue(DaemonLaunchCheck.isSupportedDaemonPath(
            "/usr/local/var/opttab/opttab"))
    }

    // 任意のprefixでも var/opttab/opttab なら通す（テスト用の一時ディレクトリなど）
    func testAcceptsArbitraryPrefix() {
        XCTAssertTrue(DaemonLaunchCheck.isSupportedDaemonPath(
            "/tmp/fixture-prefix/var/opttab/opttab"))
    }

    // brew の bin シンボリンクを辿った実体（Cellar）は許可の無いパス
    func testRejectsCellarPath() {
        XCTAssertFalse(DaemonLaunchCheck.isSupportedDaemonPath(
            "/opt/homebrew/Cellar/opttab/0.2.0/bin/opttab"))
    }

    // PATH 上の bin から直接叩かれた場合
    func testRejectsBinPath() {
        XCTAssertFalse(DaemonLaunchCheck.isSupportedDaemonPath(
            "/opt/homebrew/bin/opttab"))
    }

    // ファイル名は合っていても親が var/opttab でなければ拒否する
    func testRejectsRightBasenameWrongParent() {
        XCTAssertFalse(DaemonLaunchCheck.isSupportedDaemonPath(
            "/Users/someone/opttab/opttab"))
        XCTAssertFalse(DaemonLaunchCheck.isSupportedDaemonPath(
            "/opt/homebrew/var/opttab-dev/opttab"))
    }

    // 短すぎるパスで落ちない
    func testRejectsShortPath() {
        XCTAssertFalse(DaemonLaunchCheck.isSupportedDaemonPath("/opttab"))
        XCTAssertFalse(DaemonLaunchCheck.isSupportedDaemonPath("opttab"))
    }
}
