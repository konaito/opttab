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

        let report = DoctorReport.build(status: status,
                                        now: Date(),
                                        pidAlive: pidAlive,
                                        legacyExisting: existing)
        print(report.render())
        return report.exitCode
    }
}
