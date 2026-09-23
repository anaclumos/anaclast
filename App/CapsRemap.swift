import IOKit
import IOKit.hid
import IOKit.hidsystem

@MainActor
enum CapsRemap {
    static let capsLockUsage: UInt64 = 0x7_0000_0039
    static let f18Usage: UInt64 = 0x7_0000_006D

    private static let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private static var manager: IOHIDManager?
    private(set) static var isApplied = false

    static func apply() {
        isApplied = true
        write([[kIOHIDKeyboardModifierMappingSrcKey: capsLockUsage, kIOHIDKeyboardModifierMappingDstKey: f18Usage]])
        watchKeyboards()
    }

    static func reset() {
        isApplied = false
        write([])
    }

    static func reapply() {
        guard isApplied else { return }
        write([[kIOHIDKeyboardModifierMappingSrcKey: capsLockUsage, kIOHIDKeyboardModifierMappingDstKey: f18Usage]])
    }

    private static func write(_ mapping: [[String: UInt64]]) {
        if IOHIDEventSystemClientSetProperty(client, kIOHIDUserKeyUsageMapKey as CFString, mapping as CFArray) {
            log.info("UserKeyMapping set with \(mapping.count) entries")
        } else {
            log.error("UserKeyMapping set failed")
        }
    }

    private static func watchKeyboards() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard] as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { CapsRemap.reapply() }
            }
        }, nil)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        self.manager = manager
    }
}
