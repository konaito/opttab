import XCTest
@testable import OptTabCore

final class DoctorReportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func status(offset: TimeInterval = 0,
                        accessibility: Bool = true,
                        screenRecording: Bool = true) -> DaemonStatus {
        DaemonStatus(pid: 1234,
                     version: "0.2.0",
                     executablePath: "/opt/homebrew/var/opttab/opttab",
                     accessibility: accessibility,
                     screenRecording: screenRecording,
                     updatedAt: now.addingTimeInterval(offset))
    }

    // 状態ファイルが無い = サービスが一度も起動していない
    func testNoStatusFileMeansUnavailable() {
        let report = DoctorReport.build(status: nil, now: now, legacyExisting: [])
        XCTAssertEqual(report.service, .statusUnavailable)
        XCTAssertEqual(report.exitCode, 1)
    }

    // ハートビートが新しい = 動いている
    func testFreshStatusMeansRunning() {
        let report = DoctorReport.build(status: status(offset: -3),
                                        now: now, legacyExisting: [])
        XCTAssertEqual(report.service, .running(pid: 1234, version: "0.2.0"))
        XCTAssertEqual(report.exitCode, 0)
    }

    // ハートビートが途絶えた = 落ちている
    func testStaleStatusMeansNotRunning() {
        let report = DoctorReport.build(status: status(offset: -120),
                                        now: now, legacyExisting: [])
        XCTAssertEqual(report.service, .notRunning)
        XCTAssertEqual(report.exitCode, 1)
    }

    // アクセシビリティが無ければ異常終了（必須権限のため）
    func testMissingAccessibilityIsFailure() {
        let report = DoctorReport.build(status: status(accessibility: false),
                                        now: now, legacyExisting: [])
        XCTAssertFalse(report.accessibility)
        XCTAssertEqual(report.exitCode, 1)
    }

    // 画面収録は任意。無くても正常終了する（サムネイル無しで動く）
    func testMissingScreenRecordingIsNotFailure() {
        let report = DoctorReport.build(status: status(screenRecording: false),
                                        now: now, legacyExisting: [])
        XCTAssertFalse(report.screenRecording)
        XCTAssertEqual(report.exitCode, 0)
    }

    // 旧 .app が残っていたら警告する（イベントタップの奪い合いになる）
    func testLegacyAppProducesWarning() {
        let report = DoctorReport.build(
            status: status(), now: now,
            legacyExisting: ["/Applications/OptTab.app"])
        XCTAssertEqual(report.warnings.count, 1)
        XCTAssertTrue(report.warnings[0].contains("/Applications/OptTab.app"))
        XCTAssertTrue(report.warnings[0].contains("brew uninstall --cask opttab"))
    }

    // 手作りLaunchAgentが残っていたら警告する（brew servicesと二重起動になる）
    func testLegacyLaunchAgentProducesWarning() {
        let path = NSString(string: "~/Library/LaunchAgents/dev.konaito.opttab.plist")
            .expandingTildeInPath
        let report = DoctorReport.build(status: status(), now: now,
                                        legacyExisting: [path])
        XCTAssertEqual(report.warnings.count, 1)
        XCTAssertTrue(report.warnings[0].contains("launchctl bootout"))
    }

    // 警告があっても、サービス自体が健全なら終了コードは0のまま
    func testWarningsDoNotChangeExitCode() {
        let report = DoctorReport.build(
            status: status(), now: now,
            legacyExisting: ["/Applications/OptTab.app"])
        XCTAssertEqual(report.exitCode, 0)
    }

    func testLegacyCandidatesCoverKnownLeftovers() {
        let paths = LegacyInstall.candidates.map(\.path)
        XCTAssertTrue(paths.contains("/Applications/OptTab.app"))
        XCTAssertTrue(paths.contains(
            NSString(string: "~/Applications/OptTab.app").expandingTildeInPath))
        XCTAssertTrue(paths.contains(
            NSString(string: "~/Library/LaunchAgents/dev.konaito.opttab.plist")
                .expandingTildeInPath))
    }

    // 出力に権限とサービス状態が両方現れる
    func testRenderMentionsServiceAndPermissions() {
        let text = DoctorReport.build(status: status(), now: now,
                                      legacyExisting: []).render()
        XCTAssertTrue(text.contains("1234"))
        XCTAssertTrue(text.contains("Accessibility"))
        XCTAssertTrue(text.contains("Screen Recording"))
    }

    // 権限が欠けていたら設定パネルのURLを案内する（自動で開かない）
    func testRenderShowsSettingsURLWhenAccessibilityMissing() {
        let text = DoctorReport.build(status: status(accessibility: false),
                                      now: now, legacyExisting: []).render()
        XCTAssertTrue(text.contains("Privacy_Accessibility"))
    }

    // サービス未起動なら起動方法を案内する
    func testRenderShowsStartCommandWhenNotRunning() {
        let text = DoctorReport.build(status: nil, now: now,
                                      legacyExisting: []).render()
        XCTAssertTrue(text.contains("brew services start opttab"))
    }
}
