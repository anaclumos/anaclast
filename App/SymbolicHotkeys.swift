import AppKit

@MainActor
final class SymbolicHotkeyGuard {
    private typealias IsEnabled = @convention(c) (Int32) -> Bool
    private typealias SetEnabled = @convention(c) (Int32, Bool) -> Int32

    private var ids: [Int] = []
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    static let domain = "com.apple.symbolichotkeys" as CFString
    static let key = "AppleSymbolicHotKeys" as CFString

    func start(disabling ids: [Int]) {
        self.ids = ids
        persist()
        enforce()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.enforce() }
        }
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enforce() }
            })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.enforce() }
        })
    }

    func enforce() {
        guard let isEnabled = PrivateFramework.skyLight.symbol("CGSIsSymbolicHotKeyEnabled", as: IsEnabled.self),
              let setEnabled = PrivateFramework.skyLight.symbol("CGSSetSymbolicHotKeyEnabled", as: SetEnabled.self) else { return }
        for id in ids where isEnabled(Int32(id)) {
            let status = setEnabled(Int32(id), false)
            log.notice("symbolic hotkey \(id) was live again; disabled with status \(status)")
        }
    }

    private func persist() {
        let current = CFPreferencesCopyAppValue(Self.key, Self.domain) as? [String: Any] ?? [:]
        var updated = current
        var changed = false
        for id in ids {
            let name = String(id)
            var entry = current[name] as? [String: Any] ?? [:]
            guard entry["enabled"] as? Bool != false else { continue }
            entry["enabled"] = false
            updated[name] = entry
            changed = true
        }
        guard changed else { return }
        CFPreferencesSetAppValue(Self.key, updated as CFDictionary, Self.domain)
        CFPreferencesAppSynchronize(Self.domain)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
        process.arguments = ["-u"]
        do {
            try process.run()
        } catch {
            log.error("activateSettings failed: \(error.localizedDescription, privacy: .public)")
        }
        log.notice("persisted disabled symbolic hotkeys \(self.ids.map(String.init).joined(separator: ","), privacy: .public)")
    }
}
