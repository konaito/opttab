import Foundation

public enum DaemonLaunchCheck {
    /// launchd が起動するのは <prefix>/var/opttab/opttab だけ。
    /// TCC は非バンドルバイナリを解決後の実パスで識別するので、
    /// 別パス（Homebrew の bin シンボリンク経由＝Cellar 実体）から常駐すると
    /// 許可の無いパスで再プロンプトが出て、イベントタップも二重になる。
    public static func isSupportedDaemonPath(_ resolvedExecutablePath: String) -> Bool {
        let components = (resolvedExecutablePath as NSString).pathComponents
        guard components.count >= 3 else { return false }
        let tail = components.suffix(3)
        return Array(tail) == ["var", "opttab", "opttab"]
    }

    /// このチェックを外す環境変数。リポジトリでの `swift run` やデバッグ用。
    public static let overrideEnvironmentKey = "OPTTAB_ALLOW_ANY_PATH"

    /// 常駐を拒否するときに stderr へ出す説明。
    /// CLIの利用者向け出力は他（help / doctor）と揃えて英語にする。
    public static func refusalMessage(resolvedExecutablePath: String) -> String {
        """
        opttab: refusing to run as a service from \(resolvedExecutablePath)
          Only <brew prefix>/var/opttab/opttab may run as the background service.
          macOS keys TCC grants for non-bundled binaries by the executable's
          resolved path, so starting the daemon from any other path re-prompts
          for Accessibility and Screen Recording and adds a second event tap
          fighting over ⌥⇥.
          start the service:  brew services start opttab
          (for development only, \(overrideEnvironmentKey)=1 skips this check)
        """
    }
}
