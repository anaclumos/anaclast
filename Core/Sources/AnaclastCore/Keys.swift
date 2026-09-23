import Carbon.HIToolbox
import CoreGraphics

public struct Modifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let command = Modifiers(rawValue: 1 << 0)
    public static let shift = Modifiers(rawValue: 1 << 1)
    public static let control = Modifiers(rawValue: 1 << 2)
    public static let option = Modifiers(rawValue: 1 << 3)
    public static let function = Modifiers(rawValue: 1 << 4)

    public static let hyper: Modifiers = [.command, .shift, .control, .option]

    public init(flags: CGEventFlags) {
        var value: Modifiers = []
        if flags.contains(.maskCommand) { value.insert(.command) }
        if flags.contains(.maskShift) { value.insert(.shift) }
        if flags.contains(.maskControl) { value.insert(.control) }
        if flags.contains(.maskAlternate) { value.insert(.option) }
        if flags.contains(.maskSecondaryFn) { value.insert(.function) }
        self = value
    }

    public var flags: CGEventFlags {
        var value: CGEventFlags = []
        if contains(.command) { value.insert(.maskCommand) }
        if contains(.shift) { value.insert(.maskShift) }
        if contains(.control) { value.insert(.maskControl) }
        if contains(.option) { value.insert(.maskAlternate) }
        if contains(.function) { value.insert(.maskSecondaryFn) }
        return value
    }

    static let names: [String: Modifiers] = [
        "cmd": .command, "command": .command,
        "shift": .shift,
        "ctrl": .control, "control": .control,
        "alt": .option, "opt": .option, "option": .option,
        "fn": .function,
        "hyper": .hyper,
    ]
}

public struct KeyCode: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt16
    public init(_ rawValue: UInt16) { self.rawValue = rawValue }
    init(_ carbon: Int) { rawValue = UInt16(carbon) }

    public static let f18 = KeyCode(kVK_F18)
    public static let capsLock = KeyCode(kVK_CapsLock)
    public static let leftCommand = KeyCode(kVK_Command)
    public static let rightCommand = KeyCode(kVK_RightCommand)
    public static let v = KeyCode(kVK_ANSI_V)

    public init?(name: String) {
        guard let code = Self.byName[name.lowercased()] else { return nil }
        self = code
    }

    public var description: String {
        Self.canonical.first { $0.value == self }?.key ?? "keycode \(rawValue)"
    }

    public var isHyperSource: Bool { self == .f18 || self == .capsLock }

    public static let names = canonical.keys.sorted()

    static let byName = canonical.merging(["esc": KeyCode(kVK_Escape)]) { canonical, _ in canonical }

    private static let canonical: [String: KeyCode] = {
        var table: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
            "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
            "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
            "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
            "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "grave": kVK_ANSI_Grave, "minus": kVK_ANSI_Minus, "equal": kVK_ANSI_Equal,
            "leftbracket": kVK_ANSI_LeftBracket, "rightbracket": kVK_ANSI_RightBracket,
            "backslash": kVK_ANSI_Backslash, "semicolon": kVK_ANSI_Semicolon, "quote": kVK_ANSI_Quote,
            "comma": kVK_ANSI_Comma, "period": kVK_ANSI_Period, "slash": kVK_ANSI_Slash,
            "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
            "return": kVK_Return, "enter": kVK_ANSI_KeypadEnter, "tab": kVK_Tab, "space": kVK_Space,
            "delete": kVK_Delete, "forwarddelete": kVK_ForwardDelete, "escape": kVK_Escape,
            "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
            "capslock": kVK_CapsLock,
            "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
            "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
            "f13": kVK_F13, "f14": kVK_F14, "f15": kVK_F15, "f16": kVK_F16, "f17": kVK_F17,
            "f18": kVK_F18, "f19": kVK_F19, "f20": kVK_F20,
        ]
        table["dictation"] = 0xB0
        table["spotlight"] = 0xB1
        table["donotdisturb"] = 0xB2
        table["globe"] = 0xB3
        return table.mapValues(KeyCode.init)
    }()
}

public struct KeyChord: Hashable, Sendable, CustomStringConvertible {
    public let key: KeyCode
    public let modifiers: Modifiers

    public init(key: KeyCode, modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    public init(parsing text: String) throws(ConfigError) {
        let parts = text.lowercased().split(separator: "+").map(String.init)
        guard let keyName = parts.last, let key = KeyCode(name: keyName) else {
            throw .invalid("unknown key in chord \"\(text)\"")
        }
        var modifiers: Modifiers = []
        for name in parts.dropLast() {
            guard let modifier = Modifiers.names[name] else {
                throw .invalid("unknown modifier \"\(name)\" in chord \"\(text)\"")
            }
            modifiers.formUnion(modifier)
        }
        self.init(key: key, modifiers: modifiers)
    }

    public var description: String {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"), (.function, "fn ")]
        let prefix = modifiers == .hyper ? "Hyper " : symbols.filter { modifiers.contains($0.0) }.map(\.1).joined()
        return prefix + key.description.capitalized
    }

    public var configText: String {
        let names: [(Modifiers, String)] = [(.control, "ctrl"), (.option, "alt"), (.shift, "shift"), (.command, "cmd"), (.function, "fn")]
        let spelled = modifiers.isSuperset(of: .hyper) ? [(Modifiers.hyper, "hyper"), (.function, "fn")] : names
        return (spelled.filter { modifiers.contains($0.0) }.map(\.1) + [key.description]).joined(separator: "+")
    }
}
