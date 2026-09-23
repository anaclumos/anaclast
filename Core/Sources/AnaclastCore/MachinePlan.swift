import Foundation

public struct CommandOutput: Sendable, Equatable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct MachineError: LocalizedError, Equatable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }

    public var errorDescription: String? { description }
}

public enum FileState: Hashable, Sendable {
    case missing
    case link(String)
    case file
    case directory
}

public protocol MachineProbe {
    func hostNames() async throws -> [MachineConfig.HostNameKind: String]
    func brewBundle(_ arguments: [String], brewfile: String) async throws -> CommandOutput
    func bunGlobals() async throws -> CommandOutput?
    func launchdDisabledServices() async throws -> CommandOutput
    func preference(domain: String, key: String, currentHost: Bool) -> Any?
    func state(of path: String) -> FileState
    func contents(of path: String) -> String?
}

public struct GeneratedFile: Hashable, Sendable {
    public let path: String
    public let contents: String
    public let mode: Int
    public let directoryMode: Int?

    public static func hostEnvironment(_ env: [String: String], home: String) -> GeneratedFile {
        let lines = env.sorted { $0.key < $1.key }.map { "export \($0.key)=\($0.value.shellQuoted)\n" }
        return GeneratedFile(path: home + "/.config/zsh/host.zsh", contents: lines.joined(), mode: 0o644, directoryMode: nil)
    }

    public static func authorizedKeys(_ keys: [String], home: String) -> GeneratedFile {
        GeneratedFile(path: home + "/.ssh/authorized_keys", contents: keys.map { $0 + "\n" }.joined(), mode: 0o600, directoryMode: 0o700)
    }
}

public enum MachineStep: Sendable, CustomStringConvertible {
    public enum Category: Int, CaseIterable, Comparable, Sendable, CustomStringConvertible {
        case homebrew, clones, downloads, bunGlobals, links, generatedFiles, preferences, restarts, system

        public static func < (lhs: Category, rhs: Category) -> Bool { lhs.rawValue < rhs.rawValue }

        public var description: String {
            switch self {
            case .homebrew: "Homebrew"
            case .clones: "Clones"
            case .downloads: "Downloads"
            case .bunGlobals: "Bun Globals"
            case .links: "Links"
            case .generatedFiles: "Generated Files"
            case .preferences: "Preferences"
            case .restarts: "Restarts"
            case .system: "System (administrator)"
            }
        }
    }

    case brewInstall(String)
    case brewUnchecked(String)
    case brewRemove(heading: String, name: String)
    case clone(url: String, path: String)
    case pull(path: String)
    case download(MachineConfig.Download, existing: [String])
    case bunGlobal(String)
    case link(target: String, destination: String, replacing: FileState)
    case file(GeneratedFile, replacing: FileState)
    case preference(MachineConfig.Preference, live: String)
    case restart(process: String, domains: [String])
    case sudoLocal(String, replacing: Bool, backup: String)
    case hostName(MachineConfig.HostNameKind, from: String?, to: String)
    case remoteLogin

    public var category: Category {
        switch self {
        case .brewInstall, .brewUnchecked, .brewRemove: .homebrew
        case .clone, .pull: .clones
        case .download: .downloads
        case .bunGlobal: .bunGlobals
        case .link: .links
        case .file: .generatedFiles
        case .preference: .preferences
        case .restart: .restarts
        case .sudoLocal, .hostName, .remoteLogin: .system
        }
    }

    public var isDestructive: Bool {
        switch self {
        case .brewRemove: true
        case .download(_, let existing): !existing.isEmpty
        case .link(_, _, let replacing), .file(_, let replacing): replacing != .missing
        case .sudoLocal(_, let replacing, _): replacing
        default: false
        }
    }

    public var removal: Brewfile.Removal? {
        guard case .brewRemove(let heading, let name) = self else { return nil }
        return Brewfile.Removal(heading: heading, name: name)
    }

