import Foundation
import AnaclastCore

enum CommandLineTool {
    static let verbs: Set<String> = ["plan", "apply", "settings"]

    static func run(verb: String, arguments: [String]) -> Int32 {
        if verb == "settings" { return settings(arguments) }
        let session = MachineSession(directory: MainActor.assumeIsolated { ConfigStore.machineDirectory }, home: MachineSession.currentHome)
        Task {
            exit(await main(verb: verb, arguments: arguments, session: session))
        }
        dispatchMain()
    }

    private static func main(verb: String, arguments: [String], session: MachineSession) async -> Int32 {
        let allowed: Set<String> = verb == "apply" ? ["--update", "--yes"] : []
        if let unknown = arguments.first(where: { !allowed.contains($0) }) {
            printError("anaclast \(verb): unknown argument \(unknown)\nusage: anaclast plan | anaclast apply [--update] [--yes]")
            return 2
        }
        let plan: MachinePlan
        do {
            plan = try await session.plan(refreshDownloads: arguments.contains("--update"))
        } catch {
            printError("anaclast: cannot load \(session.configURL.path(percentEncoded: false)): \(error)")
            return 1
        }
        printPlan(plan)
        guard verb == "apply", !plan.steps.isEmpty else { return 0 }

        var includeDestructive = arguments.contains("--yes")
        if plan.destructiveCount > 0 && !includeDestructive {
            if isatty(STDIN_FILENO) != 0 {
                write("Apply \(plan.destructiveCount) destructive changes? [y/N] ", newline: false)
                includeDestructive = ["y", "yes"].contains(readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? "")
            } else {
                write("stdin is not a terminal and --yes was not given, so \(plan.destructiveCount) destructive changes are skipped.")
            }
        }
        let summary = await MachineApplier(home: session.home, output: { write($0) }).apply(plan, includeDestructive: includeDestructive)
        write("")
        for entry in summary.entries {
            switch entry.result {
            case .succeeded: break
            case .failed(let reason): write("failed   \(entry.step): \(reason)")
            case .skipped(let reason): write("skipped  \(entry.step): \(reason)")
            }
        }
        write("\(summary.succeeded) succeeded, \(summary.failed) failed, \(summary.skipped) skipped.")
        return summary.failed == 0 ? 0 : 1
    }

    private static func settings(_ arguments: [String]) -> Int32 {
        let url = MainActor.assumeIsolated { ConfigStore.configURL }
        do {
            switch (arguments.first, arguments.count) {
            case ("get", 1):
                write(String(decoding: try Config.load(from: url, validating: false).encoded(), as: UTF8.self))
            case ("get", 2):
                write(String(decoding: try Config.load(from: url, validating: false).value(at: arguments[1]), as: UTF8.self))
            case ("set", 3):
                let config = try ConfigFile.update(at: url) { $0 = try $0.setting(arguments[1], to: Data(arguments[2].utf8)) }
                if let value = try? config.value(at: arguments[1]) {
                    write(String(decoding: value, as: UTF8.self))
                }
            case ("unset", 2):
                try ConfigFile.update(at: url) { $0 = try $0.setting(arguments[1], to: nil) }
            default:
                printError("usage: anaclast settings get [path] | set <path> <json> | unset <path>\nPaths are dotted keys of ~/.config/anaclast/config.json, such as hyper.tapTimeoutMilliseconds or hyper.keys.g.")
                return 2
            }
            return 0
        } catch {
            printError("anaclast settings: \(error)")
            return 1
        }
    }

    private static func printPlan(_ plan: MachinePlan) {
        write("Host \(plan.localHostName ?? "(unknown)"), using \(plan.host.map { "hosts.\($0)" } ?? "no host entry")")
        for category in plan.categories {
            write("\n\(category)")
            for index in plan.stepIndices(in: category) {
                let step = plan.steps[index]
                write(step.isDestructive ? "  ! \(step)  [destructive]" : "  + \(step)")
            }
            for note in plan.notes(in: category) {
                write("  note: \(note)")
            }
        }
        write(plan.steps.isEmpty ? "\nNothing to change." : "\n\(plan.steps.count) changes, \(plan.destructiveCount) destructive.")
    }

    private static func write(_ text: String, newline: Bool = true) {
        try? FileHandle.standardOutput.write(contentsOf: Data((newline ? text + "\n" : text).utf8))
    }

    private static func printError(_ text: String) {
        try? FileHandle.standardError.write(contentsOf: Data((text + "\n").utf8))
    }
}
