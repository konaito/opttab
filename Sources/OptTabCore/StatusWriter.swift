import Foundation

/// 状態ファイルへの書き込みだけを持つ薄いラッパ。
public struct StatusWriter {
    private let path: String

    public init(path: String) {
        self.path = path
    }

    public func write(_ status: DaemonStatus) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try DaemonStatus.encode(status).write(to: url, options: .atomic)
    }

    /// 実行中プロセスの現在値を集める。権限の読み取りはここだけに閉じる。
    public static func currentStatus(executablePath: String,
                                     now: Date) -> DaemonStatus {
        DaemonStatus(pid: ProcessInfo.processInfo.processIdentifier,
                     version: OptTabVersion.current,
                     executablePath: executablePath,
                     accessibility: Permissions.accessibilityTrusted,
                     screenRecording: Permissions.screenRecordingGranted,
                     updatedAt: now)
    }
}
