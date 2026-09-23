import AppKit
import ServiceManagement

@MainActor
enum LoginAgent {
    static let label = "com.anaclumos.anaclast"
    static let service = SMAppService.agent(plistName: "\(label).plist")

    static var isAgentInstance: Bool {
        ProcessInfo.processInfo.environment["ANACLAST_AGENT"] == "1"
    }

    static func handOffIfNeeded() -> Bool {
        guard !isAgentInstance else {
            if waitForOthersToExit() { return false }
            otherInstances.forEach { $0.terminate() }
            if waitForOthersToExit() { return false }
            log.error("another Anaclast instance kept running; the login agent exits")
            return true
        }
        if service.status == .notRegistered || service.status == .notFound {
            do {
                try service.register()
            } catch {
                log.error("login agent registration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        switch service.status {
        case .enabled:
            let kickstart = Process()
            kickstart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            kickstart.arguments = ["kickstart", "gui/\(getuid())/\(label)"]
            do {
                try kickstart.run()
                kickstart.waitUntilExit()
                if kickstart.terminationStatus == 0 {
                    log.info("handed off to the login agent")
                    return true
                }
                log.error("kickstart exited with \(kickstart.terminationStatus)")
            } catch {
                log.error("kickstart failed: \(error.localizedDescription, privacy: .public)")
            }
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        default:
            break
        }
        return !otherInstances.isEmpty
    }

    private static var otherInstances: [NSRunningApplication] {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? label)
            .filter { $0.processIdentifier != me }
    }

    private static func waitForOthersToExit() -> Bool {
        let deadline = Date.now.addingTimeInterval(5)
        while Date.now < deadline {
            if otherInstances.isEmpty { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return otherInstances.isEmpty
    }
}
