import AppKit
import ApplicationServices

@MainActor
enum MenuInvoker {
    @discardableResult
    static func invoke(_ path: [String]) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let menuBar = AX.child(AXUIElementCreateApplication(app.processIdentifier), kAXMenuBarAttribute) else { return false }
        var container = menuBar
        for (depth, title) in path.enumerated() {
            let items = depth == 0 ? AX.children(container) : AX.children(container).flatMap { AX.children($0) }
            guard let item = items.first(where: { AX.string($0, kAXTitleAttribute) == title }) else {
                log.notice("menu item \(title, privacy: .public) not found")
                return false
            }
            if depth == path.count - 1 {
                guard AX.bool(item, kAXEnabledAttribute) != false else { return false }
                return AX.press(item)
            }
            container = item
        }
        return false
    }
}
