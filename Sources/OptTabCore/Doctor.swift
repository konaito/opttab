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

    public static func run() -> Int32 {
        let status = loadStatus(
            candidatePaths: StatusFile.candidatePaths(
                prefixes: StatusFile.defaultPrefixes),
            read: { try? Data(contentsOf: URL(fileURLWithPath: $0)) })

        let existing = Set(
            LegacyInstall.candidates
                .map(\.path)
                .filter { FileManager.default.fileExists(atPath: $0) })

        let report = DoctorReport.build(status: status,
                                        now: Date(),
                                        legacyExisting: existing)
        print(report.render())
        return report.exitCode
    }
}
