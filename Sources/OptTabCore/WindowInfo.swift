import CoreGraphics

public struct WindowInfo: Identifiable, Equatable, Sendable {
    public let id: UInt32
    public let title: String
    public let frame: CGRect
    public let layer: Int
    public let isOnScreen: Bool
    public var isMinimized: Bool

    public init(id: UInt32, title: String, frame: CGRect, layer: Int,
                isOnScreen: Bool, isMinimized: Bool) {
        self.id = id
        self.title = title
        self.frame = frame
        self.layer = layer
        self.isOnScreen = isOnScreen
        self.isMinimized = isMinimized
    }
}
