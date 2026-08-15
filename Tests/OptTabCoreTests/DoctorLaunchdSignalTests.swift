import XCTest
@testable import OptTabCore

/// 状態ファイル以外の2つのシグナル（launchd のジョブ状態、動作中の旧 .app）が
/// レポートに反映されることを見る。
final class DoctorLaunchdSignalTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func status() -> DaemonStatus {
        DaemonStatus(pid: 1234,
                     version: "0.2.0",
                     executablePath: "/opt/homebrew/var/opttab/opttab",
                     accessibility: true,
                     screenRecording: true,
                     updatedAt: now)
    }

    private func job(_ state: LaunchdJob.State,
                     _ lastExit: LaunchdJob.LastExit = .neverExited,
                     runs: Int? = 1,
                     label: String = "homebrew.mxcl.opttab") -> LaunchdJob {
        LaunchdJob(label: label, state: state, lastExit: lastExit, runs: runs)
    }

    private func report(_ jobs: [LaunchdJob] = [],
                        runningLegacyApps: [String] = []) -> DoctorReport {
        DoctorReport.build(status: status(), now: now, pidAlive: true,
                           legacyExisting: [],
                           launchdJobs: jobs,
                           runningLegacyApps: runningLegacyApps)
    }

    // --- 今まさに壊れている: クラッシュループ ---

    // これが本命。keep_alive のクラッシュループは再起動のたびに新しい pid で
    // 新鮮な status.json を書くので、状態ファイルだけ見ると常に健全に見える
    func testCrashLoopIsReportedEvenWhenHeartbeatLooksHealthy() {
        let r = report([job(.spawnScheduled, .code(7))])
        XCTAssertTrue(r.warnings.contains { $0.contains("crash-looping") })
        XCTAssertTrue(r.unhealthy)
        XCTAssertEqual(r.exitCode, 1)
    }

    // 原因を追える場所を示すこと
    func testCrashLoopPointsAtTheLog() {
        XCTAssertTrue(report([job(.spawnScheduled, .code(7))])
            .warnings.contains { $0.contains("opttab.log") })
    }

    // --- 過去に落ちて復帰済み: 警告はするが失敗にはしない ---

    // 一度落ちて自力復帰したサービスを永久に赤くし続けると、
    // 健全な「今」を偽ることになる
    func testPastRestartWarnsButDoesNotFail() {
        let r = report([job(.running(pid: 1234), .code(1), runs: 3)])
        XCTAssertTrue(r.warnings.contains { $0.contains("restarted 2 times") })
        XCTAssertFalse(r.unhealthy)
        XCTAssertEqual(r.exitCode, 0)
    }

    // 解消手順を必ず添える
    func testPastRestartShowsHowToClearIt() {
        XCTAssertTrue(report([job(.running(pid: 1234), .code(1), runs: 2)])
            .warnings.contains { $0.contains("brew services restart opttab") })
    }

    // SIGKILL では last exit code が出ない。runs だけが死を記録している
    func testSignalKillIsCaughtByRunsAlone() {
        let r = report([job(.running(pid: 1234), .unknown, runs: 2)])
        XCTAssertTrue(r.warnings.contains { $0.contains("restarted 1 time") })
    }

    func testHealthyJobAddsNoWarning() {
        let r = report([job(.running(pid: 1234), .neverExited, runs: 1)])
        XCTAssertTrue(r.warnings.isEmpty)
        XCTAssertEqual(r.exitCode, 0)
    }

    // 問い合わせられなかった場合は黙る。憶測で警告しない
    func testNoJobsAddsNoWarning() {
        let r = report([])
        XCTAssertTrue(r.warnings.isEmpty)
        XCTAssertEqual(r.exitCode, 0)
    }

    // --- 2つのシグナルの食い違い ---

    func testDisagreementIsReportedWhenLaunchdSaysNotRunning() {
        XCTAssertTrue(report([job(.notRunning)])
            .warnings.contains { $0.contains("does not report a running job") })
    }

    // 止まっているジョブに「死んで復帰した」とは言えない。
    // 過去の再起動記録があっても、今の事実（走っていない）を優先して報告する
    func testStoppedJobWithPastExitDoesNotClaimRecovery() {
        let r = report([job(.notRunning, .code(0), runs: 2)])
        XCTAssertFalse(r.warnings.contains { $0.contains("recovered") })
        XCTAssertFalse(r.warnings.contains { $0.contains("restarted") })
        XCTAssertTrue(r.warnings.contains { $0.contains("does not report a running job") })
    }

    // pid が読めなかっただけの running からは再起動の警告を落とさない
    func testUnparsedRunningStateKeepsRestartSignal() {
        XCTAssertTrue(report([job(.other("running"), .unknown, runs: 2)])
            .warnings.contains { $0.contains("restarted 1 time") })
    }

    // --- 助言はラベルに合わせる ---

    // brew が管理していないジョブに brew のコマンドを出さない
    func testNonBrewJobGetsLaunchctlAdvice() {
        let warnings = report([job(.running(pid: 1), .unknown, runs: 2,
                                   label: "dev.konaito.opttab")]).warnings
        XCTAssertTrue(warnings.contains { $0.contains("launchctl bootout") })
        XCTAssertFalse(warnings.contains { $0.contains("brew services restart") })
    }

    func testBrewJobGetsBrewAdvice() {
        let warnings = report([job(.running(pid: 1), .unknown, runs: 2,
                                   label: "homebrew.mxcl.opttab")]).warnings
        XCTAssertTrue(warnings.contains { $0.contains("brew services restart opttab") })
        XCTAssertTrue(warnings.contains { $0.contains("opttab.log") })
    }

    // state は読めたが pid が取れなかっただけのときに
    // 「launchd はジョブが走っていないと言っている」と報告してはいけない。
    // 直前の行では running と表示しているので矛盾する
    func testUnparsedRunningStateDoesNotClaimDisagreement() {
        XCTAssertFalse(report([job(.other("running"))])
            .warnings.contains { $0.contains("does not report a running job") })
    }

    // --- 二重常駐 ---

    // brew services と install-local.sh が同時に走ると2つのイベントタップが
    // ⌥⇥ を奪い合う。状態ファイルは片方しか映さないのでここでしか見えない
    func testTwoRunningJobsIsReportedAndFails() {
        let r = report([job(.running(pid: 1), label: "homebrew.mxcl.opttab"),
                        job(.running(pid: 2), label: "dev.konaito.opttab")])
        XCTAssertTrue(r.warnings.contains { $0.contains("two launchd jobs") })
        XCTAssertTrue(r.unhealthy)
        XCTAssertEqual(r.exitCode, 1)
    }

    // 片方しか走っていなければ問題ない
    func testOneRunningAndOneStoppedIsFine() {
        let r = report([job(.running(pid: 1), label: "homebrew.mxcl.opttab"),
                        job(.notRunning, label: "dev.konaito.opttab")])
        XCTAssertFalse(r.warnings.contains { $0.contains("two launchd jobs") })
    }

    // --- 動作中の旧 .app ---

    // ファイル存在チェックの届かない場所にある .app でも、動いていれば検出する
    func testRunningLegacyAppIsReportedAndFails() {
        let r = report([job(.running(pid: 1234))],
                       runningLegacyApps: ["/Users/konaito/Desktop/OptTab.app"])
        XCTAssertTrue(r.warnings.contains {
            $0.contains("/Users/konaito/Desktop/OptTab.app")
        })
        XCTAssertEqual(r.exitCode, 1)
    }

    // 移動された .app には cask のコマンドが効かない。その旨を添える
    func testMovedAppAdviceIsNotCaskOnly() {
        XCTAssertTrue(report([], runningLegacyApps: ["/tmp/OptTab.app"])
            .warnings.contains { $0.contains("delete the bundle") })
    }

    // --- 出力 ---

    func testRenderShowsEachLaunchdJob() {
        let text = report([job(.running(pid: 1), label: "homebrew.mxcl.opttab"),
                           job(.notRunning, label: "dev.konaito.opttab")]).render()
        XCTAssertTrue(text.contains("homebrew.mxcl.opttab"))
        XCTAssertTrue(text.contains("dev.konaito.opttab"))
    }

    func testRenderShowsUnknownLaunchdWhenAbsent() {
        let text = report([]).render()
        XCTAssertTrue(text.contains("launchd:"))
        XCTAssertTrue(text.contains("unknown"))
    }
}

