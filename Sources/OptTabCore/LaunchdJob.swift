import Foundation

/// `launchctl print` が報告するジョブの状態。
///
/// 状態ファイルのハートビートだけでは見えないものがある。`keep_alive` の
/// クラッシュループは再起動のたびに新しい pid で新鮮な status.json を書くため、
/// ハートビートは常に健全に見える。launchd 側の記録がその嘘を破る。
public struct LaunchdJob: Equatable {
    public enum State: Equatable {
        case running(pid: Int32)
        /// launchd が再起動をスロットリング中。実測では、即座に終了する
        /// keep_alive ジョブはこの状態に落ち着く
        case spawnScheduled
        case notRunning
        /// 解釈できなかった state。macOS のバージョン差で語彙が変わっても
        /// 落ちずに素通しできるようにしておく
        case other(String)
    }

    public enum LastExit: Equatable {
        case neverExited
        case code(Int)
        /// `last exit code` 行が無かった
        case unknown
    }

    public let label: String
    public let state: State
    public let lastExit: LastExit

    public init(label: String, state: State, lastExit: LastExit) {
        self.label = label
        self.state = state
        self.lastExit = lastExit
    }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// 人が読める一行の状態表現。
    public var stateDescription: String {
        switch state {
        case .running(let pid): return "running (pid \(pid))"
        case .spawnScheduled: return "spawn scheduled (launchd is waiting to respawn)"
        case .notRunning: return "not running"
        case .other(let raw): return raw
        }
    }

    /// 異常があれば人間向けの一文を返す。正常なら nil。
    ///
    /// OptTab の常駐は正常なら決して終了しない。したがって終了コードが
    /// 記録されていること自体が、値によらず異常を意味する。
    public var crashSignal: String? {
        let exitDetail: String
        switch lastExit {
        case .code(let code): exitDetail = " (last exit code \(code))"
        case .neverExited, .unknown: exitDetail = ""
        }

        if state == .spawnScheduled {
            return "launchd is throttling respawns\(exitDetail) — "
                 + "the service is crash-looping"
        }
        if case .code = lastExit {
            return "the service has exited at least once\(exitDetail) — "
                 + "launchd restarted it"
        }
        return nil
    }
}

/// `launchctl print` の出力から必要な事実だけを抜く。
///
/// 出力形式は macOS のバージョンで変わりうるので、読めなかったものは
/// エラーにせず `unknown` / `other` に縮退させる。doctor が壊れるより、
/// 分からないと言うほうがましなため。
public enum LaunchctlPrintParser {
    public static func parse(_ output: String, label: String) -> LaunchdJob? {
        guard let stateValue = firstValue(of: "state", in: output) else { return nil }

        let state: LaunchdJob.State
        switch stateValue {
        case "running":
            // pid が取れないうちは running と言い切らない
            state = firstValue(of: "pid", in: output)
                .flatMap(Int32.init)
                .map(LaunchdJob.State.running) ?? .other(stateValue)
        case "spawn scheduled":
            state = .spawnScheduled
        case "not running":
            state = .notRunning
        default:
            state = .other(stateValue)
        }

        let lastExit: LaunchdJob.LastExit
        switch firstValue(of: "last exit code", in: output) {
        case .none:
            lastExit = .unknown
        case .some("(never exited)"):
            lastExit = .neverExited
        case .some(let value):
            lastExit = Int(value).map(LaunchdJob.LastExit.code) ?? .unknown
        }

        return LaunchdJob(label: label, state: state, lastExit: lastExit)
    }

    /// 最初に現れた `key = value` を返す。
    /// `launchctl print` はエンドポイントごとに深くインデントした
    /// `state = active` を後ろに並べるので、先頭一致がトップレベルにあたる。
    private static func firstValue(of key: String, in output: String) -> String? {
        let prefix = key + " = "
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(prefix) else { continue }
            return String(trimmed.dropFirst(prefix.count))
        }
        return nil
    }
}

/// 動作中のアプリケーション1件。NSWorkspace を純ロジックから切り離すための器。
public struct RunningApp: Equatable {
    public let bundleIdentifier: String?
    public let bundlePath: String?

    public init(bundleIdentifier: String?, bundlePath: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
    }
}
