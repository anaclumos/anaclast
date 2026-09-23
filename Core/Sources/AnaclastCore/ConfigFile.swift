import Foundation

public enum ConfigFile {
    @discardableResult
    public static func update(at url: URL, _ change: (inout Config) throws -> Void) throws -> Config {
        var config = try Config.load(from: url, validating: false)
        try change(&config)
        try config.validate()
        _ = try Keymap(config: config)
        try write(config, to: url)
        return config
    }

    public static func write(_ config: Config, to url: URL) throws {
        try (config.encoded() + Data("\n".utf8)).write(to: url.resolvingSymlinksInPath(), options: .atomic)
    }
}

extension Config {
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func value(at path: String) throws -> Data {
        var node = try JSONSerialization.jsonObject(with: encoded())
        for key in Self.components(path) {
            guard let object = node as? [String: Any], let child = object[key] else {
                throw ConfigError.invalid("unknown setting \"\(path)\"")
            }
            node = child
        }
        return try JSONSerialization.data(withJSONObject: node, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
    }

    public func setting(_ path: String, to json: Data?) throws -> Config {
        let keys = Self.components(path)
        guard !keys.isEmpty else { throw ConfigError.invalid("a setting path is required") }
        let value = try json.map { try JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed) }.flatMap { $0 is NSNull ? nil : $0 }
        if value == nil, (try? self.value(at: path)) == nil {
            throw ConfigError.invalid("\(path) is not set")
        }
        let root = try Self.replacing(JSONSerialization.jsonObject(with: encoded()), keys: keys[...], with: value, path: path)
        let changed = try JSONDecoder().decode(Config.self, from: JSONSerialization.data(withJSONObject: root))
        try changed.rejectUnknownKeys(in: root)
        return changed
    }

    func rejectUnknownKeys(in source: Any) throws {
        if let path = Self.unknownKey(in: source, known: try JSONSerialization.jsonObject(with: encoded()), path: []) {
            throw ConfigError.invalid("unknown setting \"\(path)\"")
        }
    }

    private static func unknownKey(in source: Any, known: Any, path: [String]) -> String? {
        if let object = source as? [String: Any] {
            let knownObject = known as? [String: Any] ?? [:]
            for (key, value) in object.sorted(by: { $0.key < $1.key }) where !(value is NSNull) {
                guard let match = knownObject[key] else { return (path + [key]).joined(separator: ".") }
                if let found = unknownKey(in: value, known: match, path: path + [key]) { return found }
            }
        } else if let array = source as? [Any], let knownArray = known as? [Any] {
            for (index, (value, match)) in zip(array, knownArray).enumerated() {
                if let found = unknownKey(in: value, known: match, path: path + [String(index)]) { return found }
            }
        }
        return nil
    }

    private static func components(_ path: String) -> [String] {
        path.split(separator: ".").map(String.init)
    }

    private static func replacing(_ node: Any, keys: ArraySlice<String>, with value: Any?, path: String) throws -> Any {
        guard let key = keys.first, var object = node as? [String: Any] else {
            throw ConfigError.invalid("unknown setting \"\(path)\"")
        }
        if keys.count == 1 {
            object[key] = value
        } else {
            guard let child = object[key] else { throw ConfigError.invalid("unknown setting \"\(path)\"") }
            object[key] = try replacing(child, keys: keys.dropFirst(), with: value, path: path)
        }
        return object
    }
}
