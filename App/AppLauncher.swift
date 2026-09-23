import AppKit
import ApplicationServices
import AnaclastCore

@MainActor
enum AppLauncher {
    static func open(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            log.notice("no app for \(bundleID, privacy: .public)")
            return
        }
        open(url: url)
    }

    static func open(url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error { log.error("open \(url.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    static func openDefaultBrowser() {
        guard let probe = URL(string: "http://example.com"), let browser = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return }
        open(url: browser)
    }

    static func focusOrLaunch(_ target: WindowTarget) {
        if focusWindow(of: target) { return }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.app) else {
            log.notice("no app for \(target.app, privacy: .public)")
            return
        }
        guard let launch = target.launch, let executable = launch.first else { return open(url: app) }
        let process = Process()
        process.executableURL = app.appending(path: executable)
        process.arguments = Array(launch.dropFirst())
        do {
            try process.run()
        } catch {
            log.error("launch \(executable, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func focusWindow(of target: WindowTarget) -> Bool {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: target.app).first else { return false }
        let element = AXUIElementCreateApplication(running.processIdentifier)
        for window in AX.children(element, kAXWindowsAttribute) {
            guard let title = AX.string(window, kAXTitleAttribute), target.matches(title: title) else { continue }
            running.activate()
            AX.set(window, kAXMainAttribute, kCFBooleanTrue)
            AX.set(window, kAXFocusedAttribute, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            return true
        }
        return false
    }
}
