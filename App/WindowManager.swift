import AppKit
import ApplicationServices
import AnaclastCore

@MainActor
enum WindowManager {
    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        return AX.child(element, kAXFocusedWindowAttribute) ?? AX.child(element, kAXMainWindowAttribute)
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let origin = AX.point(window, kAXPositionAttribute), let size = AX.size(window, kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func visibleAreas() -> [CGRect] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        return NSScreen.screens.map { Tiling.flipped($0.visibleFrame, primaryHeight: primaryHeight) }
    }

    static func tile(_ name: String, tiles: [String: TileFrame]) {
        guard AX.isTrusted, let window = focusedWindow() else { return }
        let isFullScreen = AX.bool(window, "AXFullScreen") ?? false
        if name == Config.fullscreenTile {
            AX.set(window, "AXFullScreen", (!isFullScreen) as CFBoolean)
            return
        }
        guard !isFullScreen, let tile = tiles[name], let current = frame(of: window) else { return }
        let areas = visibleAreas()
        guard let index = Tiling.screenIndex(for: current, among: areas) else { return }
        let target = Tiling.frame(for: tile, in: areas[index])
        AX.set(window, size: target.size)
        AX.set(window, position: target.origin)
        AX.set(window, size: target.size)
    }
}
