import XCTest
@testable import OptTabCore

final class DaemonStatusTests: XCTestCase {
    private func status(updatedAt: Date = Date(timeIntervalSince1970: 1_000_000),
                        accessibility: Bool = true,
                        screenRecording: Bool = true) -> DaemonStatus {
        DaemonStatus(pid: 4242,
                     version: "0.2.0",
                     executablePath: "/opt/homebrew/var/opttab/opttab",
                     accessibility: accessibility,
                     screenRecording: screenRecording,
                     updatedAt: updatedAt)
    }

    // JSONを往復しても内容が変わらない
    func testRoundTrip() throws {
        let original = status()
        let decoded = try DaemonStatus.decode(try DaemonStatus.encode(original))
        XCTAssertEqual(decoded, original)
    }

    // doctorが人の目で読めるよう、キーがそのままJSONに出ていること
    func testEncodedJSONContainsKeys() throws {
        let json = String(decoding: try DaemonStatus.encode(status()), as: UTF8.self)
        XCTAssertTrue(json.contains("\"accessibility\""))
        XCTAssertTrue(json.contains("\"screenRecording\""))
        XCTAssertTrue(json.contains("\"executablePath\""))
    }

    // 壊れたJSONはthrowする（doctorが「サービス停止中」と扱えるように）
    func testDecodeGarbageThrows() {
        XCTAssertThrowsError(try DaemonStatus.decode(Data("not json".utf8)))
    }

    // 5秒ハートビートに対し許容30秒。範囲内なら生きている
    func testFreshWithinTolerance() {
        let now = Date(timeIntervalSince1970: 1_000_020)
        XCTAssertTrue(DaemonStatus.isFresh(status(), now: now, tolerance: 30))
    }

    func testStaleBeyondTolerance() {
        let now = Date(timeIntervalSince1970: 1_000_031)
        XCTAssertFalse(DaemonStatus.isFresh(status(), now: now, tolerance: 30))
    }

    // 時計が巻き戻ってもstale扱いにしない（未来の更新時刻を許容する）
    func testFutureTimestampIsFresh() {
        let now = Date(timeIntervalSince1970: 999_990)
        XCTAssertTrue(DaemonStatus.isFresh(status(), now: now, tolerance: 30))
    }

    // 状態ファイルは実行ファイルと同じディレクトリに置く。
    // launchdが起動するのは <prefix>/var/opttab/opttab なので隣に status.json ができる
    func testStatusFilePathIsSiblingOfExecutable() {
        XCTAssertEqual(
            StatusFile.path(forExecutable: "/opt/homebrew/var/opttab/opttab"),
            "/opt/homebrew/var/opttab/status.json")
    }

    func testStatusFilePathHandlesUsrLocal() {
        XCTAssertEqual(
            StatusFile.path(forExecutable: "/usr/local/var/opttab/opttab"),
            "/usr/local/var/opttab/status.json")
    }

    // doctorはCellar経由で実行されるため自分の位置からvarを導けない。
    // 既知のprefix候補を順に見る
    func testCandidatePaths() {
        XCTAssertEqual(
            StatusFile.candidatePaths(prefixes: ["/opt/homebrew", "/usr/local"]),
            ["/opt/homebrew/var/opttab/status.json",
             "/usr/local/var/opttab/status.json"])
    }

    func testDefaultPrefixesCoverBothArchitectures() {
        XCTAssertTrue(StatusFile.defaultPrefixes.contains("/opt/homebrew"))
        XCTAssertTrue(StatusFile.defaultPrefixes.contains("/usr/local"))
    }
}
