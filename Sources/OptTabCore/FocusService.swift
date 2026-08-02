import AppKit
import ApplicationServices

public enum FocusService {
    /// Windowメニューとして探す対象のメニュータイトル（ローカライズ違いを許容）
    static let windowMenuTitles: Set<String> = ["Window", "ウインドウ", "ウィンドウ"]

    @MainActor
    public static func focus(windowID: UInt32, snapshot: WindowSnapshot) {
        let app = NSRunningApplication(processIdentifier: snapshot.appPID)
        guard let axWin = snapshot.axWindows[windowID] else {
            // AXハンドルが無い＝別Spaceのウィンドウ等（Chromium系はAXが現在Spaceしか列挙しない）。
            // Windowメニュー項目のAXPressならSpace跨ぎでジャンプできる。
            let title = snapshot.windows.first(where: { $0.id == windowID })?.title ?? ""
            if focusViaWindowMenu(appPID: snapshot.appPID, windowTitle: title) {
                NSLog("OptTab: focused via Window menu: %@", title)
            } else {
                NSLog("OptTab: Window menu fallback failed, activating app only (title=%@)", title)
                app?.activate()
            }
            return
        }
        // 最小化されていたら復元
        var minimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWin, kAXMinimizedAttribute as CFString,
                                         &minimized) == .success,
           (minimized as? Bool) == true {
            AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString,
                                         kCFBooleanFalse)
        }
        // メインウィンドウ化 → 前面へ → アプリをアクティブに
        AXUIElementSetAttributeValue(axWin, kAXMainAttribute as CFString,
                                     kCFBooleanTrue)
        let raiseErr = AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
        app?.activate()
        NSLog("OptTab: direct raise id=%u axTitle=%@ err=%d", windowID,
              axTitle(axWin), raiseErr.rawValue)
        if raiseErr != .success {
            NSLog("OptTab: AXRaise failed (%d) for window %u", raiseErr.rawValue, windowID)
        }
    }

    /// アプリのWindowメニューの全項目タイトルを返す（到達可能性判定に使う）。
    /// Windowメニューが見つからなければ空配列。
    static func windowMenuItemTitles(appPID: pid_t) -> [String] {
        let axApp = AXUIElementCreateApplication(appPID)
        var mb: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString,
                                            &mb) == .success,
              let menubarRef = mb, CFGetTypeID(menubarRef) == AXUIElementGetTypeID()
        else { return [] }
        let menubar = menubarRef as! AXUIElement
        for menu in axChildren(menubar) where windowMenuTitles.contains(axTitle(menu)) {
            guard let submenu = axChildren(menu).first else { continue }
            return axChildren(submenu).map { axTitle($0) }
        }
        return []
    }

    /// アプリのWindowメニューから対象ウィンドウの項目を探してAXPressする。
    /// メニュー項目は全Spaceのウィンドウを含むため、AXRaise不能なウィンドウへの公開APIでの唯一の経路。
    @MainActor
    static func focusViaWindowMenu(appPID: pid_t, windowTitle: String) -> Bool {
        guard !windowTitle.isEmpty else { return false }
        let axApp = AXUIElementCreateApplication(appPID)
        var mb: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString,
                                            &mb) == .success,
              let menubarRef = mb, CFGetTypeID(menubarRef) == AXUIElementGetTypeID()
        else { return false }
        let menubar = menubarRef as! AXUIElement

        for menu in axChildren(menubar) where windowMenuTitles.contains(axTitle(menu)) {
            guard let submenu = axChildren(menu).first else { continue }
            let items = axChildren(submenu)
            let titles = items.map { axTitle($0) }
            guard let idx = WindowMenuMatcher.bestIndex(windowTitle: windowTitle,
                                                        menuTitles: titles) else { continue }
            return AXUIElementPerformAction(items[idx], kAXPressAction as CFString) == .success
        }
        return false
    }

    private static func axChildren(_ el: AXUIElement) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString,
                                            &v) == .success,
              let arr = v as? [AXUIElement] else { return [] }
        return arr
    }

    private static func axTitle(_ el: AXUIElement) -> String {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString,
                                            &v) == .success else { return "" }
        return v as? String ?? ""
    }
}
