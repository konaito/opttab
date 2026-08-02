import AppKit
import ApplicationServices

public enum FocusService {
    @MainActor
    public static func focus(windowID: UInt32, snapshot: WindowSnapshot) {
        let app = NSRunningApplication(processIdentifier: snapshot.appPID)
        guard let axWin = snapshot.axWindows[windowID] else {
            // AX対応が取れなかった場合はアプリをactivateするだけ（最低限の縮退）
            app?.activate()
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
        AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
        app?.activate()
    }
}
