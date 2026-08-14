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

    private func plist(programArgument: String) -> Data {
        Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
            "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key><string>dev.konaito.opttab</string>
                <key>ProgramArguments</key><array><string>\(programArgument)</string></array>
            </dict>
            </plist>
            """.utf8)
    }

    func testReadsProgramArgumentFromPlist() {
        XCTAssertEqual(
            Doctor.programArgument(
                fromPlist: plist(programArgument: "/opt/homebrew/var/opttab/opttab")),
            "/opt/homebrew/var/opttab/opttab")
    }

    func testProgramArgumentIsNilForGarbage() {
        XCTAssertNil(Doctor.programArgument(fromPlist: Data("not a plist".utf8)))
    }

    // ProgramArguments が無いplistもnil（＝疑わしい扱いになる）
    func testProgramArgumentIsNilWhenKeyMissing() {
        let data = Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict>
                <key>Label</key><string>dev.konaito.opttab</string>
            </dict></plist>
            """.utf8)
        XCTAssertNil(Doctor.programArgument(fromPlist: data))
    }

    // install-local.sh が作った開発用LaunchAgentは残骸に数えない
    func testDevLaunchAgentIsNotReportedAsLeftover() {
        let existing = Doctor.legacyExisting(
            exists: { $0 == LegacyInstall.launchAgentPath },
            readPlist: { _ in self.plist(programArgument: "/opt/homebrew/var/opttab/opttab") })
        XCTAssertTrue(existing.isEmpty)
    }

    // 旧メニューバー版の .app を起動するLaunchAgentは残骸として報告する
    func testAppLaunchAgentIsReportedAsLeftover() {
        let existing = Doctor.legacyExisting(
            exists: { $0 == LegacyInstall.launchAgentPath },
            readPlist: { _ in
                self.plist(programArgument: "/Applications/OptTab.app/Contents/MacOS/OptTab")
            })
        XCTAssertEqual(existing, [LegacyInstall.launchAgentPath])
    }

    // plistが読めないときは疑わしい側に倒す
    func testUnreadableLaunchAgentIsReportedAsLeftover() {
        let existing = Doctor.legacyExisting(
            exists: { $0 == LegacyInstall.launchAgentPath },
            readPlist: { _ in nil })
        XCTAssertEqual(existing, [LegacyInstall.launchAgentPath])
    }

    // .app 側の候補は存在するかどうかだけで判定する（plistは読まない）
    func testAppCandidatesUsePlainExistenceCheck() {
        let existing = Doctor.legacyExisting(
            exists: { $0 == "/Applications/OptTab.app" },
            readPlist: { _ in XCTFail("plistは読まないはず"); return nil })
        XCTAssertEqual(existing, ["/Applications/OptTab.app"])
    }
}