    public var description: String {
        switch self {
        case .brewInstall(let line): line
        case .brewUnchecked(let reason): "Install the Brewfile; it could not be checked: \(reason)"
        case .brewRemove(let heading, let name): "\(heading.prefix(1).uppercased())\(heading.dropFirst()): \(name)"
        case .clone(let url, let path): "Clone \(url) into \(path)"
        case .pull(let path): "Pull \(path) (fast-forward only)"
        case .download(let download, let existing):
            existing.isEmpty
                ? "Download \(download.name) to \(download.install.map(\.to).joined(separator: ", "))"
                : "Download \(download.name) again, replacing \(existing.joined(separator: ", "))"
        case .bunGlobal(let name): "Install bun global \(name)"
        case .link(let target, let destination, let replacing):
            replacing == .missing
                ? "Link \(target) to \(destination)"
                : "Replace \(target) (\(replacing.summary)) with a link to \(destination)"
        case .file(let file, let replacing):
            replacing == .missing ? "Write \(file.path)" : "Replace \(file.path) (\(replacing.summary))"
        case .preference(let preference, let live):
            "\(preference.domain)\(preference.currentHost ? " (current host)" : "") \(preference.key): \(live) -> \(MachinePlan.render(preference.value))"
        case .restart(let process, let domains): "Restart \(process) for \(domains.joined(separator: ", "))"
        case .sudoLocal(_, let replacing, let backup):
            replacing
                ? "Replace \(RootScript.sudoLocalPath), keeping the old file as \(backup)"
                : "Write \(RootScript.sudoLocalPath)"
        case .hostName(let kind, let from, let to): "Set \(kind.rawValue): \(from ?? "(unset)") -> \(to)"
        case .remoteLogin: "Turn on Remote Login (com.openssh.sshd)"
        }
    }
}

extension FileState {
    var summary: String {
        switch self {
        case .missing: "missing"
        case .link(let destination): "a link to \(destination)"
        case .file: "a file"
        case .directory: "a directory"
        }
    }
}

extension String {
    public var shellQuoted: String {
        "'" + replacing("'", with: #"'\''"#) + "'"
    }
}

public struct Brewfile: Hashable, Sendable {
    public enum Removal: Hashable, Sendable {
        case cask(String)
        case formula(String)
        case tap(String)
        case appStore(id: Int)

        public init?(heading: String, name: String) {
            switch heading {
            case "uninstall casks": self = .cask(name)
            case "uninstall formulae": self = .formula(name)
            case "untap": self = .tap(name)
            case "uninstall Mac App Store apps":
                guard name.hasSuffix(")"), let open = name.lastIndex(of: "("), let id = Int(name[name.index(after: open)...].dropLast()) else { return nil }
                self = .appStore(id: id)
            default: return nil
            }
        }

        public var brewArguments: [String]? {
            switch self {
            case .cask(let name): ["uninstall", "--cask", "--force", name]
            case .formula(let name): ["uninstall", "--formula", "--force", name]
            case .tap(let name): ["untap", name]
            case .appStore: nil
            }
        }
    }

    public let install: String
    public let cleanup: String

    public init(homebrew: MachineConfig.Homebrew, host: MachineConfig.HostView) {
        var lines = homebrew.taps.map { "tap \(Self.quoted($0))" }
        lines += host.brews.map(Self.line)
        lines += host.casks.map { Self.entry("cask", $0) }
        lines += homebrew.mas.sorted { $0.key < $1.key }.map { "mas \(Self.quoted($0.key)), id: \($0.value)" }
        let kept = homebrew.keep.brews.map { Self.entry("brew", $0) } + homebrew.keep.casks.map { Self.entry("cask", $0) }
        install = lines.map { $0 + "\n" }.joined()
        cleanup = (lines + kept).map { $0 + "\n" }.joined()
    }

    static func line(_ brew: MachineConfig.Brew) -> String {
        var line = entry("brew", brew.name)
        if let policy = brew.restartService { line += ", restart_service: :\(policy.rawValue)" }
        if brew.startService { line += ", start_service: true" }
        return line
    }

    static func entry(_ type: String, _ name: String) -> String {
        "\(type) \(quoted(name))" + (name.count { $0 == "/" } == 2 ? ", trusted: true" : "")
    }

    static func quoted(_ value: String) -> String {
        "\"" + value.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"").replacing("#", with: "\\#") + "\""
    }

    public static func missing(fromCheck output: CommandOutput) throws(MachineError) -> [String] {
        guard output.status != 0 else { return [] }
        let missing = output.stderr.split(whereSeparator: \.isNewline).compactMap { $0.hasPrefix("→ ") ? String($0.dropFirst(2)) : nil }
        guard !missing.isEmpty else { throw failure(output, "brew bundle check") }
        return missing
    }

