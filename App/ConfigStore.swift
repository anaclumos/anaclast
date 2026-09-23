import Foundation
import OSLog
import AnaclastCore

let log = Logger(subsystem: "com.anaclumos.anaclast", category: "anaclast")

@MainActor
final class ConfigStore {
    static let directory: URL = {
        guard let path = Bundle.main.object(forInfoDictionaryKey: "AnaclastConfigDirectory") as? String, !path.isEmpty else {
            fatalError("Info.plist is missing AnaclastConfigDirectory")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }()

    static var configURL: URL { directory.appending(path: "anaclast.json") }

    private(set) var config: Config
    private var watcher: FileWatcher?
    var onChange: ((Config) -> Void)?
    var onError: ((String) -> Void)?

    init() throws {
        config = try Config.load(from: Self.configURL)
    }

    func reload(onlyIfChanged: Bool = false) {
        do {
            let loaded = try Config.load(from: Self.configURL)
            guard !onlyIfChanged || loaded != config else { return }
            config = loaded
            log.info("config reloaded")
            onChange?(config)
        } catch {
            log.error("config reload failed: \(String(describing: error), privacy: .public)")
            onError?(String(describing: error))
        }
    }

    func update(_ change: (inout Config) throws -> Void) throws {
        config = try ConfigFile.update(at: Self.configURL, change)
        log.info("config updated")
        onChange?(config)
    }

    func watch() {
        let config = Self.configURL.resolvingSymlinksInPath().path
        watcher = FileWatcher(paths: [Self.directory.path], latency: 0.3) { [weak self] changed in
            guard changed.contains(where: { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == config }) else { return }
            self?.reload(onlyIfChanged: true)
        }
    }
}
