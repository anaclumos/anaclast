import AppKit

struct InstalledApp: Sendable, Hashable {
    let name: String
    let url: URL
    let bundleID: String?
}

@MainActor
final class AppIndex {
    private(set) var apps: [InstalledApp] = []
    private var watcher: FileWatcher?
    var onChange: (() -> Void)?

    nonisolated static let roots: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"),
    ]

    func start() {
        refresh()
        watcher = FileWatcher(paths: Self.roots.map(\.path), latency: 1) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        Task {
            let found = await Task.detached(priority: .utility) { Self.scan() }.value
            apps = found
            onChange?()
        }
    }

    nonisolated static func scan() -> [InstalledApp] {
        var seen = Set<String>()
        var result: [InstalledApp] = []
        for root in roots {
            for url in bundles(under: root, depth: 0) {
                let bundleID = Bundle(url: url)?.bundleIdentifier
                let key = bundleID ?? url.path
                guard seen.insert(key).inserted else { continue }
                let displayName = FileManager.default.displayName(atPath: url.path)
                let name = displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
                result.append(InstalledApp(name: name, url: url, bundleID: bundleID))
            }
        }
        return result
    }

    nonisolated private static func bundles(under url: URL, depth: Int) -> [URL] {
        if url.pathExtension == "app" { return [url] }
        guard depth < 3, let children = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return children.flatMap { child -> [URL] in
            let resolved = child.resolvingSymlinksInPath()
            guard (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return [] }
            return bundles(under: resolved, depth: depth + 1)
        }
    }
}

@MainActor
enum IconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(for url: URL) -> NSImage {
        if let cached = icons[url.path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[url.path] = icon
        return icon
    }
}
