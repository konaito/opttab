import AppKit
import Foundation
import OptTabCore

switch CLICommand.parse(Array(CommandLine.arguments.dropFirst())) {
case .version:
    print(OptTabVersion.current)

case .help:
    print(CLICommand.helpText)

case .doctor:
    exit(Doctor.run())

case .unknown(let argument):
    FileHandle.standardError.write(
        Data("opttab: unknown argument '\(argument)'\n".utf8))
    FileHandle.standardError.write(Data((CLICommand.helpText + "\n").utf8))
    exit(2)

case .daemon:
    // TCC は実行ファイルの実パスで許可を識別する。固定パス以外から常駐すると
    // 許可の無いパスで再プロンプトが出て、イベントタップも二重になる。
    let resolvedPath = URL(fileURLWithPath: CommandLine.arguments[0])
        .resolvingSymlinksInPath().path
    let allowAnyPath = ProcessInfo.processInfo
        .environment[DaemonLaunchCheck.overrideEnvironmentKey] == "1"
    if !allowAnyPath && !DaemonLaunchCheck.isSupportedDaemonPath(resolvedPath) {
        FileHandle.standardError.write(Data(
            (DaemonLaunchCheck.refusalMessage(
                resolvedExecutablePath: resolvedPath) + "\n").utf8))
        exit(3)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