    public static func removals(fromCleanup output: CommandOutput) throws(MachineError) -> [(heading: String, name: String)] {
        guard output.status != 0 else { return [] }
        var heading: String?
        var removals: [(heading: String, name: String)] = []
        for line in output.stdout.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("Would "), line.hasSuffix(":") {
                let title = line.dropFirst("Would ".count).dropLast()
                heading = title.hasPrefix("uninstall ") || title == "untap" ? String(title) : nil
            } else if line.hasPrefix("Run `brew bundle cleanup") {
                heading = nil
            } else if let heading {
                removals.append((heading, String(line)))
            }
        }
        guard !removals.isEmpty else { throw failure(output, "brew bundle cleanup") }
        return removals
    }

    public static func failure(_ output: CommandOutput, _ command: String) -> MachineError {
        let lines = output.stderr.split(whereSeparator: \.isNewline)
        let reason = lines.first { $0.hasPrefix("Error:") } ?? lines.last
        return MachineError("\(command) exited with status \(output.status)\(reason.map { ": \($0)" } ?? "")")
    }
}

public enum RootScript {
    public static let sudoLocalPath = "/etc/pam.d/sudo_local"
    static let statusMarker = "anaclast-root-status"

    public static func backupPath(at date: Date) -> String {
        sudoLocalPath + ".anaclast-backup-" + date.formatted(.iso8601.dateSeparator(.omitted).timeSeparator(.omitted))
    }

    public static func modulePaths(in contents: String) -> [String] {
        var paths: [String] = []
        for line in contents.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count > 2, !fields[0].hasPrefix("#"), fields[2].hasPrefix("/"), !paths.contains(String(fields[2])) else { continue }
            paths.append(String(fields[2]))
        }
        return paths
    }

    public static func removalRefusal(installing files: some Sequence<String>, sudoLocal: String) -> String? {
        let resolved = { (path: String) in URL(fileURLWithPath: path).resolvingSymlinksInPath().path(percentEncoded: false) }
        let installed = Set(files.map(resolved))
        let loaded = modulePaths(in: sudoLocal).filter { installed.contains(resolved($0)) }
        guard !loaded.isEmpty else { return nil }
        return "refused: \(sudoLocalPath) loads \(loaded.joined(separator: ", ")), which this formula installs, and sudo fails when a PAM module is missing"
    }

    public static func render(_ steps: [MachineStep]) -> String {
        var lines = ["#!/bin/sh", "exec 2>&1"]
        for (index, step) in steps.enumerated() {
            guard let command = command(for: step) else { continue }
            lines.append(command)
            lines.append("/bin/echo \(statusMarker) \(index) $?")
        }
        lines.append("exit 0")
        return lines.map { $0 + "\n" }.joined()
    }

    static func command(for step: MachineStep) -> String? {
        switch step {
        case .sudoLocal(let contents, _, let backup):
            let path = sudoLocalPath.shellQuoted
            let backup = backup.shellQuoted
            let checks = modulePaths(in: contents).map { module in
                "{ [ -f \(module.shellQuoted) ] || { /usr/bin/printf '%s\\n' \("\(module) is not a regular file, so \(sudoLocalPath) is left unchanged".shellQuoted); false; }; }"
            }
            let write = "{ [ ! -e \(path) ] || { [ ! -e \(backup) ] && [ ! -L \(backup) ] && /bin/cp -L \(path) \(backup); }; } && /bin/rm -f \(path) && /usr/bin/printf '%s' \(contents.shellQuoted) > \(path) && /usr/sbin/chown root:wheel \(path) && /bin/chmod 0444 \(path)"
            return (checks + [write]).joined(separator: " && ")
        case .brewRemove:
            guard case .appStore(let id)? = step.removal else { return nil }
            // mas uninstall needs root, and as root it reads SUDO_UID and SUDO_GID to hand the app back to this user before trashing it.
            return "MAS_NO_AUTO_INDEX=1 SUDO_UID=\(getuid()) SUDO_GID=\(getgid()) /opt/homebrew/bin/mas uninstall \(id)"
        case .hostName(let kind, _, let name):
            return "/usr/sbin/scutil --set \(kind.rawValue) \(name.shellQuoted)"
        case .remoteLogin:
            return "/bin/launchctl enable system/com.openssh.sshd && /bin/launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist"
        default:
            return nil
        }
    }

    public static func statuses(in output: String) -> [Int: Int32] {
        var statuses: [Int: Int32] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ")
            guard fields.count == 3, fields[0] == statusMarker, let index = Int(fields[1]), let status = Int32(fields[2]) else { continue }
            statuses[index] = status
        }
        return statuses
    }
}

