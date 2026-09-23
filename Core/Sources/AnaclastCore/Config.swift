import Foundation

public enum ConfigError: Error, Equatable, CustomStringConvertible {
    case invalid(String)

    public var description: String {
        switch self {
        case .invalid(let message): message
        }
    }
}

public enum Command: String, CaseIterable, Sendable, Codable {
    case launcher
    case openSettings
    case clipboardHistory
    case toggleDarkMode
    case lockScreen
    case showDesktop
    case missionControl
    case toggleCapsLock
    case openDefaultBrowser
    case cursorAgents
    case cursorIDE
    case applyMachineConfig
    case reloadConfig
    case quit
}

public enum Action: Hashable, Sendable {
    case open(bundleID: String)
    case tile(String)
    case inputSource(String)
    case keystroke(KeyChord)
    case menu([String])
    case command(Command)
}

struct DynamicKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension Action: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "an action is an object with exactly one key"))
        }
        switch key.stringValue {
        case "open": self = .open(bundleID: try container.decode(String.self, forKey: key))
        case "tile": self = .tile(try container.decode(String.self, forKey: key))
        case "inputSource": self = .inputSource(try container.decode(String.self, forKey: key))
        case "menu": self = .menu(try container.decode([String].self, forKey: key))
        case "command": self = .command(try container.decode(Command.self, forKey: key))
        case "keystroke":
            let text = try container.decode(String.self, forKey: key)
            do {
                self = .keystroke(try KeyChord(parsing: text))
            } catch {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: error.description)
            }
        default:
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "unknown action \"\(key.stringValue)\"")
        }
    }
}

extension Action: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        switch self {
        case .open(let bundleID): try container.encode(bundleID, forKey: DynamicKey(stringValue: "open"))
        case .tile(let name): try container.encode(name, forKey: DynamicKey(stringValue: "tile"))
        case .inputSource(let id): try container.encode(id, forKey: DynamicKey(stringValue: "inputSource"))
        case .menu(let path): try container.encode(path, forKey: DynamicKey(stringValue: "menu"))
        case .command(let command): try container.encode(command, forKey: DynamicKey(stringValue: "command"))
        case .keystroke(let chord): try container.encode(chord.configText, forKey: DynamicKey(stringValue: "keystroke"))
        }
    }
}

public struct TileFrame: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

public struct Shortcut: Codable, Hashable, Sendable {
    public let chord: String
    public let app: String?
    public let action: Action
}

public struct Remap: Codable, Hashable, Sendable {
    public let from: String
    public let to: String
}

public struct Config: Codable, Hashable, Sendable {
    public struct Hyper: Codable, Hashable, Sendable {
        public var tap: Action
        public var tapTimeoutMilliseconds: Int
        public var keys: [String: Action]
    }

    public struct ModifierTaps: Codable, Hashable, Sendable {
        public var timeoutMilliseconds: Int
        public var leftCommand: Action?
        public var rightCommand: Action?
    }

    public struct Clipboard: Codable, Hashable, Sendable {
        public var limit: Int?

        // Writes null instead of dropping the key, so a config that keeps all history still names the setting.
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(limit, forKey: .limit)
        }
    }

    public var tiles: [String: TileFrame]
    public var hyper: Hyper
    public var modifierTaps: ModifierTaps
    public var shortcuts: [Shortcut]
    public var remaps: [Remap]
    public var disabledSymbolicHotkeys: [Int]
    public var clipboard: Clipboard

    public static let fullscreenTile = "fullscreen"
    public static let hyperKeyNames = KeyCode.names.filter { KeyCode(name: $0)?.isHyperSource == false }

    public static func load(from url: URL, validating: Bool = true) throws -> Config {
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(Config.self, from: data)
        try config.rejectUnknownKeys(in: JSONSerialization.jsonObject(with: data))
        if validating { try config.validate() }
        return config
    }

    public func validate() throws(ConfigError) {
        guard tiles[Self.fullscreenTile] == nil else {
            throw .invalid("the tile name \"\(Self.fullscreenTile)\" is reserved for toggling full screen")
        }
        for (name, tile) in tiles {
            let values = [tile.x, tile.y, tile.w, tile.h]
            guard values.allSatisfy({ (0...1).contains($0) }), tile.w > 0, tile.h > 0, tile.x + tile.w <= 1.0001, tile.y + tile.h <= 1.0001 else {
                throw .invalid("tile \"\(name)\" must be fractions of the screen inside 0...1")
            }
        }
        guard hyper.tapTimeoutMilliseconds > 0, modifierTaps.timeoutMilliseconds > 0 else {
            throw .invalid("tap timeouts must be positive")
        }
        if let limit = clipboard.limit, limit <= 0 { throw .invalid("clipboard.limit must be positive, or left out to keep all history") }
        var bound = Set<KeyCode>()
        for name in hyper.keys.keys.sorted() {
            guard let key = KeyCode(name: name) else { throw .invalid("hyper.keys has unknown key \"\(name)\"") }
            guard !key.isHyperSource else { throw .invalid("hyper.keys cannot bind \(key), which is the Hyper key itself") }
            guard bound.insert(key).inserted else { throw .invalid("hyper.keys binds \(key) under two names") }
        }
        var remapped = Set<KeyChord>()
        for remap in remaps {
            let from = try KeyChord(parsing: remap.from)
            guard from.modifiers == [] || from.modifiers == .function else {
                throw .invalid("remap \"\(remap.from)\" may only require fn")
            }
            guard remapped.insert(from).inserted else { throw .invalid("\"\(remap.from)\" is remapped twice") }
            _ = try KeyChord(parsing: remap.to)
        }
        for shortcut in shortcuts {
            _ = try KeyChord(parsing: shortcut.chord)
        }
        var actions = [hyper.tap] + Array(hyper.keys.values) + shortcuts.map(\.action)
        actions += [modifierTaps.leftCommand, modifierTaps.rightCommand].compactMap { $0 }
        for action in actions {
            if case .tile(let name) = action, name != Self.fullscreenTile, tiles[name] == nil {
                throw .invalid("action refers to unknown tile \"\(name)\"")
            }
            if case .menu(let path) = action, path.count < 2 {
                throw .invalid("a menu action needs at least a menu and an item")
            }
        }
    }
}
