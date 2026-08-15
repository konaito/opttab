import Foundation

/// `launchctl print` が報告するジョブの状態。
///
/// 状態ファイルのハートビートだけでは見えないものがある。`keep_alive` の
/// クラッシュループは再起動のたびに新しい pid で新鮮な status.json を書くため、
/// ハートビートは常に健全に見える。launchd 側の記録がその嘘を破る。
///
/// 実測（macOS 26.5）で確かめた挙動:
/// - 健全: `state = running` / `runs = 1` / `last exit code = (never exited)`
/// - クラッシュループ: `state = spawn scheduled` / `last exit code = <n>`
/// - `runs` は launchd が再起動するたびに増える（1→2→3）。
///   `brew services restart` はジョブを作り直すので 1 に戻る
/// - **SIGKILL で殺された場合 `last exit code` の行自体が出ない。**
///   そのため終了コードだけを見ていると信号殺しを取りこぼす。`runs` はこれを拾う
public struct LaunchdJob: Equatable {
    public enum State: Equatable {
        case running(pid: Int32)
        /// launchd が再起動をスロットリング中。即座に終了する keep_alive
        /// ジョブはこの状態に落ち着く
        case spawnScheduled
        case notRunning
        /// 解釈できなかった state。macOS のバージョン差で語彙が変わっても
        /// 落ちずに素通しできるようにしておく
        case other(String)
    }

    public enum LastExit: Equatable {
        case neverExited
        case code(Int)
        /// `last exit code` 行が無かった（SIGKILL 直後がこれ）
        case unknown
    }

    public let label: String
    public let state: State
    public let lastExit: LastExit
    /// launchd がこのジョブを起動した回数。読めなければ nil。
    public let runs: Int?

    public init(label: String, state: State, lastExit: LastExit, runs: Int? = nil) {
        self.label = label
        self.state = state
        self.lastExit = lastExit
        self.runs = runs
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

    /// **今まさに**壊れている場合だけ一文を返す。
    ///
    /// これだけが終了コードを失敗にする。過去に一度落ちて自力で復帰した
    /// サービスまで永久に赤くし続けるのは、健全な今の状態を偽ることになる。
    public var crashSignal: String? {
        guard state == .spawnScheduled else { return nil }
        let detail: String
        if case .code(let code) = lastExit {
            detail = " (last exit code \(code))"
        } else {
            detail = ""
        }
        return "launchd is throttling respawns\(detail) — the service is crash-looping"
    }

    /// 過去に落ちて launchd が復帰させた形跡。警告はするが失敗にはしない。
    ///
    /// `runs` を主信号にしているのは、SIGKILL のように `last exit code` が
    /// 残らない死に方も拾えるため。
    public var restartSignal: String? {
        guard crashSignal == nil else { return nil }
        // 今止まっているジョブに「死んで復帰した」とは言えない。
        // その状態は別途「launchd はジョブが走っていないと言っている」で報告する。
        // isRunning ではなく notRunning で弾くのは、pid が読めなかっただけの
        // .other("running") から再起動の警告を落とさないため。
        guard state != .notRunning else { return nil }

        let restarts = (runs ?? 1) - 1
        var detail = ""
        if case .code(let code) = lastExit { detail = ", last exit code \(code)" }

        if restarts > 0 {
            return "the service has been restarted \(restarts) time"
                 + (restarts == 1 ? "" : "s")
                 + " by launchd\(detail) — it died and recovered"
        }
        if case .code = lastExit {
            return "the service has exited at least once\(detail) — launchd restarted it"
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

        return LaunchdJob(label: label,
                          state: state,
                          lastExit: lastExit,
                          runs: firstValue(of: "runs", in: output).flatMap(Int.init))
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
