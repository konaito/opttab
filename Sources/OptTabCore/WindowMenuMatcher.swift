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
        bestUnusedIndex(windowTitle: windowTitle, menuTitles: menuTitles, used: [])
    }

    static func bestUnusedIndex(windowTitle: String, menuTitles: [String],
                                used: Set<Int>) -> Int? {
        guard !windowTitle.isEmpty else { return nil }
        return menuTitles.indices.reversed().first {
            !used.contains($0) &&
            matches(windowTitle: windowTitle, menuTitle: menuTitles[$0])
        }
    }

    /// 切り替え可能なウィンドウだけを残す（メニュー項目の消費制）。
    /// Windowメニュー項目は実ウィンドウと1:1なので、
    /// 1) AXハンドル持ちのウィンドウが自分のメニュー項目を先に消費し、
    /// 2) AXなしのウィンドウは未消費の項目が残っている場合のみ1枚につき1項目で通す。
    /// これにより、実ウィンドウと同タイトルのネイティブタブ裏タブ（到達不能）が
    /// タイトル一致だけで到達可能と誤判定されるのを防ぐ。
    public static func reachableWindows(_ windows: [WindowInfo],
                                        hasAXHandle: (UInt32) -> Bool,
                                        menuTitles: [String]) -> [WindowInfo] {
        var used = Set<Int>()
        for w in windows where hasAXHandle(w.id) {
            if let i = bestUnusedIndex(windowTitle: w.title,
                                       menuTitles: menuTitles, used: used) {
                used.insert(i)
            }
        }
        return windows.filter { w in
            if hasAXHandle(w.id) { return true }
            if let i = bestUnusedIndex(windowTitle: w.title,
                                       menuTitles: menuTitles, used: used) {
                used.insert(i)
                return true
            }
            return false
        }
    }
}
