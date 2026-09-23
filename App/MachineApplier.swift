import Foundation
import AnaclastCore

struct MachineSummary: Sendable {
    enum Result: Sendable, Equatable {
        case succeeded
        case failed(String)
        case skipped(String)
    }

    struct Entry: Sendable {
        let step: MachineStep
        let result: Result
    }

    let entries: [Entry]

    var succeeded: Int { entries.count { $0.result == .succeeded } }
    var failed: Int { entries.count { if case .failed = $0.result { true } else { false } } }
    var skipped: Int { entries.count { if case .skipped = $0.result { true } else { false } } }
}

struct MachineApplier: Sendable {
    let home: String
    let output: @Sendable (String) -> Void

    @concurrent
    func apply(_ plan: MachinePlan, includeDestructive: Bool) async -> MachineSummary {
        var results: [Int: MachineSummary.Result] = [:]
        var pending: [Int] = []
        for (index, step) in plan.steps.enumerated() {
            if step.isDestructive && !includeDestructive {
                results[index] = .skipped("destructive change not confirmed")
            } else {
                pending.append(index)
            }
        }
        let byCategory = Dictionary(grouping: pending) { plan.steps[$0].category }

        let appStore = await applyHomebrew(byCategory[.homebrew] ?? [], plan: plan, into: &results)
        for category in [MachineStep.Category.clones, .downloads, .bunGlobals, .links, .generatedFiles, .preferences] {
            for index in byCategory[category] ?? [] {
                results[index] = await record(plan.steps[index]) { try await execute(plan.steps[index]) }
            }
        }
        for index in byCategory[.restarts] ?? [] {
            guard case .restart(let process, let domains) = plan.steps[index] else { continue }
            let changed = plan.steps.indices.contains { other in
                guard case .preference(let preference, _) = plan.steps[other] else { return false }
                return domains.contains(preference.domain) && results[other] == .succeeded
            }
            guard changed else {
                results[index] = .skipped("no preference in \(domains.joined(separator: ", ")) changed")
                continue
            }
            results[index] = await record(plan.steps[index]) { try await run("/usr/bin/killall", [process]) }
        }
        await applySystem(appStore + (byCategory[.system] ?? []), plan: plan, into: &results)

        let entries = plan.steps.indices.map { MachineSummary.Entry(step: plan.steps[$0], result: results[$0] ?? .skipped("not run")) }
        return MachineSummary(entries: entries)
    }

    private func applyHomebrew(_ indices: [Int], plan: MachinePlan, into results: inout [Int: MachineSummary.Result]) async -> [Int] {
        guard !indices.isEmpty else { return [] }
        guard FileManager.default.isExecutableFile(atPath: MachineTools.brew) else {
            let message = "Homebrew is not installed at \(MachineTools.brew); install it from https://brew.sh and apply again"
            output("Homebrew: \(message)")
            for index in indices { results[index] = .failed(message) }
            return []
        }
        let removals = indices.filter { if case .brewRemove = plan.steps[$0] { true } else { false } }
        let installs = indices.filter { !removals.contains($0) }
        var appStore: [Int] = []
        do {
            let directory = try MachineTools.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let install = directory.appending(path: "Brewfile")
            let cleanup = directory.appending(path: "Brewfile.cleanup")
            try Data(plan.brewfile.install.utf8).write(to: install)
            try Data(plan.brewfile.cleanup.utf8).write(to: cleanup)
            if !installs.isEmpty {
                output("==> brew update")
                if case .failed(let message) = await result({ try await run(MachineTools.brew, ["update"]) }) {
                    output("brew update failed, installing from the current formulae: \(message)")
                }
                output("==> brew bundle install (\(installs.count) missing)")
                let outcome = await result { try await run(MachineTools.brew, ["bundle", "install", "--file=\(install.path(percentEncoded: false))"]) }
                for index in installs { results[index] = outcome }
            }
            if !removals.isEmpty {
                output("==> brew bundle cleanup (checking \(removals.count) confirmed removals)")
                let listing = try Brewfile.removals(fromCleanup: try await MachineTools.run(MachineTools.brew, ["bundle", "cleanup", "--file=\(cleanup.path(percentEncoded: false))"], environment: MachineTools.homebrewEnvironment))
                let sudoLocal = FileManager.default.fileExists(atPath: RootScript.sudoLocalPath) ? try String(contentsOfFile: RootScript.sudoLocalPath, encoding: .utf8) : ""
                let (pending, skipped) = plan.removals(removals, stillListedIn: listing)
                results.merge(skipped.mapValues(MachineSummary.Result.skipped)) { $1 }
                for index in pending {
                    let step = plan.steps[index]
                    if case .appStore? = step.removal {
                        appStore.append(index)
                        continue
                    }
                    output("==> \(step)")
                    results[index] = await result { try await remove(step, sudoLocal: sudoLocal) }
                }
            }
        } catch {
            for index in indices where results[index] == nil { results[index] = .failed(error.localizedDescription) }
        }
        for index in indices {
            if case .failed(let message) = results[index] { output("FAILED \(plan.steps[index]): \(message)") }
        }
        return appStore
    }

