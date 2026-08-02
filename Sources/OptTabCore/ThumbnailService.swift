import CoreGraphics
import ScreenCaptureKit

public actor ThumbnailService {
    private var cache: [UInt32: CGImage] = [:]

    public init() {}

    public func cached(for id: UInt32) -> CGImage? { cache[id] }

    /// ウィンドウ単体のスクショ。失敗時（別Spaceで取れない等）は過去のキャッシュを返す
    public func capture(_ window: SCWindow) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        // サムネイル用途なので1/2スケールで十分
        config.width = max(1, Int(window.frame.width) / 2)
        config.height = max(1, Int(window.frame.height) / 2)
        config.showsCursor = false
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
            cache[window.windowID] = image
            return image
        } catch {
            return cache[window.windowID]
        }
    }
}
