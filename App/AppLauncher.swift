import AppKit
import ApplicationServices

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

    static let cursorBundleID = "com.todesktop.230313mzl4w4u92"
    static let cursorAgentsTitle = "Cursor Agents"

    static func openCursor(agents: Bool) {
        if focusCursorWindow(agents: agents) { return }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: cursorBundleID) else { return }
        let cli = app.appending(path: "Contents/Resources/app/bin/cursor")
        let process = Process()
        process.executableURL = cli
        process.arguments = agents ? ["--glass"] : ["--classic", "-n"]
        do {
            try process.run()
        } catch {
            log.error("cursor cli failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func focusCursorWindow(agents: Bool) -> Bool {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: cursorBundleID).first else { return false }
        let element = AXUIElementCreateApplication(running.processIdentifier)
        for window in AX.children(element, kAXWindowsAttribute) {
            guard let title = AX.string(window, kAXTitleAttribute), !title.isEmpty else { continue }
            guard (title == cursorAgentsTitle) == agents else { continue }
            running.activate()
            AX.set(window, kAXMainAttribute, kCFBooleanTrue)
            AX.set(window, kAXFocusedAttribute, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            return true
        }
        return false
    }
}
