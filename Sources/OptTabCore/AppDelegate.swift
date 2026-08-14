import AppKit
import Foundation

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: HotkeyMonitor?
    private var controller: SwitcherController?
    private var retryTimer: Timer?
    private var statusTimer: Timer?
    private var statusWriter: StatusWriter?

    /// 状態ファイルのハートビート間隔。doctor側の許容(30秒)と対で意味を持つ。
    private static let statusInterval: TimeInterval = 5.0

    public func applicationDidFinishLaunching(_ notification: Notification) {
        startStatusHeartbeat()

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

    /// 自分の権限状態を実行ファイルの隣の status.json に書き続ける。
    /// opttab doctor はこれを読む。
    private func startStatusHeartbeat() {
        let executablePath = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath().path
        let writer = StatusWriter(
            path: StatusFile.path(forExecutable: executablePath))
        statusWriter = writer

        let publish = { [weak self] in
            guard self != nil else { return }
            let status = StatusWriter.currentStatus(
                executablePath: executablePath, now: Date())
            do {
                try writer.write(status)
            } catch {
                NSLog("status write failed: \(error)")
            }
        }
        publish()
        statusTimer = Timer.scheduledTimer(
            withTimeInterval: Self.statusInterval, repeats: true) { _ in
            publish()
        }
    }

    @discardableResult
    private func startMonitor() -> Bool {
        guard Permissions.accessibilityTrusted else { return false }
        return monitor?.start() ?? false
    }
}
