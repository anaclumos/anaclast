import AppKit
import AnaclastCore

@MainActor
final class ActionRunner {
    var tiles: [String: TileFrame] = [:]
    var onCommand: (Command) -> Void = { _ in }

    func run(_ actions: [Action]) {
        for action in actions { run(action) }
    }

    func run(_ action: Action) {
        switch action {
        case .open(let bundleID): AppLauncher.open(bundleID: bundleID)
        case .tile(let name): WindowManager.tile(name, tiles: tiles)
        case .inputSource(let id): InputSwitcher.select(id)
        case .keystroke(let chord): KeySender.post(chord)
        case .menu(let path): MenuInvoker.invoke(path)
        case .command(let command): run(command)
        case .window(let target): AppLauncher.focusOrLaunch(target)
        }
    }

    private func run(_ command: Command) {
        switch command {
        case .toggleDarkMode: SystemActions.toggleDarkMode()
        case .lockScreen: SystemActions.lockScreen()
        case .showDesktop: SystemActions.showDesktop()
        case .missionControl: SystemActions.missionControl()
        case .toggleCapsLock: SystemActions.toggleCapsLock()
        case .openDefaultBrowser: AppLauncher.openDefaultBrowser()
        case .launcher, .openSettings, .clipboardHistory, .applyMachineConfig, .reloadConfig, .quit: onCommand(command)
        }
    }
}
