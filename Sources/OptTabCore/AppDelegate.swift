import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: HotkeyMonitor?
    private var controller: SwitcherController?
    private var retryTimer: Timer?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 画面収録は未許可でも動く（サムネイル無しの縮退運転）が、初回に要求はする
        if !Permissions.screenRecordingGranted {
            Permissions.requestScreenRecording()
        }

        let controller = SwitcherController()
        self.controller = controller
        let monitor = HotkeyMonitor()
        monitor.delegate = controller
        self.monitor = monitor

        if !startMonitor() {
            // アクセシビリティ未許可: ダイアログを出しつつ、許可されるまで3秒ごとに再試行
            Permissions.promptAccessibility()
            retryTimer = Timer.scheduledTimer(withTimeInterval: 3.0,
                                              repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if self.startMonitor() {
                        self.retryTimer?.invalidate()
                        self.retryTimer = nil
                    }
                }
            }
        }
    }

    @discardableResult
    private func startMonitor() -> Bool {
        guard Permissions.accessibilityTrusted else { return false }
        return monitor?.start() ?? false
    }
}
