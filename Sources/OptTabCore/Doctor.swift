import AppKit
import Darwin
import Foundation

/// `opttab doctor` の実体。ファイルI/Oだけを持ち、判定は DoctorReport に委ねる。
public enum Doctor {
    /// 候補パスを順に読み、最初に成功したものを返す。
    /// 読み取り関数を差し替えられるようにしてテスト可能にしている。
    public static func loadStatus(candidatePaths: [String],
                                  read: (String) -> Data?) -> DaemonStatus? {
        for path in candidatePaths {
            guard let data = read(path) else { continue }
            if let status = try? DaemonStatus.decode(data) { return status }
        }
        return nil
    }

    /// LaunchAgent の plist から ProgramArguments[0] を取り出す。
    /// プロセスを起こさずに Data から直接読む。
    public static func programArgument(fromPlist data: Data) -> String? {
        guard let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [Any],
              let first = arguments.first as? String
        else { return nil }
        return first
    }

    /// 残骸として警告すべきパスを決める。
    /// LaunchAgent だけは存在するかどうかではなく、何を起動するかで判定する。
    /// install-local.sh が作った開発用の plist を「残骸」と呼んで
    /// 消させると、動いている環境を壊すことになる。
    public static func legacyExisting(exists: (String) -> Bool,
                                      readPlist: (String) -> Data?) -> Set<String> {
        var result: Set<String> = []
        for candidate in LegacyInstall.candidates where exists(candidate.path) {
            if candidate.path == LegacyInstall.launchAgentPath {
                let argument = readPlist(candidate.path)
                    .flatMap(programArgument(fromPlist:))
                guard LegacyInstall.launchAgentIsLegacy(programArgument: argument)
                else { continue }
            }
            result.insert(candidate.path)
        }
        return result
    }

    /// doctor が問い合わせるジョブのラベル。
    /// brew services 経由と、Scripts/install-local.sh が作る開発用の両方を見る。
    public static let serviceLabels = ["homebrew.mxcl.opttab", "dev.konaito.opttab"]

    /// 最初に見つかったジョブを返す。読み取り関数を差し替えられるようにしてある。
    public static func launchdJob(labels: [String],
                                  printJob: (String) -> String?) -> LaunchdJob? {
        for label in labels {
            guard let output = printJob(label),
                  let job = LaunchctlPrintParser.parse(output, label: label)
            else { continue }
            return job
        }
        return nil
    }

    /// `launchctl print gui/<uid>/<label>` を実行して標準出力を返す。
    /// ジョブが無ければ非ゼロ終了するので nil にする。
    private static func launchctlPrint(_ label: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(getuid())/\(label)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// 動作中のアプリを NSWorkspace から集める。純ロジックへ渡すための薄い層。
    private static func runningApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications.map {
            RunningApp(bundleIdentifier: $0.bundleIdentifier,
                       bundlePath: $0.bundleURL?.path)
        }
    }

    public static func run() -> Int32 {
        let status = loadStatus(
            candidatePaths: StatusFile.candidatePaths(
                prefixes: StatusFile.defaultPrefixes),
            read: { try? Data(contentsOf: URL(fileURLWithPath: $0)) })

        let existing = legacyExisting(
            exists: { FileManager.default.fileExists(atPath: $0) },
            readPlist: { try? Data(contentsOf: URL(fileURLWithPath: $0)) })

        // ハートビートは5秒間隔なので、止めた直後の30秒は「動いている」に見える。
        // シグナル0の送信でプロセスの生存を直接確かめて、その窓を潰す。
        let pidAlive = status.map { kill($0.pid, 0) == 0 } ?? false

        let report = DoctorReport.build(
            status: status,
            now: Date(),
            pidAlive: pidAlive,
            legacyExisting: existing,
            launchd: launchdJob(labels: serviceLabels, printJob: launchctlPrint),
            runningLegacyApps: LegacyInstall.runningLegacyApps(runningApps()))
        print(report.render())
        return report.exitCode
    }
}
