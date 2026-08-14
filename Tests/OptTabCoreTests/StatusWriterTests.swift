import XCTest
@testable import OptTabCore

final class StatusWriterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opttab-statuswriter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func sample() -> DaemonStatus {
        DaemonStatus(pid: 99,
                     version: "0.2.0",
                     executablePath: "/opt/homebrew/var/opttab/opttab",
                     accessibility: true,
                     screenRecording: false,
                     updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testWritesReadableFile() throws {
        let path = directory.appendingPathComponent("status.json").path
        try StatusWriter(path: path).write(sample())
        let decoded = try DaemonStatus.decode(
            try Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertEqual(decoded, sample())
    }

    // 5秒ごとに上書きするので、2回目以降も壊れないこと
    func testOverwritesExistingFile() throws {
        let path = directory.appendingPathComponent("status.json").path
        let writer = StatusWriter(path: path)
        try writer.write(sample())
        let updated = DaemonStatus(pid: 99,
                                   version: "0.2.0",
                                   executablePath: "/opt/homebrew/var/opttab/opttab",
                                   accessibility: true,
                                   screenRecording: true,
                                   updatedAt: Date(timeIntervalSince1970: 1_700_000_005))
        try writer.write(updated)
        let decoded = try DaemonStatus.decode(
            try Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertEqual(decoded, updated)
    }

    // 親ディレクトリが無ければ作る（開発環境で var/opttab が無い場合）
    func testCreatesParentDirectory() throws {
        let path = directory.appendingPathComponent("nested/deep/status.json").path
        try StatusWriter(path: path).write(sample())
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    // currentStatus は実行時の権限を読むが、pidとpathは決定的に埋まる
    func testCurrentStatusFillsProcessFacts() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let status = StatusWriter.currentStatus(
            executablePath: "/opt/homebrew/var/opttab/opttab", now: now)
        XCTAssertEqual(status.pid, ProcessInfo.processInfo.processIdentifier)
        XCTAssertEqual(status.executablePath, "/opt/homebrew/var/opttab/opttab")
        XCTAssertEqual(status.updatedAt, now)
    }
}
