import AppKit
import AnaclastCore

@MainActor
enum Catalog {
    static func items(apps: [InstalledApp], config: Config, keymap: Keymap) -> [LauncherItem] {
        let hints = hintTable(config: config, keymap: keymap)
        let titles = Dictionary(apps.map { ($0.name, 1) }, uniquingKeysWith: +)
        var items = apps.map { app in
            LauncherItem(
                id: "app:\(app.bundleID ?? app.url.path)",
                title: app.name,
                subtitle: titles[app.name, default: 0] > 1 ? app.url.lastPathComponent : "",
                keywords: [app.url.deletingPathExtension().lastPathComponent],
                icon: .file(app.url),
                target: .app(app.url),
                hint: app.bundleID.flatMap { hints[.open(bundleID: $0)] }
            )
        }
        for command in Command.allCases where command != .launcher {
            let action = Action.command(command)
            items.append(LauncherItem(id: "command:\(command.rawValue)", title: command.title, subtitle: "", keywords: command.keywords, icon: .symbol(command.symbol), target: .action(action), hint: hints[action]))
        }
        let tileNames = config.tiles.keys.sorted() + [Config.fullscreenTile]
        for name in tileNames {
            let action = Action.tile(name)
            let words = name.replacing("-", with: " ")
            let title = name == Config.fullscreenTile ? "Toggle Full Screen" : "Tile \(words.capitalized)"
            items.append(LauncherItem(id: "tile:\(name)", title: title, subtitle: "Window", keywords: [words, "window \(words)"], icon: .symbol("macwindow"), target: .action(action), hint: hints[action]))
        }
        var windows = Set<WindowTarget>()
        for case .window(let target) in config.boundActions where windows.insert(target).inserted {
            let action = Action.window(target)
            let icon: LauncherItem.Icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.app).map { .file($0) } ?? .symbol("macwindow")
            items.append(LauncherItem(id: "window:\(target.name)", title: target.name, subtitle: "", keywords: [], icon: icon, target: .action(action), hint: hints[action]))
        }
        for source in InputSources.selectable() {
            let action = Action.inputSource(source.id)
            items.append(LauncherItem(id: "input:\(source.id)", title: "Switch to \(source.name)", subtitle: "Input Source", keywords: ["input", "keyboard", source.name], icon: .symbol("keyboard"), target: .action(action), hint: hints[action]))
        }
        return items
    }

    static func choices(from items: [LauncherItem]) -> [ActionChoice] {
        let launcher = ActionChoice(id: "command:\(Command.launcher.rawValue)", title: Command.launcher.title, kind: .command, action: .command(.launcher))
        return [launcher] + items.compactMap { item in
            switch item.target {
            case .action(let action):
                ActionChoice(id: item.id, title: item.title, kind: ActionChoice.Kind(action), action: action)
            case .app(let url):
                Bundle(url: url)?.bundleIdentifier.map { ActionChoice(id: item.id, title: item.title, kind: .app, action: .open(bundleID: $0)) }
            }
        }
    }

    static func hintTable(config: Config, keymap: Keymap) -> [Action: String] {
        var hints: [Action: String] = [:]
        hints[config.hyper.tap] = "⇪ tap"
        for (key, action) in keymap.hyperBindings where hints[action] == nil {
            hints[action] = "Hyper \(key.description.capitalized)"
        }
        for (chord, app, action) in keymap.shortcutBindings where app == nil && hints[action] == nil {
            hints[action] = chord.description
        }
        if let left = config.modifierTaps.leftCommand, hints[left] == nil { hints[left] = "Left ⌘ tap" }
        if let right = config.modifierTaps.rightCommand, hints[right] == nil { hints[right] = "Right ⌘ tap" }
        return hints
    }
}

struct ActionChoice: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case tile = "Windows"
        case command = "Commands"
        case inputSource = "Input Sources"
        case app = "Apps"
        case other = "Other"

        init(_ action: Action) {
            switch action {
            case .tile: self = .tile
            case .command: self = .command
            case .inputSource: self = .inputSource
            case .open, .window: self = .app
            case .keystroke, .menu: self = .other
            }
        }
    }

    let id: String
    let title: String
    let kind: Kind
    let action: Action

    static func describe(_ action: Action) -> String {
        switch action {
        case .open(let bundleID): "Open \(bundleID)"
        case .tile(let name): "Tile \(name)"
        case .inputSource(let id): "Switch to \(id)"
        case .keystroke(let chord): "Press \(chord)"
        case .menu(let path): "Menu \(path.joined(separator: " > "))"
        case .command(let command): command.title
        case .window(let target): target.name
        }
    }
}

extension Command {
    var title: String {
        switch self {
        case .launcher: "Open Launcher"
        case .openSettings: "Anaclast Settings"
        case .clipboardHistory: "Clipboard History"
        case .toggleDarkMode: "Toggle Dark Mode"
        case .lockScreen: "Lock Screen"
        case .showDesktop: "Show Desktop"
        case .missionControl: "Mission Control"
        case .toggleCapsLock: "Toggle Caps Lock"
        case .openDefaultBrowser: "Open Default Browser"
        case .applyMachineConfig: "Apply Machine Config"
        case .reloadConfig: "Reload Config"
        case .quit: "Quit Anaclast"
        }
    }

    var symbol: String {
        switch self {
        case .launcher: "command"
        case .openSettings: "gearshape"
        case .clipboardHistory: "list.clipboard"
        case .toggleDarkMode: "circle.lefthalf.filled"
        case .lockScreen: "lock"
        case .showDesktop: "menubar.dock.rectangle"
        case .missionControl: "rectangle.3.group"
        case .toggleCapsLock: "capslock"
        case .openDefaultBrowser: "globe"
        case .applyMachineConfig: "gearshape.2"
        case .reloadConfig: "arrow.clockwise"
        case .quit: "power"
        }
    }

    var keywords: [String] {
        switch self {
        case .openSettings: ["preferences", "config", "hyper"]
        case .toggleDarkMode: ["appearance", "theme", "light"]
        case .lockScreen: ["sleep", "screen"]
        case .clipboardHistory: ["paste", "copy"]
        case .openDefaultBrowser: ["web", "internet"]
        case .applyMachineConfig: ["brew", "defaults", "dotfiles", "setup"]
        default: []
        }
    }
}
