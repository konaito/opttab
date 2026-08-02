/// ウィンドウタイトルとWindowメニュー項目タイトルの照合。
/// Chromium系アプリ（Dia/Chrome等）はAXが現在Spaceのウィンドウしか列挙しないため、
/// 別SpaceのウィンドウへはWindowメニュー項目のAXPressでジャンプする。その照合ロジック（純粋関数）。
public enum WindowMenuMatcher {
    /// 完全一致、または「…」省略を許した前方一致（どちら側が省略されていても可）。
    /// 空タイトルは常に不一致（誤爆防止）。
    public static func matches(windowTitle: String, menuTitle: String) -> Bool {
        let w = windowTitle.hasSuffix("…") ? String(windowTitle.dropLast()) : windowTitle
        let m = menuTitle.hasSuffix("…") ? String(menuTitle.dropLast()) : menuTitle
        guard !w.isEmpty, !m.isEmpty else { return false }
        return w.hasPrefix(m) || m.hasPrefix(w)
    }

    /// メニュー項目タイトル列から対象ウィンドウに対応するindexを返す。
    /// ウィンドウ一覧項目はメニュー末尾に並ぶため、末尾側から探す。
    public static func bestIndex(windowTitle: String, menuTitles: [String]) -> Int? {
        guard !windowTitle.isEmpty else { return nil }
        return menuTitles.indices.reversed().first {
            matches(windowTitle: windowTitle, menuTitle: menuTitles[$0])
        }
    }
}