    private func remove(_ step: MachineStep, sudoLocal: String) async throws {
        guard let removal = step.removal, let arguments = removal.brewArguments else {
            throw MachineError("no uninstall command for this cleanup entry")
        }
        if case .formula(let name) = removal, !RootScript.modulePaths(in: sudoLocal).isEmpty {
            let files = try await MachineTools.run(MachineTools.brew, ["list", "--formula", name], environment: MachineTools.homebrewEnvironment)
            guard files.status == 0 else { throw Brewfile.failure(files, "brew list --formula \(name)") }
            if let refusal = RootScript.removalRefusal(installing: files.stdout.split(whereSeparator: \.isNewline).map(String.init), sudoLocal: sudoLocal) {
                throw MachineError(refusal)
            }
        }
        let outcome = try await MachineTools.run(MachineTools.brew, arguments, environment: MachineTools.homebrewEnvironment, onLine: output)
        guard outcome.status == 0 else { throw Brewfile.failure(outcome, "brew \(arguments.joined(separator: " "))") }
    }

    private func applySystem(_ indices: [Int], plan: MachinePlan, into results: inout [Int: MachineSummary.Result]) async {
        guard !indices.isEmpty else { return }
        let steps = indices.map { plan.steps[$0] }
        output("==> administrator script: \(steps.map(\.description).joined(separator: "; "))")
        do {
            let directory = try MachineTools.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let script = directory.appending(path: "anaclast-root.sh")
            guard FileManager.default.createFile(atPath: script.path(percentEncoded: false), contents: Data(RootScript.render(steps).utf8), attributes: [.posixPermissions: 0o700]) else {
                throw MachineError("could not write \(script.path(percentEncoded: false))")
            }
            let outcome = try await MachineTools.run("/usr/bin/osascript", [
                "-e", "on run argv",
                "-e", "do shell script quoted form of (item 1 of argv) with administrator privileges without altering line endings",
                "-e", "end run",
                script.path(percentEncoded: false),
            ], onLine: output)
            let statuses = RootScript.statuses(in: outcome.stdout)
            for (position, index) in indices.enumerated() {
                switch statuses[position] {
                case 0?: results[index] = .succeeded
                case let status?: results[index] = .failed("exited with status \(status)")
                case nil: results[index] = .failed(outcome.status == 0 ? "the administrator script reported no status" : "osascript exited with status \(outcome.status): \(outcome.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
        } catch {
            for index in indices { results[index] = .failed(error.localizedDescription) }
        }
        for index in indices {
            if case .failed(let message) = results[index] { output("FAILED \(plan.steps[index]): \(message)") }
        }
    }

    private func record(_ step: MachineStep, _ body: () async throws -> Void) async -> MachineSummary.Result {
        output("==> \(step)")
        let outcome = await result(body)
        if case .failed(let message) = outcome { output("FAILED \(step): \(message)") }
        return outcome
    }

    private func result(_ body: () async throws -> Void) async -> MachineSummary.Result {
        do {
            try await body()
            return .succeeded
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func run(_ executable: String, _ arguments: [String]) async throws {
        let outcome = try await MachineTools.run(executable, arguments, environment: MachineTools.homebrewEnvironment, onLine: output)
        guard outcome.status == 0 else {
            throw MachineError("\(([executable] + arguments).joined(separator: " ")) exited with status \(outcome.status)")
        }
    }

    private func execute(_ step: MachineStep) async throws {
        switch step {
        case .clone(let url, let path):
            try await run(MachineTools.git, ["clone", url, path])
        case .pull(let path):
            try await run(MachineTools.git, ["-C", path, "pull", "--ff-only"])
        case .download(let download, let existing):
            try await install(download, replacing: !existing.isEmpty)
        case .bunGlobal(let name):
            guard let bun = MachineTools.bun(home: home) else {
                throw MachineError("bun is not installed at /opt/homebrew/bin/bun or \(home)/.bun/bin/bun")
            }
            try await run(bun, ["add", "--global", name])
        case .link(let target, let destination, let replacing):
            try prepare(target, replacing: replacing != .missing)
            try FileManager.default.createSymbolicLink(atPath: target, withDestinationPath: destination)
        case .file(let file, let replacing):
            try prepare(file.path, replacing: replacing != .missing)
            if let mode = file.directoryMode {
                try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: (file.path as NSString).deletingLastPathComponent)
            }
            guard FileManager.default.createFile(atPath: file.path, contents: Data(file.contents.utf8), attributes: [.posixPermissions: file.mode]) else {
                throw MachineError("could not write \(file.path)")
            }
        case .preference(let preference, _):
            try MachinePreferences.write(preference)
        case .brewInstall, .brewUnchecked, .brewRemove, .restart, .sudoLocal, .hostName, .remoteLogin:
            throw MachineError("\(step.category) steps run as a batch")
        }
    }

    private func prepare(_ path: String, replacing: Bool) throws {
        if (try? FileManager.default.attributesOfItem(atPath: path)) != nil {
            guard replacing else { throw MachineError("\(path) appeared after planning; plan again") }
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            output("moved \(path) to the Trash")
        }
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    }

    private func install(_ download: MachineConfig.Download, replacing: Bool) async throws {
        guard let url = URL(string: download.url) else { throw MachineError("\(download.url) is not a URL") }
        let directory = try MachineTools.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        output("downloading \(download.url)")
        let (file, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MachineError("\(download.url) returned HTTP \(http.statusCode)")
        }
        let archive = directory.appending(path: "archive")
        let extracted = directory.appending(path: "extracted")
        try FileManager.default.moveItem(at: file, to: archive)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        switch download.format {
        case .tarGz: try await run("/usr/bin/tar", ["-xzf", archive.path(percentEncoded: false), "-C", extracted.path(percentEncoded: false)])
        case .zip: try await run("/usr/bin/ditto", ["-x", "-k", archive.path(percentEncoded: false), extracted.path(percentEncoded: false)])
        }
        for entry in download.install {
            let source = extracted.appending(path: entry.from)
            var items = [(source, entry.to)]
            if entry.from.hasSuffix("/") {
                let children = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
                    .filter { entry.pathExtension == nil || $0.pathExtension == entry.pathExtension }
                guard !children.isEmpty else { throw MachineError("\(download.name): \(entry.from) has no matching files") }
                try FileManager.default.createDirectory(atPath: entry.to, withIntermediateDirectories: true)
                items = children.map { ($0, (entry.to as NSString).appendingPathComponent($0.lastPathComponent)) }
            }
            for (item, destination) in items {
                try prepare(destination, replacing: replacing)
                try FileManager.default.copyItem(at: item, to: URL(fileURLWithPath: destination))
                if entry.executable == true {
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination)
                }
                output("installed \(destination)")
            }
        }
    }
}
