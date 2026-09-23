import Carbon
import CoreGraphics
import Foundation

enum InputSwitcher {
    private typealias GetKeyFocusProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<DarwinBoolean>) -> CGError
    private typealias CreatePerProcessRemote = @convention(c) (CFAllocator?, CFString, pid_t) -> Unmanaged<CFMessagePort>?
    private typealias CreateFlattenedInputSource = @convention(c) (TISInputSource, UnsafeMutablePointer<Unmanaged<CFTypeRef>?>) -> DarwinBoolean
    private typealias GetProcessPID = @convention(c) (UnsafePointer<ProcessSerialNumber>, UnsafeMutablePointer<pid_t>) -> OSStatus

    private static let selectInputSourceMessage: Int32 = 7

    static func select(_ id: String) {
        guard let source = InputSources.source(id: id) else {
            log.error("input source \(id, privacy: .public) is not enabled")
            return
        }
        do {
            try requestFocusedProcess(select: source)
        } catch {
            log.notice("TSM request failed (\(String(describing: error), privacy: .public)); falling back to TIS")
            TISSelectInputSource(source)
        }
    }

    enum Failure: Error {
        case missingSymbol, noFocusProcess, flattenFailed, noPort, transport(Int32), rejected(Int32)
    }

    private static func requestFocusedProcess(select source: TISInputSource) throws(Failure) {
        guard let getKeyFocus = PrivateFramework.loaded.symbol("CPSGetKeyFocusProcess", as: GetKeyFocusProcess.self),
              let createRemote = PrivateFramework.loaded.symbol("CFMessagePortCreatePerProcessRemote", as: CreatePerProcessRemote.self),
              let flatten = PrivateFramework.loaded.symbol("_CreateFlattenedInputSource", as: CreateFlattenedInputSource.self),
              let getPID = PrivateFramework.loaded.symbol("GetProcessPID", as: GetProcessPID.self) else { throw .missingSymbol }
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kNoProcess))
        var ignored: DarwinBoolean = false
        var pid: pid_t = 0
        guard getKeyFocus(&psn, &ignored) == .success, getPID(&psn, &pid) == noErr, pid > 0 else { throw .noFocusProcess }
        var flattened: Unmanaged<CFTypeRef>?
        guard flatten(source, &flattened).boolValue, let flattened else { throw .flattenFailed }
        let request = ["tsmInputSourceSelectedInpSrcKey": flattened.takeRetainedValue()] as CFDictionary
        guard let body = CFPropertyListCreateData(nil, request, .xmlFormat_v1_0, 0, nil)?.takeRetainedValue() else { throw .flattenFailed }
        guard let port = createRemote(nil, "com.apple.tsm.portname" as CFString, pid)?.takeRetainedValue() else { throw .noPort }
        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(port, selectInputSourceMessage, body, 0.5, 1.5, CFRunLoopMode.defaultMode.rawValue, &reply)
        guard status == kCFMessagePortSuccess else { throw .transport(status) }
        guard let data = reply?.takeRetainedValue(),
              let plist = try? PropertyListSerialization.propertyList(from: data as Data, format: nil) as? [String: Any],
              let result = plist["tsmInputModeReplyToServerErrorKey"] as? Int32 else { throw .rejected(Int32.min) }
        guard result == noErr else { throw .rejected(result) }
    }
}
