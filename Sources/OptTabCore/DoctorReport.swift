import Foundation

/// 旧インストールの残骸。新デーモンと同時に走ると
/// 2つのCGEventTapが ⌥⇥ を奪い合うので検出して警告する。
/// 消すのは越権なのでコマンドを表示するだけにする。
public enum LegacyInstall {
    public struct Candidate: Equatable {
        public let path: String
        public let advice: String

        public init(path: String, advice: String) {
            self.path = path
            self.advice = advice
        }
    }

    /// 旧メニューバー版が残す、あるいは Scripts/install-local.sh が作る LaunchAgent。
    public static let launchAgentPath =
        NSString(string: "~/Library/LaunchAgents/dev.konaito.opttab.plist")
            .expandingTildeInPath

    public static let candidates: [Candidate] = [
        Candidate(path: "/Applications/OptTab.app",
                  advice: "brew uninstall --cask opttab"),
        Candidate(path: NSString(string: "~/Applications/OptTab.app")
                    .expandingTildeInPath,
                  advice: "rm -rf ~/Applications/OptTab.app"),
        Candidate(path: launchAgentPath,
                  advice: "launchctl bootout gui/$UID/dev.konaito.opttab && "
                        + "rm -f ~/Library/LaunchAgents/dev.konaito.opttab.plist"),
    ]

    /// dev.konaito.opttab.plist は2種類ある。
    /// - Scripts/install-local.sh が作る開発用（ProgramArguments が <prefix>/var/opttab/opttab を指す）→ 正常、警告しない
    /// - 旧メニューバー版が残したもの（.app を指す）→ 二重タップの原因、警告する
    public static func launchAgentIsLegacy(programArgument: String?) -> Bool {
        guard let programArgument else { return true }
        return !DaemonLaunchCheck.isSupportedDaemonPath(programArgument)
    }

    public static func warnings(existing: Set<String>) -> [String] {
        candidates
            .filter { existing.contains($0.path) }
            .map { "leftover from the old install: \($0.path)\n    remove it: \($0.advice)" }
    }
}

public struct DoctorReport: Equatable {
    public enum Service: Equatable {
        case running(pid: Int32, version: String)
        /// 状態ファイルはあるがハートビートが途絶えている
        case notRunning
        /// 状態ファイルが無い（未起動、または別prefixにインストールされている）
        case statusUnavailable
    }

    /// デーモンのハートビートは5秒間隔。取りこぼしを見込んで30秒許容する。
    public static let freshnessTolerance: TimeInterval = 30

    public let service: Service
    public let accessibility: Bool
    public let screenRecording: Bool
    public let warnings: [String]

    public init(service: Service,
                accessibility: Bool,
                screenRecording: Bool,
                warnings: [String]) {
        self.service = service
        self.accessibility = accessibility
        self.screenRecording = screenRecording
        self.warnings = warnings
    }

    /// - Parameter pidAlive: status.json の pid が生きているか。
    ///   ハートビートの鮮度だけでは、停止直後の最大30秒を取りこぼす。
    ///   判定に使う値は呼び出し側（Doctor）が観測して渡す。
    public static func build(status: DaemonStatus?,
                             now: Date,
                             pidAlive: Bool,
                             legacyExisting: Set<String>) -> DoctorReport {
        let warnings = LegacyInstall.warnings(existing: legacyExisting)

        guard let status else {
            return DoctorReport(service: .statusUnavailable,
                                accessibility: false,
                                screenRecording: false,
                                warnings: warnings)
        }

        let fresh = DaemonStatus.isFresh(status, now: now,
                                         tolerance: freshnessTolerance)
        return DoctorReport(
            service: fresh && pidAlive
                ? .running(pid: status.pid, version: status.version)
                : .notRunning,
            accessibility: status.accessibility,
            screenRecording: status.screenRecording,
            warnings: warnings)
    }

    /// アクセシビリティはホットキーに必須。画面収録はサムネイル用の任意権限。
    public var exitCode: Int32 {
        switch service {
        case .running:
            return accessibility ? 0 : 1
        case .notRunning, .statusUnavailable:
            return 1
        }
    }

    public func render() -> String {
        var lines: [String] = []
        // 状態ファイルが無いときの権限値は「未許可」ではなく「不明」。
        // 未起動のユーザーにMISSINGと許可手順を出すのは誤誘導になる。
        var permissionsKnown = true

        switch service {
        case .running(let pid, let version):
            lines.append("service:          running (pid \(pid), version \(version))")
        case .notRunning:
            lines.append("service:          not running (heartbeat is stale)")
            lines.append("  start it:       brew services start opttab")
        case .statusUnavailable:
            lines.append("service:          not running (no status file)")
            lines.append("  start it:       brew services start opttab")
            permissionsKnown = false
        }

        if permissionsKnown {
            lines.append("Accessibility:    \(accessibility ? "granted" : "MISSING (required for the ⌥⇥ hotkey)")")
            if !accessibility {
                lines.append("  grant it:       System Settings > Privacy & Security > Accessibility")
                lines.append("  open directly:  open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'")
            }

            lines.append("Screen Recording: \(screenRecording ? "granted" : "missing (optional — thumbnails are replaced by icons)")")
            if !screenRecording {
                lines.append("  grant it:       System Settings > Privacy & Security > Screen Recording")
                lines.append("  open directly:  open 'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'")
            }
        } else {
            lines.append("Accessibility:    unknown (start the service first)")
            lines.append("Screen Recording: unknown (start the service first)")
        }

        for warning in warnings {
            lines.append("warning: \(warning)")
        }

        return lines.joined(separator: "\n")
    }
}
