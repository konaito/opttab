import AppKit
import ApplicationServices
import ScreenCaptureKit

public struct WindowSnapshot {
    public let appPID: pid_t
    public let appName: String
    public let appIcon: NSImage?
    public var windows: [WindowInfo]
    public let scWindows: [UInt32: SCWindow]
    public let axWindows: [UInt32: AXUIElement]
}

public enum WindowProviderError: Error {
    case noFrontmostApp
}

public final class WindowProvider {
    public init() {}

    /// 最前面アプリの全ウィンドウ（別Space・最小化含む）のスナップショット
    public func snapshot() async throws -> WindowSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw WindowProviderError.noFrontmostApp
        }
        let pid = app.processIdentifier

        var infos: [WindowInfo]
        var scMap: [UInt32: SCWindow] = [:]

        do {
            // 別Spaceのウィンドウも含めて列挙（onScreenWindowsOnly: false が肝）
            let content = try await SCShareableContent
                .excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let scList = content.windows.filter {
                $0.owningApplication?.processID == pid
            }
            infos = scList.map { w in
                WindowInfo(id: w.windowID,
                           title: w.title ?? "",
                           frame: w.frame,
                           layer: w.windowLayer,
                           isOnScreen: w.isOnScreen,
                           isMinimized: false)
            }
            for w in scList { scMap[w.windowID] = w }
        } catch {
            // 画面収録許可なし等でSCShareableContentが失敗 → CGWindowListで縮退取得
            // （scMapは空のまま → サムネイル取得はスキップされ、アイコン表示の縮退モードになる）
            NSLog("OptTab: SCShareableContent failed, falling back to CGWindowList: \(error)")
            infos = Self.cgWindowListFallback(pid: pid)
        }

        // AXウィンドウと突き合わせ（最小化フラグと操作ハンドルを得る）
        let axApp = AXUIElementCreateApplication(pid)
        var axValue: CFTypeRef?
        var axList: [AXUIElement] = []
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString,
                                         &axValue) == .success,
           let arr = axValue as? [AXUIElement] {
            axList = arr
        }
        let allDescriptors = axList.map {
            AXWindowDescriptor(title: Self.axTitle($0),
                               frame: Self.axFrame($0),
                               isMinimized: Self.axMinimized($0))
        }
        // タブバー等の付属AXウィンドウを突き合わせ対象から外す（誤マッチ防止）
        let axIndices = WindowMatcher.eligibleAXIndices(allDescriptors)
        let descriptors = axIndices.map { allDescriptors[$0] }
        let mapping = WindowMatcher.match(cg: infos, ax: descriptors)
        var axHandles: [UInt32: AXUIElement] = [:]
        for (wid, idx) in mapping {
            let original = axIndices[idx]
            axHandles[wid] = axList[original]
            if let i = infos.firstIndex(where: { $0.id == wid }) {
                // SCWindow.titleがnilだった場合や縮退モード（タイトル取得不可）を
                // AXのタイトルで補う。eligible()の判定に使われるためsortより前に行う。
                let old = infos[i]
                let title = old.title.isEmpty ? allDescriptors[original].title : old.title
                infos[i] = WindowInfo(id: old.id, title: title, frame: old.frame,
                                      layer: old.layer, isOnScreen: old.isOnScreen,
                                      isMinimized: allDescriptors[original].isMinimized)
            }
        }

        // 並び順を決定
        let frontOrder = Self.onScreenOrder(pid: pid)
        let eligible = WindowOrdering.eligible(infos)
        let sorted = WindowOrdering.sortedByFrontOrder(eligible,
                                                       frontOrder: frontOrder)
        let ordered = WindowOrdering.ordered(sorted, frontID: frontOrder.first)

        // 到達不能ウィンドウの除外（メニュー項目の消費制）:
        // AXハンドルが無く、未消費のWindowメニュー項目も無いCGウィンドウは、
        // ネイティブタブの裏タブ等で切り替え手段が存在しない。候補に出さない。
        // 実ウィンドウと同タイトルの裏タブを弾くため、単純なタイトル一致ではなく
        // 「メニュー項目1つにつきウィンドウ1枚」で判定する。
        var reachable = ordered
        if ordered.contains(where: { axHandles[$0.id] == nil }) {
            let menuTitles = FocusService.windowMenuItemTitles(appPID: pid)
            reachable = WindowMenuMatcher.reachableWindows(
                ordered,
                hasAXHandle: { axHandles[$0] != nil },
                menuTitles: menuTitles)
            if reachable.count != ordered.count {
                NSLog("OptTab: excluded %d unreachable window(s) (native tabs etc.)",
                      ordered.count - reachable.count)
            }
        }

        return WindowSnapshot(appPID: pid,
                              appName: app.localizedName ?? "",
                              appIcon: app.icon,
                              windows: reachable,
                              scWindows: scMap,
                              axWindows: axHandles)
    }

    /// 画面収録許可なしでSCShareableContentが使えない場合のCGWindowListベース縮退取得
    /// タイトルは取得できない（AXマッチング側で補完される）
    static func cgWindowListFallback(pid: pid_t) -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { d -> WindowInfo? in
            guard let p = d[kCGWindowOwnerPID as String] as? Int32, p == pid,
                  let n = d[kCGWindowNumber as String] as? UInt32,
                  let layer = d[kCGWindowLayer as String] as? Int,
                  let boundsDict = d[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }
            let isOnScreen = d[kCGWindowIsOnscreen as String] as? Bool ?? false
            return WindowInfo(id: n,
                              title: "",
                              frame: bounds,
                              layer: layer,
                              isOnScreen: isOnScreen,
                              isMinimized: false)
        }
    }

    /// 現在のSpaceで前面→背面順のCGWindowID列（レイヤー0のみ）
    static func onScreenOrder(pid: pid_t) -> [UInt32] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            guard let p = d[kCGWindowOwnerPID as String] as? Int32, p == pid,
                  let layer = d[kCGWindowLayer as String] as? Int, layer == 0,
                  let n = d[kCGWindowNumber as String] as? UInt32
            else { return nil }
            return n
        }
    }

    static func axTitle(_ el: AXUIElement) -> String {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString,
                                            &v) == .success else { return "" }
        return v as? String ?? ""
    }

    static func axMinimized(_ el: AXUIElement) -> Bool {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXMinimizedAttribute as CFString,
                                            &v) == .success else { return false }
        return v as? Bool ?? false
    }

    static func axFrame(_ el: AXUIElement) -> CGRect {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        var origin = CGPoint.zero
        var size = CGSize.zero
        if AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString,
                                         &posValue) == .success,
           let pv = posValue, CFGetTypeID(pv) == AXValueGetTypeID() {
            AXValueGetValue(pv as! AXValue, .cgPoint, &origin)
        }
        if AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString,
                                         &sizeValue) == .success,
           let sv = sizeValue, CFGetTypeID(sv) == AXValueGetTypeID() {
            AXValueGetValue(sv as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }
}
