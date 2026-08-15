import XCTest
@testable import OptTabCore

final class LaunchdJobTests: XCTestCase {
    /// 実機の `launchctl print gui/<uid>/homebrew.mxcl.opttab` から採った健全時の出力。
    /// ネストした `state = active` 行が後ろに続くのが要点で、
    /// トップレベルの state を拾えているかがここで効く。
    private let healthy = """
        \tactive count = 4
        \tstate = running
        \truns = 1
        \tpid = 23363
        \tlast exit code = (never exited)
        \t\tstate = active
        \t\tactive count = 1
        """

    /// 実機でクラッシュループを再現したときの出力。
    private let crashing = """
        \tstate = spawn scheduled
        \truns = 1
        \tlast exit code = 7
        \t\tstate = active
        """

    func testParsesHealthyJob() {
        let job = LaunchctlPrintParser.parse(healthy, label: "homebrew.mxcl.opttab")
        XCTAssertEqual(job?.label, "homebrew.mxcl.opttab")
        XCTAssertEqual(job?.state, .running(pid: 23363))
        XCTAssertEqual(job?.lastExit, .neverExited)
    }

    // ネストした `state = active` ではなくトップレベルの state を採ること
    func testIgnoresNestedStateLines() {
        XCTAssertEqual(
            LaunchctlPrintParser.parse(healthy, label: "x")?.state,
            .running(pid: 23363))
    }

    func testParsesCrashingJob() {
        let job = LaunchctlPrintParser.parse(crashing, label: "x")
        XCTAssertEqual(job?.state, .spawnScheduled)
        XCTAssertEqual(job?.lastExit, .code(7))
    }

    // ジョブが見つからない出力は nil。エラーにしない
    func testUnparseableOutputIsNil() {
        XCTAssertNil(LaunchctlPrintParser.parse(
            "Could not find service \"opttab\" in domain for gui", label: "x"))
        XCTAssertNil(LaunchctlPrintParser.parse("", label: "x"))
    }

    // last exit code の行が無い macOS でも state だけで成立させる（縮退）
    func testMissingLastExitDegradesToUnknown() {
        let job = LaunchctlPrintParser.parse("\tstate = running\n\tpid = 5", label: "x")
        XCTAssertEqual(job?.state, .running(pid: 5))
        XCTAssertEqual(job?.lastExit, .unknown)
    }

    // state は読めたが pid が無い場合、running とは言い切らない
    func testRunningWithoutPidIsOther() {
        XCTAssertEqual(LaunchctlPrintParser.parse("\tstate = running", label: "x")?.state,
                       .other("running"))
    }

    func testParsesNotRunning() {
        XCTAssertEqual(
            LaunchctlPrintParser.parse("\tstate = not running", label: "x")?.state,
            .notRunning)
    }

    // --- クラッシュ判定 ---

    // 健全: 一度も終了していない常駐は何も言わない
    func testHealthyJobHasNoCrashSignal() {
        XCTAssertNil(LaunchctlPrintParser.parse(healthy, label: "x")?.crashSignal)
    }

    // 今まさに落ち続けている
    func testSpawnScheduledIsCrashLooping() {
        let signal = LaunchctlPrintParser.parse(crashing, label: "x")?.crashSignal
        XCTAssertNotNil(signal)
        XCTAssertTrue(signal!.contains("crash-looping"))
        XCTAssertTrue(signal!.contains("7"))
    }

    // 今は動いている以上 crashSignal ではない。復帰済みとして restartSignal に出す
    func testRunningAfterAnExitIsARestartNotACrash() {
        let job = LaunchctlPrintParser.parse(
            "\tstate = running\n\tpid = 42\n\tlast exit code = 1", label: "x")
        XCTAssertNil(job?.crashSignal)
        XCTAssertTrue(job!.restartSignal!.contains("exited at least once"))
    }

    // 終了コード0でも、決して終了しないはずの常駐が終了していれば記録する
    func testCleanExitIsStillReported() {
        let job = LaunchctlPrintParser.parse(
            "\tstate = running\n\tpid = 42\n\tlast exit code = 0", label: "x")
        XCTAssertNotNil(job?.restartSignal)
    }

    // --- runs ---

    // 実測: launchd が再起動するたびに増え、brew services restart で1に戻る
    func testParsesRuns() {
        XCTAssertEqual(LaunchctlPrintParser.parse(healthy, label: "x")?.runs, 1)
    }

    func testRunsIsNilWhenAbsent() {
        XCTAssertNil(LaunchctlPrintParser.parse("\tstate = running\n\tpid = 5",
                                                label: "x")?.runs)
    }

    // SIGKILL で殺されると last exit code の行が出ない。
    // 実測で確認した死に方で、runs だけが記録を持つ
    func testRunsCatchesSignalKillWithoutExitCode() {
        let job = LaunchctlPrintParser.parse(
            "\tstate = running\n\truns = 2\n\tpid = 9", label: "x")
        XCTAssertEqual(job?.lastExit, .unknown)
        XCTAssertNotNil(job?.restartSignal)
        XCTAssertTrue(job!.restartSignal!.contains("restarted 1 time"))
    }

    func testRunsOneMeansNoRestart() {
        XCTAssertNil(LaunchctlPrintParser.parse(healthy, label: "x")?.restartSignal)
    }

    // クラッシュループ中は crashSignal だけを出す。二重に言わない
    func testCrashLoopSuppressesRestartSignal() {
        let job = LaunchctlPrintParser.parse(crashing, label: "x")
        XCTAssertNotNil(job?.crashSignal)
        XCTAssertNil(job?.restartSignal)
    }
}
