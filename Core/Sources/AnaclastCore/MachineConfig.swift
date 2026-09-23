import Foundation

public struct MachineConfig: Sendable {
    public struct Homebrew: Decodable, Sendable {
        public struct Keep: Decodable, Sendable {
            public let brews: [String]
            public let casks: [String]
        }

        public let taps: [String]
        public let brews: [Brew]
        public let casks: [String]
        public let mas: [String: Int]
        public let keep: Keep
        public let cleanup: Bool
    }

    public struct Brew: Decodable, Sendable, Hashable {
        public enum RestartPolicy: String, Decodable, Sendable { case changed, always }

        public let name: String
        public let startService: Bool
        public let restartService: RestartPolicy?

        private enum Keys: String, CodingKey { case name, startService, restartService }

        public init(from decoder: any Decoder) throws {
            if let name = try? decoder.singleValueContainer().decode(String.self) {
                self.name = name
                startService = false
                restartService = nil
                return
            }
            let container = try decoder.container(keyedBy: Keys.self)
            name = try container.decode(String.self, forKey: .name)
            startService = try container.decodeIfPresent(Bool.self, forKey: .startService) ?? false
            restartService = try container.decodeIfPresent(RestartPolicy.self, forKey: .restartService)
        }
    }

    public struct Preference: @unchecked Sendable {
        public let domain: String
        public let key: String
        public let currentHost: Bool
        public let value: Any
    }

    public struct Link: Decodable, Sendable, Hashable {
        public let source: String
        public let target: String
    }

    public struct Clone: Decodable, Sendable, Hashable {
        public let url: String
        public let path: String
    }

    public struct Download: Decodable, Sendable, Hashable {
        public enum Format: String, Decodable, Sendable { case tarGz = "tar.gz", zip }

        public struct Install: Decodable, Sendable, Hashable {
            public let from: String
            public let to: String
            public let pathExtension: String?
            public let executable: Bool?
        }

        public let name: String
        public let url: String
        public let format: Format
        public let install: [Install]
    }

    public struct Host: Decodable, Sendable {
        public let computerName: String?
        public let hostName: String?
        public let localHostName: String?
        public let brews: [Brew]?
        public let casks: [String]?
        public let env: [String: String]?
        public let authorizedKeys: [String]?
    }

    public struct HostView: Sendable, Equatable {
        public let key: String?
        public let brews: [Brew]
        public let casks: [String]
        public let env: [String: String]
        public let authorizedKeys: [String]?
        public let names: [HostNameKind: String]
    }

    public enum HostNameKind: String, CaseIterable, Sendable {
        case computerName = "ComputerName"
        case hostName = "HostName"
        case localHostName = "LocalHostName"
    }

    public let homebrew: Homebrew
    public let preferences: [Preference]
    public let restart: [String: String]
    public let links: [Link]
    public let clones: [Clone]
    public let downloads: [Download]
    public let bunGlobals: [String]
    public let sudoLocal: String?
    public let remoteLogin: Bool
    public let hosts: [String: Host]

    public static let homeToken = "${HOME}"
    public static let globalDomain = "NSGlobalDomain"
    public static let defaultHost = "default"

    public static func load(from url: URL, home: String = NSHomeDirectory()) throws -> MachineConfig {
        try decode(Data(contentsOf: url), home: home)
    }

