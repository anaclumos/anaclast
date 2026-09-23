import AppKit
import CoreGraphics
import Synchronization
import AnaclastCore

final class EventTap: @unchecked Sendable {
    private let engine: Mutex<KeyboardEngine>
    private let frontmostApp = Mutex<String?>(nil)
    private let perform: @Sendable ([Action]) -> Void
    private var port: CFMachPort?
    private var thread: Thread?

    init(keymap: Keymap, perform: @escaping @Sendable ([Action]) -> Void) {
        engine = Mutex(KeyboardEngine(keymap: keymap))
        self.perform = perform
    }

    func replace(keymap: Keymap) {
        engine.withLock { $0.replace(keymap: keymap) }
    }

    func setFrontmostApp(_ bundleID: String?) {
        frontmostApp.withLock { $0 = bundleID }
    }

    func start(onRunning: @escaping @Sendable () -> Void) {
        guard thread == nil else { return }
        let thread = Thread { [self] in run(onRunning: onRunning) }
        thread.name = "anaclast.eventtap"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    private func run(onRunning: @Sendable () -> Void) {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            return Unmanaged<EventTap>.fromOpaque(info).takeUnretainedValue().handle(type: type, event: event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            log.error("event tap creation failed; Accessibility not granted")
            return
        }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        log.info("event tap running")
        onRunning()
        CFRunLoopRun()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            engine.withLock { $0.reset() }
            log.notice("event tap re-enabled after \(type.rawValue)")
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == KeySender.marker {
            return Unmanaged.passUnretained(event)
        }
        let kind: KeyEvent.Kind
        switch type {
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .flagsChanged: kind = .flagsChanged
        default: kind = .pointer
        }
        let keyEvent = KeyEvent(
            kind: kind,
            keyCode: KeyCode(UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))),
            flags: event.flags,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            time: ProcessInfo.processInfo.systemUptime,
            hyperSourceHeld: kind != .keyDown || CGEventSource.keyState(.hidSystemState, key: KeyCode.f18.rawValue)
        )
        let app = frontmostApp.withLock { $0 }
        let resolution = engine.withLock { $0.handle(keyEvent, frontmostApp: app) }
        if !resolution.actions.isEmpty {
            perform(resolution.actions)
        }
        if let rewrite = resolution.rewrite {
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(rewrite.keyCode.rawValue))
            event.flags = rewrite.flags
        }
        return resolution.swallow ? nil : Unmanaged.passUnretained(event)
    }
}
