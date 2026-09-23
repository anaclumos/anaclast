import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())

if let verb = arguments.first, CommandLineTool.verbs.contains(verb) {
    exit(CommandLineTool.run(verb: verb, arguments: Array(arguments.dropFirst())))
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
