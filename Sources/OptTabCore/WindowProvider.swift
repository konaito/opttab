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

        // 別Spaceのウィンドウも含めて列挙（onScreenWindowsOnly: false が肝）
        let content = try await SCShareableContent
            .excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let scList = content.windows.filter {
            $0.owningApplication?.processID == pid
        }

        var infos: [WindowInfo] = scList.map { w in
            WindowInfo(id: w.windowID,
                       title: w.title ?? "",
                       frame: w.frame,
                       layer: w.windowLayer,
                       isOnScreen: w.isOnScreen,
                       isMinimized: false)
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
        let descriptors = axList.map {
            AXWindowDescriptor(title: Self.axTitle($0),
                               frame: Self.axFrame($0),
                               isMinimized: Self.axMinimized($0))
        }
        let mapping = WindowMatcher.match(cg: infos, ax: descriptors)
        var axHandles: [UInt32: AXUIElement] = [:]
        for (wid, idx) in mapping {
            axHandles[wid] = axList[idx]
            if let i = infos.firstIndex(where: { $0.id == wid }) {
                infos[i].isMinimized = descriptors[idx].isMinimized
            }
        }

        // 並び順を決定
        let frontOrder = Self.onScreenOrder(pid: pid)
        let eligible = WindowOrdering.eligible(infos)
        let sorted = WindowOrdering.sortedByFrontOrder(eligible,
                                                       frontOrder: frontOrder)
        let ordered = WindowOrdering.ordered(sorted, frontID: frontOrder.first)

        var scMap: [UInt32: SCWindow] = [:]
        for w in scList { scMap[w.windowID] = w }

        return WindowSnapshot(appPID: pid,
                              appName: app.localizedName ?? "",
                              appIcon: app.icon,
                              windows: ordered,
                              scWindows: scMap,
                              axWindows: axHandles)
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
