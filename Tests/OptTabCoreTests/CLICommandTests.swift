import XCTest
@testable import OptTabCore

final class CLICommandTests: XCTestCase {
    // 引数なし = デーモンとして常駐する
    func testNoArgumentsIsDaemon() {
        XCTAssertEqual(CLICommand.parse([]), .daemon)
    }

    func testVersionFlag() {
        XCTAssertEqual(CLICommand.parse(["--version"]), .version)
        XCTAssertEqual(CLICommand.parse(["-v"]), .version)
    }

    func testHelpFlag() {
        XCTAssertEqual(CLICommand.parse(["--help"]), .help)
        XCTAssertEqual(CLICommand.parse(["-h"]), .help)
    }

    func testDoctorSubcommand() {
        XCTAssertEqual(CLICommand.parse(["doctor"]), .doctor)
    }

    // 未知の引数は unknown。デーモンとして起動してしまわないこと
    func testUnknownArgument() {
        XCTAssertEqual(CLICommand.parse(["--bogus"]), .unknown("--bogus"))
        XCTAssertEqual(CLICommand.parse(["status"]), .unknown("status"))
    }

    // 余分な引数は最初のものだけ見る（launchdはProgramArgumentsを1つしか渡さない）
    func testFirstArgumentWins() {
        XCTAssertEqual(CLICommand.parse(["doctor", "--version"]), .doctor)
    }

    func testHelpTextMentionsEverySubcommand() {
        let text = CLICommand.helpText
        XCTAssertTrue(text.contains("doctor"))
        XCTAssertTrue(text.contains("--version"))
    }
}
