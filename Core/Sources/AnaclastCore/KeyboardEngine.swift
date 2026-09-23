import Carbon.HIToolbox
import CoreGraphics

public struct KeyEvent: Sendable {
    public enum Kind: Sendable { case keyDown, keyUp, flagsChanged, pointer }

    public let kind: Kind
    public let keyCode: KeyCode
    public let flags: CGEventFlags
    public let isRepeat: Bool
    public let time: Double
    public let hyperSourceHeld: Bool

    public init(kind: Kind, keyCode: KeyCode, flags: CGEventFlags, isRepeat: Bool = false, time: Double, hyperSourceHeld: Bool = true) {
        self.kind = kind
        self.keyCode = keyCode
        self.flags = flags
        self.isRepeat = isRepeat
        self.time = time
        self.hyperSourceHeld = hyperSourceHeld
    }

    var modifiers: Modifiers { Modifiers(flags: flags) }
}

public struct Rewrite: Equatable, Sendable {
    public let keyCode: KeyCode
    public let flags: CGEventFlags
}

public struct Resolution: Equatable, Sendable {
    public let swallow: Bool
    public let actions: [Action]
    public let rewrite: Rewrite?

    init(swallow: Bool, actions: [Action], rewrite: Rewrite? = nil) {
        self.swallow = swallow
        self.actions = actions
        self.rewrite = rewrite
    }

    public static let pass = Resolution(swallow: false, actions: [])
    public static let swallow = Resolution(swallow: true, actions: [])
    static func run(_ action: Action) -> Resolution { Resolution(swallow: true, actions: [action]) }
}

public struct Keymap: Sendable {
    struct ScopedAction: Sendable {
        let app: String?
        let action: Action
    }

    let hyperSource: KeyCode
    let hyperTap: Action
    let hyperTapTimeout: Double
    let hyperKeys: [KeyCode: Action]
    let commandTaps: [KeyCode: Action]
    let commandTapTimeout: Double
    let shortcuts: [KeyChord: [ScopedAction]]
    let remaps: [KeyCode: KeyChord]
    let functionRemaps: [KeyCode: KeyChord]

    public init(config: Config, hyperSource: KeyCode = .f18) throws(ConfigError) {
        try config.validate()
        self.hyperSource = hyperSource
        hyperTap = config.hyper.tap
        hyperTapTimeout = Double(config.hyper.tapTimeoutMilliseconds) / 1000
        var hyperKeys: [KeyCode: Action] = [:]
        for (name, action) in config.hyper.keys {
            guard let code = KeyCode(name: name) else { throw .invalid("hyper.keys has unknown key \"\(name)\"") }
            hyperKeys[code] = action
        }
        self.hyperKeys = hyperKeys
        var commandTaps: [KeyCode: Action] = [:]
        commandTaps[.leftCommand] = config.modifierTaps.leftCommand
        commandTaps[.rightCommand] = config.modifierTaps.rightCommand
        self.commandTaps = commandTaps
        commandTapTimeout = Double(config.modifierTaps.timeoutMilliseconds) / 1000
        var shortcuts: [KeyChord: [ScopedAction]] = [:]
        for shortcut in config.shortcuts {
            let chord = try KeyChord(parsing: shortcut.chord)
            shortcuts[chord, default: []].append(ScopedAction(app: shortcut.app, action: shortcut.action))
        }
        self.shortcuts = shortcuts
        var remaps: [KeyCode: KeyChord] = [:]
        var functionRemaps: [KeyCode: KeyChord] = [:]
        for remap in config.remaps {
            let from = try KeyChord(parsing: remap.from)
            let to = try KeyChord(parsing: remap.to)
            if from.modifiers.contains(.function) {
                functionRemaps[from.key] = to
            } else {
                remaps[from.key] = to
            }
        }
        self.remaps = remaps
        self.functionRemaps = functionRemaps
    }

    public var hyperBindings: [(KeyCode, Action)] { hyperKeys.map { ($0.key, $0.value) } }
    public var shortcutBindings: [(KeyChord, String?, Action)] {
        shortcuts.flatMap { chord, scoped in scoped.map { (chord, $0.app, $0.action) } }
    }
}

public struct KeyboardEngine: Sendable {
    public private(set) var keymap: Keymap
    private var hyperHeld = false
    private var hyperDownAt = 0.0
    private var hyperUsed = false
    private var functionHeld = false
    private var commandTap: (key: KeyCode, at: Double)?
    private var swallowedKeys: Set<KeyCode> = []
    private var rewrittenKeys: [KeyCode: KeyChord] = [:]

