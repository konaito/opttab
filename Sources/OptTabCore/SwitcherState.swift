public struct SwitcherState: Equatable {
    public private(set) var windows: [WindowInfo]
    public private(set) var selectedIndex: Int

    /// ウィンドウ2枚未満なら発動しない（nil）
    public init?(windows: [WindowInfo], reverse: Bool = false) {
        guard windows.count >= 2 else { return nil }
        self.windows = windows
        self.selectedIndex = reverse ? windows.count - 1 : 1
    }

    public var selected: WindowInfo { windows[selectedIndex] }

    public mutating func selectNext() {
        selectedIndex = (selectedIndex + 1) % windows.count
    }

    public mutating func selectPrevious() {
        selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
    }

    public mutating func select(_ index: Int) {
        guard windows.indices.contains(index) else { return }
        selectedIndex = index
    }
}
