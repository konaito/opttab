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
    public static func refusalMessage(resolvedExecutablePath: String) -> String {
        """
        opttab: この場所からは常駐できない: \(resolvedExecutablePath)
          常駐できるのは <brew prefix>/var/opttab/opttab だけ。
          macOS は非バンドルバイナリの TCC 許可を実行ファイルの実パスで識別するため、
          別パスから起動するとアクセシビリティと画面収録が再度要求され、
          イベントタップが二重になって ⌥⇥ を奪い合う。
          サービスとして起動する: brew services start opttab
          （開発時に意図して別パスから動かすなら \(overrideEnvironmentKey)=1）
        """
    }
}
