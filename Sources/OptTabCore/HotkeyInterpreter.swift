public enum HotkeyAction: Equatable, Sendable {
    case activate(reverse: Bool)
    case cycle(reverse: Bool)
    case commit
    case cancel
    case passthrough
}

public enum HotkeyInterpreter {
    public static let tabKeyCode: Int64 = 48
    public static let escKeyCode: Int64 = 53

    public static func actionForKeyDown(keyCode: Int64, optionDown: Bool,
                                        shiftDown: Bool, commandDown: Bool,
                                        controlDown: Bool,
                                        sessionActive: Bool) -> HotkeyAction {
        if sessionActive {
            switch keyCode {
            case tabKeyCode: return .cycle(reverse: shiftDown)
            case escKeyCode: return .cancel
            default: return .passthrough
            }
        }
        guard keyCode == tabKeyCode, optionDown, !commandDown, !controlDown else {
            return .passthrough
        }
        return .activate(reverse: shiftDown)
    }

    public static func actionForFlagsChanged(optionDown: Bool,
                                             sessionActive: Bool) -> HotkeyAction {
        if sessionActive && !optionDown { return .commit }
        return .passthrough
    }
}
