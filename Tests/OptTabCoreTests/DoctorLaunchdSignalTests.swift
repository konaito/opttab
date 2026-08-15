import XCTest
@testable import OptTabCore

/// 状態ファイル以外の2つのシグナル（launchd のジョブ状態、動作中の旧 .app）が
/// レポートに反映されることを見る。
final class DoctorLaunchdSignalTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func status(offset: TimeInterval = 0) -> DaemonStatus {
        DaemonStatus(pid: 1234,
                     version: "0.2.0",
                     executablePath: "/opt/homebrew/var/opttab/opttab",
                     accessibility: true,
                     screenRecording: true,
                     updatedAt: now.addingTimeInterval(offset))
    }

    private func job(_ state: LaunchdJob.State,
                     _ lastExit: LaunchdJob.LastExit) -> LaunchdJob {
        LaunchdJob(label: "homebrew.mxcl.opttab", state: state, lastExit: lastExit)
    }

    // --- クラッシュループ ---

    // これが本命。keep_alive のクラッシュループは再起動のたびに新しい pid で
    // 新鮮な status.json を書くので、状態ファイルだけ見ると常に健全に見える。
    // launchd 側の記録があって初めて嘘が破れる
    func testCrashLoopIsReportedEvenWhenHeartbeatLooksHealthy() {
        let report = DoctorReport.build(
            status: status(), now: now, pidAlive: true, legacyExisting: [],
            launchd: job(.spawnScheduled, .code(7)))
        XCTAssertTrue(report.warnings.contains { $0.contains("crash-looping") })
    }

    // クラッシュループは異常なので終了コードも失敗にする
    func testCrashLoopFailsExitCode() {
        let report = DoctorReport.build(
            status: status(), now: now, pidAlive: true, legacyExisting: [],
            launchd: job(.spawnScheduled, .code(7)))
        XCTAssertEqual(report.exitCode, 1)
    }

    // 今は動いていても、過去に終了していれば警告する
    func testPastExitIsReported() {
        let report = DoctorReport.build(
            status: status(), now: now, pidAlive: true, legacyExisting: [],
            launchd: job(.running(pid: 1234), .code(1)))
        XCTAssertTrue(report.warnings.contains { $0.contains("exited at least once") })
    }

    func testHealthyJobAddsNoWarning() {
        let report = DoctorReport.build(
            status: status(), now: now, pidAlive: true, legacyExisting: [],
            launchd: job(.running(pid: 1234), .neverExited))
        XCTAssertTrue(report.warnings.isEmpty)
        XCTAssertEqual(report.exitCode, 0)
    }

    // launchd を問い合わせられなかった場合は黙る。憶測で警告しない
    func testAbsentLaunchdJobAddsNoWarning() {
        let report = DoctorReport.build(
            status: status(), now: now, pidAlive: true, legacyExisting: [],
            launchd: nil)
        XCTAssertTrue(report.warnings.isEmpty)
        XCTAssertEqual(report.exitCode, 0)
    }

    // --- 2つのシグナルの食い違い ---

    // 状態ファイルは「動いている」と言うのに launchd はジョブを知らない。
    // install-local.sh で直接起動した等でありうるが、利用者には伝える価値がある
    func testDisagreementIsReportedWhenLaunchdSaysNotRunning() {
        let report = DoctorReport.build(
            status: status(), now: now, pidAlive: true, legacyExisting: [],
            launchd: job(.notRunning, .neverExited))
        XCTAssertTrue(report.warnings.contains { $0.contains("launchd") })
    }

    // --- 動作中の旧 .app ---

    // ファイル存在チェックの届かない場所にある .app でも、動いていれば検出する
    func testRunningLegacyAppIsReported() {
        let report = DoctorReport.build(
            status: status(), now: now, pidAlive: true, legacyExisting: [],
            launchd: job(.running(pid: 1234), .neverExited),
            runningLegacyApps: ["/Users/konaito/Desktop/OptTab.app"])
        XCTAssertTrue(report.warnings.contains {
            $0.contains("/Users/konaito/Desktop/OptTab.app")
        })
    }

    // 動いている旧版は ⌥⇥ を実際に奪い合う。単なる残骸ファイルと違って失敗扱い
    func testRunningLegacyAppFailsExitCode() {
        let report = DoctorReport.build(
            status: status(), now: now, pidAlive: true, legacyExisting: [],
            launchd: job(.running(pid: 1234), .neverExited),
            runningLegacyApps: ["/Applications/OptTab.app"])
        XCTAssertEqual(report.exitCode, 1)
    }

    // --- 出力 ---

    func testRenderShowsLaunchdLine() {
        let text = DoctorReport.build(
            status: status(), now: now, pidAlive: true, legacyExisting: [],
            launchd: job(.running(pid: 1234), .neverExited)).render()
        XCTAssertTrue(text.contains("launchd:"))
        XCTAssertTrue(text.contains("homebrew.mxcl.opttab"))
    }

    // 問い合わせできなかったときも行は出すが、状態は unknown と言う
    func testRenderShowsUnknownLaunchdWhenAbsent() {
        let text = DoctorReport.build(
            status: status(), now: now, pidAlive: true, legacyExisting: [],
            launchd: nil).render()
        XCTAssertTrue(text.contains("launchd:"))
        XCTAssertTrue(text.contains("unknown"))
    }
}
