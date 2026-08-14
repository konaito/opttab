import Foundation

/// 常駐しているデーモンが自分の状態を書き出すためのモデル。
///
/// `opttab doctor` が自プロセスで `AXIsProcessTrusted()` を呼んでも、
/// 答えるのは呼び出し元のターミナルについてであってデーモンについてではない。
/// 権限の有無が問われるのは固定パスで動いているデーモンだけなので、
/// デーモン自身に書かせて doctor はそれを読む。
public struct DaemonStatus: Codable, Equatable {
    public let pid: Int32
    public let version: String
    public let executablePath: String
    public let accessibility: Bool
    public let screenRecording: Bool
    public let updatedAt: Date

    public init(pid: Int32,
                version: String,
                executablePath: String,
                accessibility: Bool,
                screenRecording: Bool,
                updatedAt: Date) {
        self.pid = pid
        self.version = version
        self.executablePath = executablePath
        self.accessibility = accessibility
        self.screenRecording = screenRecording
        self.updatedAt = updatedAt
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func encode(_ status: DaemonStatus) throws -> Data {
        try encoder.encode(status)
    }

    public static func decode(_ data: Data) throws -> DaemonStatus {
        try decoder.decode(DaemonStatus.self, from: data)
    }

    /// デーモンは5秒ごとに書き直す。許容を超えて古ければ死んでいるとみなす。
    /// 時計の巻き戻りで誤判定しないよう、未来の時刻は常に新鮮扱いにする。
    public static func isFresh(_ status: DaemonStatus,
                               now: Date,
                               tolerance: TimeInterval) -> Bool {
        now.timeIntervalSince(status.updatedAt) <= tolerance
    }
}

public enum StatusFile {
    public static let fileName = "status.json"

    /// 実行ファイルの隣に置く。launchdが起動するのは
    /// <prefix>/var/opttab/opttab なので <prefix>/var/opttab/status.json になる。
    public static func path(forExecutable executablePath: String) -> String {
        (executablePath as NSString).deletingLastPathComponent
            + "/" + fileName
    }

    /// doctorはCellar以下から実行されるので自分の位置からvarを導けない。
    /// 既知のHomebrew prefixを順に探す。
    public static func candidatePaths(prefixes: [String]) -> [String] {
        prefixes.map { "\($0)/var/opttab/\(fileName)" }
    }

    /// Apple Silicon と Intel の標準prefix。
    public static let defaultPrefixes = ["/opt/homebrew", "/usr/local"]
}
