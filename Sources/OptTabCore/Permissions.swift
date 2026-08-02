import AppKit
import ApplicationServices
import CoreGraphics

public enum Permissions {
    public static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// システムのアクセシビリティ許可ダイアログを出す
    public static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public static var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    public static func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    public static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    public static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private static func open(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
