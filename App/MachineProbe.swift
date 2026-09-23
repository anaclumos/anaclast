import Foundation
import AnaclastCore

enum MachineTools {
    static let brew = "/opt/homebrew/bin/brew"
    static let git = "/usr/bin/git"
    static let homebrewEnvironment = ["HOMEBREW_NO_ASK": "1", "HOMEBREW_NO_ENV_HINTS": "1", "HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_AUTOREMOVE": "1"]

    static func bun(home: String) -> String? {
        ["/opt/homebrew/bin/bun", home + "/.bun/bin/bun"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func run(_ executable: String, _ arguments: [String], environment: [String: String] = [:], onLine: @escaping @Sendable (String) -> Void = { _ in }) async throws -> CommandOutput {
        guard FileManager.default.isExecutableFile(atPath: executable) else { throw MachineError("\(executable) is not installed") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var merged = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        merged["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:" + (merged["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        process.environment = merged
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let (exits, exit) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = {
            exit.yield($0.terminationStatus)
            exit.finish()
        }
        do {
            try process.run()
        } catch {
            throw MachineError("\(executable) could not start: \(error.localizedDescription)")
        }
        async let out = lines(of: stdout.fileHandleForReading, onLine)
        async let err = lines(of: stderr.fileHandleForReading, onLine)
        let (output, errors) = try await (out, err)
        var status: Int32 = -1
        for await code in exits { status = code }
        return CommandOutput(status: status, stdout: output, stderr: errors)
    }

    private static func lines(of handle: FileHandle, _ onLine: @Sendable (String) -> Void) async throws -> String {
        var lines: [String] = []
        for try await line in handle.bytes.lines {
            onLine(line)
            lines.append(line)
        }
        return lines.map { $0 + "\n" }.joined()
    }

    static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "anaclast-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return directory
    }
}

enum MachinePreferences {
    static func application(_ domain: String) -> CFString {
        domain == MachineConfig.globalDomain ? kCFPreferencesAnyApplication : domain as CFString
    }

    static func host(_ currentHost: Bool) -> CFString {
        currentHost ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost
    }

    static func read(domain: String, key: String, currentHost: Bool) -> Any? {
        CFPreferencesCopyValue(key as CFString, application(domain), kCFPreferencesCurrentUser, host(currentHost))
    }

    static func write(_ preference: MachineConfig.Preference) throws {
        let application = application(preference.domain)
        let host = host(preference.currentHost)
        CFPreferencesSetValue(preference.key as CFString, preference.value as CFPropertyList, application, kCFPreferencesCurrentUser, host)
        guard CFPreferencesSynchronize(application, kCFPreferencesCurrentUser, host) else {
            throw MachineError("could not save \(preference.domain) \(preference.key)")
        }
        let live = read(domain: preference.domain, key: preference.key, currentHost: preference.currentHost)
        guard MachinePlan.matches(live: live, desired: preference.value) else {
            throw MachineError("\(preference.domain) \(preference.key) reads back as \(MachinePlan.render(live))")
        }
    }
}

struct LiveMachineProbe: MachineProbe {
    let home: String

    func hostNames() async throws -> [MachineConfig.HostNameKind: String] {
        var names: [MachineConfig.HostNameKind: String] = [:]
        for kind in MachineConfig.HostNameKind.allCases {
            let output = try await MachineTools.run("/usr/sbin/scutil", ["--get", kind.rawValue])
            if output.status == 0 { names[kind] = output.stdout.trimmingCharacters(in: .newlines) }
        }
        return names
    }

    func brewBundle(_ arguments: [String], brewfile: String) async throws -> CommandOutput {
        let directory = try MachineTools.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "Brewfile")
        try Data(brewfile.utf8).write(to: file)
        return try await MachineTools.run(MachineTools.brew, ["bundle"] + arguments + ["--file=\(file.path(percentEncoded: false))"], environment: MachineTools.homebrewEnvironment)
    }

    func bunGlobals() async throws -> CommandOutput? {
        guard let bun = MachineTools.bun(home: home) else { return nil }
        return try await MachineTools.run(bun, ["pm", "ls", "--global"])
    }

    func launchdDisabledServices() async throws -> CommandOutput {
        try await MachineTools.run("/bin/launchctl", ["print-disabled", "system"])
    }

    func preference(domain: String, key: String, currentHost: Bool) -> Any? {
        MachinePreferences.read(domain: domain, key: key, currentHost: currentHost)
    }

    func state(of path: String) -> FileState {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return .missing }
        switch attributes[.type] as? FileAttributeType {
        case .typeSymbolicLink?: return .link((try? FileManager.default.destinationOfSymbolicLink(atPath: path)) ?? "")
        case .typeDirectory?: return .directory
        default: return .file
        }
    }

    func contents(of path: String) -> String? {
        try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }
}

struct MachineSession: Sendable {
    let directory: URL
    let home: String

    static var currentHome: String {
        ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    }

    var configURL: URL { directory.appending(path: "machine.json") }

    @concurrent
    func plan(refreshDownloads: Bool) async throws -> MachinePlan {
        let config = try MachineConfig.load(from: configURL, home: home)
        return try await MachinePlan.make(
            config: config,
            configDirectory: directory.path(percentEncoded: false),
            home: home,
            refreshDownloads: refreshDownloads,
            probe: LiveMachineProbe(home: home)
        )
    }
}
