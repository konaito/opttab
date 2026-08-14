import XCTest
@testable import OptTabCore

final class DoctorTests: XCTestCase {
    private let sample = DaemonStatus(
        pid: 7,
        version: "0.2.0",
        executablePath: "/opt/homebrew/var/opttab/opttab",
        accessibility: true,
        screenRecording: true,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

    // 最初に見つかった候補パスを採用する
    func testLoadsFromFirstExistingCandidate() throws {
        let data = try DaemonStatus.encode(sample)
        let loaded = Doctor.loadStatus(
            candidatePaths: ["/opt/homebrew/var/opttab/status.json",
                             "/usr/local/var/opttab/status.json"],
            read: { $0 == "/opt/homebrew/var/opttab/status.json" ? data : nil })
        XCTAssertEqual(loaded, sample)
    }

    // 前段が無ければ次の候補へ進む（Intel Macのprefix）
    func testFallsBackToSecondCandidate() throws {
        let data = try DaemonStatus.encode(sample)
        let loaded = Doctor.loadStatus(
            candidatePaths: ["/opt/homebrew/var/opttab/status.json",
                             "/usr/local/var/opttab/status.json"],
            read: { $0 == "/usr/local/var/opttab/status.json" ? data : nil })
        XCTAssertEqual(loaded, sample)
    }

    func testReturnsNilWhenNoCandidateExists() {
        XCTAssertNil(Doctor.loadStatus(
            candidatePaths: ["/opt/homebrew/var/opttab/status.json"],
            read: { _ in nil }))
    }

    // 壊れたファイルはnil扱い（doctorが落ちない）
    func testCorruptFileIsTreatedAsMissing() {
        XCTAssertNil(Doctor.loadStatus(
            candidatePaths: ["/opt/homebrew/var/opttab/status.json"],
            read: { _ in Data("garbage".utf8) }))
    }
}
