import XCTest
@testable import OptTabCore

final class RunningLegacyAppTests: XCTestCase {
    // 旧メニューバー版が動いていれば、置き場所を問わず検出する。
    // ファイル存在チェックは /Applications と ~/Applications しか見ないので、
    // ユーザーが .app を別の場所へ移していると取りこぼす
    func testDetectsRunningLegacyAppAnywhere() {
        let apps = [
            RunningApp(bundleIdentifier: "dev.konaito.opttab",
                       bundlePath: "/Users/konaito/Desktop/OptTab.app"),
            RunningApp(bundleIdentifier: "com.apple.finder",
                       bundlePath: "/System/Library/CoreServices/Finder.app"),
        ]
        XCTAssertEqual(LegacyInstall.runningLegacyApps(apps),
                       ["/Users/konaito/Desktop/OptTab.app"])
    }

    // 新デーモンは非バンドルなので bundlePath を持たない。混ざってはいけない
    func testIgnoresNonBundledDaemon() {
        let apps = [RunningApp(bundleIdentifier: "dev.konaito.opttab", bundlePath: nil)]
        XCTAssertTrue(LegacyInstall.runningLegacyApps(apps).isEmpty)
    }

    // バンドルIDが同じでも .app でなければ対象外
    func testIgnoresNonAppBundlePath() {
        let apps = [RunningApp(bundleIdentifier: "dev.konaito.opttab",
                               bundlePath: "/opt/homebrew/var/opttab")]
        XCTAssertTrue(LegacyInstall.runningLegacyApps(apps).isEmpty)
    }

    func testIgnoresOtherBundleIdentifiers() {
        let apps = [RunningApp(bundleIdentifier: "com.example.other",
                               bundlePath: "/Applications/Other.app")]
        XCTAssertTrue(LegacyInstall.runningLegacyApps(apps).isEmpty)
    }

    func testEmptyInputYieldsEmpty() {
        XCTAssertTrue(LegacyInstall.runningLegacyApps([]).isEmpty)
    }
}
