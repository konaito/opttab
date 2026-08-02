import AppKit
import CoreGraphics

@MainActor
public protocol HotkeyMonitorDelegate: AnyObject {
    var isSessionActive: Bool { get }
    func handle(_ action: HotkeyAction)
}

public final class HotkeyMonitor {
    public weak var delegate: (any HotkeyMonitorDelegate)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public init() {}

    deinit {
        stop()
    }

    /// tap作成に失敗（アクセシビリティ未許可）ならfalse
    public func start() -> Bool {
        guard eventTap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>
                .fromOpaque(refcon).takeUnretainedValue()
            return monitor.process(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func process(type: CGEventType,
                         event: CGEvent) -> Unmanaged<CGEvent>? {
        // OSによる無効化からの復帰
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let optionDown = flags.contains(.maskAlternate)
        // tapはメインrunloopに載せているのでここはメインスレッド
        let action = MainActor.assumeIsolated { () -> HotkeyAction in
            let active = delegate?.isSessionActive ?? false
            switch type {
            case .keyDown:
                return HotkeyInterpreter.actionForKeyDown(
                    keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                    optionDown: optionDown,
                    shiftDown: flags.contains(.maskShift),
                    commandDown: flags.contains(.maskCommand),
                    controlDown: flags.contains(.maskControl),
                    sessionActive: active)
            case .flagsChanged:
                return HotkeyInterpreter.actionForFlagsChanged(
                    optionDown: optionDown, sessionActive: active)
            default:
                return .passthrough
            }
        }

        if action == .passthrough { return Unmanaged.passUnretained(event) }
        MainActor.assumeIsolated { delegate?.handle(action) }
        if action == .commit { return Unmanaged.passUnretained(event) }  // 修飾キー解放はシステムにも流す
        return nil  // 消費（システムに流さない）
    }
}