public struct MachinePlan: Sendable {
    public struct Note: Sendable, Hashable {
        public let category: MachineStep.Category
        public let message: String
    }

    public let host: String?
    public let localHostName: String?
    public let steps: [MachineStep]
    public let notes: [Note]
    public let brewfile: Brewfile

    public var destructiveCount: Int { steps.count(where: \.isDestructive) }

    public var categories: [MachineStep.Category] {
        MachineStep.Category.allCases.filter { category in
            steps.contains { $0.category == category } || notes.contains { $0.category == category }
        }
    }

    public func stepIndices(in category: MachineStep.Category) -> [Int] {
        steps.indices.filter { steps[$0].category == category }
    }

    public func notes(in category: MachineStep.Category) -> [String] {
        notes.filter { $0.category == category }.map(\.message)
    }

    public func removals(_ indices: [Int], stillListedIn listing: [(heading: String, name: String)]) -> (pending: [Int], skipped: [Int: String]) {
        var listed: [Int] = []
        var skipped: [Int: String] = [:]
        for index in indices {
            guard case .brewRemove(let heading, let name) = steps[index] else { continue }
            if listing.contains(where: { $0.heading == heading && $0.name == name }) {
                listed.append(index)
            } else {
                skipped[index] = "no longer removable, now required"
            }
        }
        let casks = listed.filter { if case .cask? = steps[$0].removal { true } else { false } }
        let formulae = listed.filter { if case .formula? = steps[$0].removal { true } else { false } }
        // brew bundle lists each formula after its dependencies, so the reverse uninstalls every dependent before what it needs.
        return (casks + formulae.reversed() + listed.filter { !casks.contains($0) && !formulae.contains($0) }, skipped)
    }

    public static func make(config: MachineConfig, configDirectory: String, home: String, refreshDownloads: Bool, now: Date = .now, probe: some MachineProbe) async throws -> MachinePlan {
        let names = try await probe.hostNames()
        let host = config.host(named: names[.localHostName])
        let brewfile = Brewfile(homebrew: config.homebrew, host: host)
        var steps: [MachineStep] = []
        var notes: [Note] = []

        do {
            let check = try await probe.brewBundle(["check", "--verbose"], brewfile: brewfile.install)
            steps += try Brewfile.missing(fromCheck: check).map(MachineStep.brewInstall)
        } catch {
            steps.append(.brewUnchecked(error.localizedDescription))
        }
        if config.homebrew.cleanup {
            do {
                let cleanup = try await probe.brewBundle(["cleanup"], brewfile: brewfile.cleanup)
                steps += try Brewfile.removals(fromCleanup: cleanup).map { MachineStep.brewRemove(heading: $0.heading, name: $0.name) }
            } catch {
                notes.append(Note(category: .homebrew, message: "cleanup was not checked: \(error.localizedDescription)"))
            }
        }

        for clone in config.clones {
            steps.append(probe.state(of: clone.path) == .missing ? .clone(url: clone.url, path: clone.path) : .pull(path: clone.path))
        }

        for download in config.downloads {
            let existing = download.install.map(\.to).filter { probe.state(of: $0) != .missing }
            if refreshDownloads || existing.count < download.install.count {
                steps.append(.download(download, existing: existing))
            }
        }

        if !config.bunGlobals.isEmpty {
            do {
                var installed = Set<String>()
                if let listing = try await probe.bunGlobals() {
                    guard listing.status == 0 else { throw MachineError("bun pm ls --global exited with status \(listing.status)") }
                    installed = bunPackages(inListing: listing.stdout)
                } else {
                    notes.append(Note(category: .bunGlobals, message: "bun is not installed, so every global is listed"))
                }
                steps += config.bunGlobals.filter { !installed.contains(packageName($0)) }.map(MachineStep.bunGlobal)
            } catch {
                notes.append(Note(category: .bunGlobals, message: "globals were not checked: \(error.localizedDescription)"))
            }
        }

        for link in config.links {
            let destination = (configDirectory as NSString).appendingPathComponent(link.source)
            guard probe.state(of: destination) != .missing else {
                notes.append(Note(category: .links, message: "\(destination) does not exist, so \(link.target) is not linked"))
                continue
            }
            let state = probe.state(of: link.target)
            if state != .link(destination) {
                steps.append(.link(target: link.target, destination: destination, replacing: state))
            }
        }

        var files = [GeneratedFile.hostEnvironment(host.env, home: home)]
        if let keys = host.authorizedKeys { files.append(.authorizedKeys(keys, home: home)) }
        for file in files {
            let state = probe.state(of: file.path)
            if state != .file || probe.contents(of: file.path) != file.contents {
                steps.append(.file(file, replacing: state))
            }
        }

        var changedDomains: [String] = []
        for preference in config.preferences {
            let live = probe.preference(domain: preference.domain, key: preference.key, currentHost: preference.currentHost)
            guard !matches(live: live, desired: preference.value) else { continue }
            steps.append(.preference(preference, live: render(live)))
            if !changedDomains.contains(preference.domain) { changedDomains.append(preference.domain) }
        }
        var restarts: [(process: String, domains: [String])] = []
        for domain in changedDomains {
            guard let process = config.restart[domain] else { continue }
            if let index = restarts.firstIndex(where: { $0.process == process }) {
                restarts[index].domains.append(domain)
            } else {
                restarts.append((process, [domain]))
            }
        }
        steps += restarts.map { MachineStep.restart(process: $0.process, domains: $0.domains) }

        if let sudoLocal = config.sudoLocal, probe.contents(of: RootScript.sudoLocalPath) != sudoLocal {
            steps.append(.sudoLocal(sudoLocal, replacing: probe.state(of: RootScript.sudoLocalPath) != .missing, backup: RootScript.backupPath(at: now)))
        }
        for kind in MachineConfig.HostNameKind.allCases {
            guard let desired = host.names[kind], names[kind] != desired else { continue }
            steps.append(.hostName(kind, from: names[kind], to: desired))
        }
        if config.remoteLogin {
            do {
                let output = try await probe.launchdDisabledServices()
                switch remoteLoginEnabled(inDisabledServices: output.stdout) {
                case false?: steps.append(.remoteLogin)
                case true?: break
                case nil: notes.append(Note(category: .system, message: "Remote Login check skipped: launchctl print-disabled system does not list com.openssh.sshd"))
                }
            } catch {
                notes.append(Note(category: .system, message: "Remote Login check skipped: \(error.localizedDescription)"))
            }
        }

        return MachinePlan(host: host.key, localHostName: names[.localHostName], steps: steps, notes: notes, brewfile: brewfile)
    }

