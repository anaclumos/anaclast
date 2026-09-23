import AppKit
import IOKit
import IOKit.hidsystem

@MainActor
enum SystemActions {
    private typealias GetTheme = @convention(c) () -> Int32
    private typealias SetTheme = @convention(c) (Int32, Bool) -> Void
    private typealias LockScreen = @convention(c) () -> Int32
    private typealias DockNotification = @convention(c) (CFString, Int32) -> Int32

    static func toggleDarkMode() {
        guard let get = PrivateFramework.skyLight.symbol("SLSGetAppearanceThemeLegacy", as: GetTheme.self),
              let set = PrivateFramework.skyLight.symbol("SLSSetAppearanceThemeNotifying", as: SetTheme.self) else { return }
        set(get() == 1 ? 0 : 1, true)
    }

    static func lockScreen() {
        guard let lock = PrivateFramework.login.symbol("SACLockScreenImmediate", as: LockScreen.self) else { return }
        let status = lock()
        if status != 0 { log.error("SACLockScreenImmediate returned \(status)") }
    }

    static func missionControl() {
        dock("com.apple.expose.awake")
    }

    static func showDesktop() {
        dock("com.apple.showdesktop.awake")
    }

    private static func dock(_ notification: String) {
        guard let send = PrivateFramework.loaded.symbol("CoreDockSendNotification", as: DockNotification.self) else { return }
        let status = send(notification as CFString, 0)
        if status != 0 { log.error("CoreDockSendNotification \(notification, privacy: .public) returned \(status)") }
    }

    static func toggleCapsLock() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else {
            log.error("cannot open IOHIDSystem")
            return
        }
        defer { IOServiceClose(connect) }
        var state = false
        IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &state)
        IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), !state)
    }
}