    static func decode(_ data: Data, home: String) throws -> MachineConfig {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError.invalid("machine config must be a JSON object")
        }
        try check(root, against: schema, at: "")
        guard let expanded = expandingHome(in: root, home: home) as? [String: Any] else {
            throw ConfigError.invalid("machine config must be a JSON object")
        }
        let document = try JSONDecoder().decode(Document.self, from: JSONSerialization.data(withJSONObject: expanded))
        let values = expanded["preferences"] as? [[String: Any]] ?? []
        var preferences: [Preference] = []
        for (index, (entry, raw)) in zip(document.preferences, values).enumerated() {
            guard let value = raw["value"] else { throw ConfigError.invalid("preferences[\(index)].value is required") }
            guard !containsNull(value) else { throw ConfigError.invalid("preferences[\(index)].value must not contain null") }
            preferences.append(Preference(domain: entry.domain, key: entry.key, currentHost: entry.currentHost ?? false, value: value))
        }
        let config = MachineConfig(
            homebrew: document.homebrew,
            preferences: preferences,
            restart: document.restart,
            links: document.links.map { Link(source: $0.source, target: expandingTilde($0.target, home: home)) },
            clones: document.clones.map { Clone(url: $0.url, path: expandingTilde($0.path, home: home)) },
            downloads: document.downloads.map { download in
                Download(name: download.name, url: download.url, format: download.format, install: download.install.map {
                    Download.Install(from: $0.from, to: expandingTilde($0.to, home: home), pathExtension: $0.pathExtension, executable: $0.executable)
                })
            },
            bunGlobals: document.bunGlobals,
            sudoLocal: document.sudoLocal,
            remoteLogin: document.remoteLogin,
            hosts: document.hosts
        )
        try config.validate()
        return config
    }

    public func host(named localHostName: String?) -> HostView {
        let key = [localHostName, Self.defaultHost].compactMap { $0 }.first { hosts[$0] != nil }
        let host = key.flatMap { hosts[$0] }
        var brewNames = Set<String>()
        var caskNames = Set<String>()
        var names: [HostNameKind: String] = [:]
        names[.computerName] = host?.computerName
        names[.hostName] = host?.hostName
        names[.localHostName] = host?.localHostName
        return HostView(
            key: key,
            brews: (homebrew.brews + (host?.brews ?? [])).filter { brewNames.insert($0.name).inserted },
            casks: (homebrew.casks + (host?.casks ?? [])).filter { caskNames.insert($0).inserted },
            env: host?.env ?? [:],
            authorizedKeys: host?.authorizedKeys,
            names: names
        )
    }

    func validate() throws(ConfigError) {
        for (index, link) in links.enumerated() where link.source.hasPrefix("/") {
            throw .invalid("links[\(index)].source must be relative to the config directory")
        }
        var paths = links.enumerated().map { ("links[\($0)].target", $1.target) }
        paths += clones.enumerated().map { ("clones[\($0)].path", $1.path) }
        for (index, download) in downloads.enumerated() {
            guard !download.install.isEmpty else { throw .invalid("downloads[\(index)].install must not be empty") }
            paths += download.install.enumerated().map { ("downloads[\(index)].install[\($0)].to", $1.to) }
        }
        for (field, path) in paths where !path.hasPrefix("/") {
            throw .invalid("\(field) must be absolute or start with ~/ or \(Self.homeToken)")
        }
        for (name, host) in hosts {
            for key in (host.env ?? [:]).keys where !Self.isShellName(key) {
                throw .invalid("hosts.\(name).env: \"\(key)\" is not a shell variable name")
            }
        }
    }

    static func isShellName(_ name: String) -> Bool {
        guard let first = name.first, first == "_" || (first.isASCII && first.isLetter) else { return false }
        return name.allSatisfy { $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }

    private static func expandingHome(in value: Any, home: String) -> Any {
        switch value {
        case let string as String: string.replacing(homeToken, with: home)
        case let array as [Any]: array.map { expandingHome(in: $0, home: home) }
        case let object as [String: Any]: object.mapValues { expandingHome(in: $0, home: home) }
        default: value
        }
    }

    private static func expandingTilde(_ path: String, home: String) -> String {
        path.hasPrefix("~/") ? home + path.dropFirst() : path
    }

    private static func containsNull(_ value: Any) -> Bool {
        switch value {
        case is NSNull: true
        case let array as [Any]: array.contains(where: containsNull)
        case let object as [String: Any]: object.values.contains(where: containsNull)
        default: false
        }
    }

    private struct Document: Decodable {
        struct PreferenceEntry: Decodable {
            let domain: String
            let key: String
            let currentHost: Bool?
        }

        let homebrew: Homebrew
        let preferences: [PreferenceEntry]
        let restart: [String: String]
        let links: [Link]
        let clones: [Clone]
        let downloads: [Download]
        let bunGlobals: [String]
        let sudoLocal: String?
        let remoteLogin: Bool
        let hosts: [String: Host]
    }

    private indirect enum Schema: Sendable {
        case object([String: Schema])
        case list(Schema)
        case map(Schema)
        case brew
        case name
        case any
    }

    private static let brewSchema: Schema = .object(["name": .name, "startService": .any, "restartService": .any])

    private static let schema: Schema = .object([
        "homebrew": .object([
            "taps": .list(.name),
            "brews": .list(.brew),
            "casks": .list(.name),
            "mas": .map(.any),
            "keep": .object(["brews": .list(.name), "casks": .list(.name)]),
            "cleanup": .any,
        ]),
        "preferences": .list(.object(["domain": .name, "key": .name, "currentHost": .any, "value": .any])),
        "restart": .map(.name),
        "links": .list(.object(["source": .name, "target": .name])),
        "clones": .list(.object(["url": .name, "path": .name])),
        "downloads": .list(.object([
            "name": .name,
            "url": .name,
            "format": .any,
            "install": .list(.object(["from": .name, "to": .name, "pathExtension": .name, "executable": .any])),
        ])),
        "bunGlobals": .list(.name),
        "sudoLocal": .name,
        "remoteLogin": .any,
        "hosts": .map(.object([
            "computerName": .name,
            "hostName": .name,
            "localHostName": .name,
            "brews": .list(.brew),
            "casks": .list(.name),
            "env": .map(.any),
            "authorizedKeys": .list(.name),
        ])),
    ])

    private static func check(_ value: Any, against schema: Schema, at path: String) throws(ConfigError) {
        switch schema {
        case .any:
            return
        case .name:
            if let name = value as? String, name.isEmpty { throw .invalid("\(path) must not be empty") }
        case .brew:
            try check(value, against: value is String ? .name : brewSchema, at: path)
        case .list(let element):
            guard let array = value as? [Any] else { return }
            for (index, item) in array.enumerated() {
                try check(item, against: element, at: "\(path)[\(index)]")
            }
        case .map(let element):
            guard let object = value as? [String: Any] else { return }
            for (key, item) in object.sorted(by: { $0.key < $1.key }) {
                guard !key.isEmpty else { throw .invalid("\(path) has an empty name") }
                try check(item, against: element, at: "\(path).\(key)")
            }
        case .object(let fields):
            guard let object = value as? [String: Any] else { return }
            for (key, item) in object.sorted(by: { $0.key < $1.key }) {
                guard let field = fields[key] else {
                    throw .invalid("unknown key \"\(key)\" in \(path.isEmpty ? "the top level" : path)")
                }
                try check(item, against: field, at: path.isEmpty ? key : "\(path).\(key)")
            }
        }
    }
}