    public static func matches(live: Any?, desired: Any) -> Bool {
        switch desired {
        case let desired as [String: Any]:
            guard let live = live as? [String: Any] else { return false }
            return desired.allSatisfy { key, value in matches(live: live[key], desired: value) }
        case let desired as [Any]:
            guard let live = live as? [Any], live.count == desired.count else { return false }
            return zip(live, desired).allSatisfy { matches(live: $0, desired: $1) }
        default:
            guard let live = live as? NSObject, let desired = desired as? NSObject else { return false }
            return live.isEqual(desired)
        }
    }

    public static func render(_ value: Any?) -> String {
        let text = describe(value)
        return text.count > 160 ? String(text.prefix(159)) + "…" : text
    }

    private static func describe(_ value: Any?) -> String {
        switch value {
        case nil: "(unset)"
        case let string as String: "\"\(string)\""
        case let number as NSNumber: CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
        case let data as Data: "<\(data.count) bytes>"
        case let date as Date: date.formatted(.iso8601)
        case let array as [Any]: "[" + array.map(describe).joined(separator: ", ") + "]"
        case let object as [String: Any]: "{" + object.sorted { $0.key < $1.key }.map { "\($0.key): \(describe($0.value))" }.joined(separator: ", ") + "}"
        case let value?: String(describing: value)
        }
    }

    public static func bunPackages(inListing listing: String) -> Set<String> {
        var names = Set<String>()
        for line in listing.split(whereSeparator: \.isNewline) where line.hasPrefix("├── ") || line.hasPrefix("└── ") {
            names.insert(packageName(String(line.dropFirst(4))))
        }
        return names
    }

    public static func packageName(_ spec: String) -> String {
        guard let at = spec.dropFirst().lastIndex(of: "@") else { return spec }
        return String(spec[..<at])
    }

    public static func remoteLoginEnabled(inDisabledServices output: String) -> Bool? {
        let prefix = "\"com.openssh.sshd\" =>"
        for line in output.split(whereSeparator: \.isNewline) {
            let entry = line.trimmingCharacters(in: .whitespaces)
            guard entry.hasPrefix(prefix) else { continue }
            switch entry.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces) {
            case "enabled", "false": return true
            case "disabled", "true": return false
            default: return nil
            }
        }
        return nil
    }
}
