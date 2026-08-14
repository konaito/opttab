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
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