/// Doctor 側の薄い層。ラベルを順に引いて、読めたものだけ集める。
final class DoctorLaunchdJobsTests: XCTestCase {
    private let healthy = "\tstate = running\n\tpid = 7\n\truns = 1"

    func testCollectsEveryLabelThatParses() {
        let jobs = Doctor.launchdJobs(labels: ["a", "b"]) { _ in self.healthy }
        XCTAssertEqual(jobs.map(\.label), ["a", "b"])
    }

    // 片方しか読めなくても、もう片方は落とさない
    func testSkipsLabelsWithNoOutput() {
        let jobs = Doctor.launchdJobs(labels: ["a", "b"]) {
            $0 == "b" ? self.healthy : nil
        }
        XCTAssertEqual(jobs.map(\.label), ["b"])
    }

    // 解釈できない出力はエラーではなく無視
    func testSkipsUnparseableOutput() {
        let jobs = Doctor.launchdJobs(labels: ["a"]) { _ in "Could not find service" }
        XCTAssertTrue(jobs.isEmpty)
    }

    func testNoLabelsYieldsEmpty() {
        XCTAssertTrue(Doctor.launchdJobs(labels: []) { _ in self.healthy }.isEmpty)
    }

    // 実際に問い合わせるのは brew services 経由と開発用の両方
    func testServiceLabelsCoverBothInstallPaths() {
        XCTAssertEqual(Doctor.serviceLabels,
                       ["homebrew.mxcl.opttab", "dev.konaito.opttab"])
    }
}