    static let deviceCommandMask: [KeyCode: UInt64] = [.leftCommand: 0x08, .rightCommand: 0x10]
    static let functionKey = KeyCode(kVK_Function)

    public init(keymap: Keymap) {
        self.keymap = keymap
    }

    public mutating func replace(keymap: Keymap) {
        self.keymap = keymap
        reset()
    }

    public mutating func reset() {
        hyperHeld = false
        hyperUsed = false
        functionHeld = false
        commandTap = nil
        swallowedKeys = []
        rewrittenKeys = [:]
    }

    public mutating func handle(_ event: KeyEvent, frontmostApp: String?) -> Resolution {
        switch event.kind {
        case .pointer:
            commandTap = nil
            if hyperHeld { hyperUsed = true }
            return .pass
        case .flagsChanged:
            return flagsChanged(event)
        case .keyDown:
            return keyDown(event, frontmostApp: frontmostApp)
        case .keyUp:
            return keyUp(event)
        }
    }

    private mutating func flagsChanged(_ event: KeyEvent) -> Resolution {
        if hyperHeld { hyperUsed = true }
        if event.keyCode == Self.functionKey {
            functionHeld = event.flags.contains(.maskSecondaryFn)
        }
        guard let mask = Self.deviceCommandMask[event.keyCode] else {
            commandTap = nil
            return .pass
        }
        let isDown = event.flags.rawValue & mask != 0
        if isDown {
            commandTap = (event.keyCode, event.time)
            return .pass
        }
        defer { commandTap = nil }
        guard let tap = commandTap, tap.key == event.keyCode, event.time - tap.at < keymap.commandTapTimeout,
              let action = keymap.commandTaps[event.keyCode] else {
            return .pass
        }
        return Resolution(swallow: false, actions: [action])
    }

    private mutating func keyDown(_ event: KeyEvent, frontmostApp: String?) -> Resolution {
        commandTap = nil
        if event.keyCode == keymap.hyperSource {
            if !event.isRepeat {
                hyperHeld = true
                hyperDownAt = event.time
                hyperUsed = false
            }
            return .swallow
        }
        if event.isRepeat {
            if swallowedKeys.contains(event.keyCode) { return .swallow }
            if let target = rewrittenKeys[event.keyCode] { return rewrite(event, to: target) }
            if hyperHeld { hyperUsed = true }
            return .pass
        }
        swallowedKeys.remove(event.keyCode)
        rewrittenKeys.removeValue(forKey: event.keyCode)
        if hyperHeld && !event.hyperSourceHeld {
            hyperHeld = false
        }
        if hyperHeld {
            hyperUsed = true
            if let action = keymap.hyperKeys[event.keyCode] {
                swallowedKeys.insert(event.keyCode)
                return .run(action)
            }
        }
        if let target = functionHeld ? keymap.functionRemaps[event.keyCode] : keymap.remaps[event.keyCode] {
            rewrittenKeys[event.keyCode] = target
            return rewrite(event, to: target)
        }
        if hyperHeld {
            return .pass
        }
        if let action = shortcutAction(event, frontmostApp: frontmostApp) {
            swallowedKeys.insert(event.keyCode)
            return .run(action)
        }
        return .pass
    }

    private mutating func keyUp(_ event: KeyEvent) -> Resolution {
        if event.keyCode == keymap.hyperSource {
            defer { hyperHeld = false }
            if hyperHeld, !hyperUsed, event.time - hyperDownAt < keymap.hyperTapTimeout {
                return .run(keymap.hyperTap)
            }
            return .swallow
        }
        if swallowedKeys.remove(event.keyCode) != nil {
            return .swallow
        }
        if let target = rewrittenKeys.removeValue(forKey: event.keyCode) {
            return rewrite(event, to: target)
        }
        return .pass
    }

    private func rewrite(_ event: KeyEvent, to target: KeyChord) -> Resolution {
        let flags = event.flags.subtracting(.maskSecondaryFn).union(target.modifiers.flags)
        return Resolution(swallow: false, actions: [], rewrite: Rewrite(keyCode: target.key, flags: flags))
    }

    private func shortcutAction(_ event: KeyEvent, frontmostApp: String?) -> Action? {
        let modifiers = event.modifiers
        let exact = KeyChord(key: event.keyCode, modifiers: modifiers)
        let withoutFunction = KeyChord(key: event.keyCode, modifiers: modifiers.subtracting(.function))
        guard let candidates = keymap.shortcuts[exact] ?? keymap.shortcuts[withoutFunction] else { return nil }
        if let scoped = candidates.first(where: { $0.app != nil && $0.app == frontmostApp }) {
            return scoped.action
        }
        return candidates.first(where: { $0.app == nil })?.action
    }
}
