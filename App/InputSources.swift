import Carbon
import Foundation

struct InputSourceInfo: Sendable, Hashable {
    let id: String
    let name: String
}

enum InputSources {
    static func selectable() -> [InputSourceInfo] {
        sources().compactMap { source in
            guard let id = string(source, kTISPropertyInputSourceID), let name = string(source, kTISPropertyLocalizedName) else { return nil }
            return InputSourceInfo(id: id, name: name)
        }
    }

    static func source(id: String) -> TISInputSource? {
        sources().first { string($0, kTISPropertyInputSourceID) == id }
    }

    private static func sources() -> [TISInputSource] {
        let filter = [
            kTISPropertyInputSourceIsSelectCapable as String: true,
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        return list
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
