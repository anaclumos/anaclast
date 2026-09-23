import CoreGraphics
import AnaclastCore

enum KeySender {
    static let marker: Int64 = 0x414E_4143

    static func post(_ chord: KeyChord) {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: chord.key.rawValue, keyDown: isDown) else { continue }
            event.flags = chord.modifiers.flags
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cgSessionEventTap)
        }
    }
}
