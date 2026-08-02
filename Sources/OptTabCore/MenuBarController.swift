import AppKit
import ServiceManagement

@MainActor
public final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!

    public override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.on.rectangle",
            accessibilityDescription: "OptTab")

        let menu = NSMenu()
        let loginItem = NSMenuItem(title: "ログイン時に起動",
                                   action: #selector(toggleLaunchAtLogin),
                                   keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        let permItem = NSMenuItem(title: "権限を確認…",
                                  action: #selector(checkPermissions),
                                  keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "OptTabを終了",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("SMAppService error: \(error)")
        }
    }

    @objc private func checkPermissions() {
        if !Permissions.accessibilityTrusted {
            Permissions.openAccessibilitySettings()
        }
        if !Permissions.screenRecordingGranted {
            Permissions.openScreenRecordingSettings()
        }
        if Permissions.accessibilityTrusted && Permissions.screenRecordingGranted {
            let alert = NSAlert()
            alert.messageText = "権限OK"
            alert.informativeText = "アクセシビリティと画面収録は許可済み。"
            alert.runModal()
        }
    }
}

extension MenuBarController: NSMenuDelegate {
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.first?.state =
            SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
