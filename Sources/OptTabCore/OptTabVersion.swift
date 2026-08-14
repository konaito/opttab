import Foundation

public enum OptTabVersion {
    /// バイナリの __TEXT,__info_plist セクションに埋め込んだ
    /// CFBundleShortVersionString を読む。
    public static var current: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? "unknown"
    }
}
