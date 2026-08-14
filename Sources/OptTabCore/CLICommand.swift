import Foundation

/// バイナリ1つでデーモン本体とCLIサブコマンドを兼ねるための引数解釈。
public enum CLICommand: Equatable {
    /// 引数なし。launchdから起動される常駐モード。
    case daemon
    case version
    case doctor
    case help
    case unknown(String)

    /// プログラム名を除いた引数列を解釈する。
    public static func parse(_ arguments: [String]) -> CLICommand {
        guard let first = arguments.first else { return .daemon }
        switch first {
        case "--version", "-v": return .version
        case "--help", "-h": return .help
        case "doctor": return .doctor
        default: return .unknown(first)
        }
    }

    public static let helpText = """
        opttab — Option+Tab window switcher for macOS

        usage:
          opttab              run as the background service (launchd invokes this)
          opttab doctor       report service state and permissions
          opttab --version    print version
          opttab --help       print this help

        The service is managed by Homebrew:
          brew services start opttab
          brew services stop opttab
          brew services restart opttab
        """
}
