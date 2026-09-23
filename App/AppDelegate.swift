import AppIntents
import AppKit
import AnaclastCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ConfigStore?
    private let intents = IntentHost()
    private var choices: [ActionChoice] = []
    private var tap: EventTap?
    private let runner = ActionRunner()
    private let apps = AppIndex()
    private let hotkeys = SymbolicHotkeyGuard()
    private let launcherModel = LauncherModel()
    private let status = SystemStatus()
    private var launcherPanel: FloatingPanel?
    private var clipboardModel: ClipboardModel?
    private var clipboardPanel: FloatingPanel?
    private var trustTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var termination: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if LoginAgent.handOffIfNeeded() {
            NSApp.terminate(nil)
            return
        }
        let intents = self.intents
        AppDependencyManager.shared.add(dependency: intents)
        CapsRemap.reset()
        quitOnTermination()
        let store: ConfigStore
        do {
            store = try ConfigStore()
        } catch {
            fail("Anaclast could not load \(ConfigStore.configURL.path)", detail: String(describing: error), quitting: true)
            return
        }
        self.store = store
        let config = store.config
        let keymap: Keymap
        do {
            keymap = try Keymap(config: config)
        } catch {
            fail("Anaclast config is invalid", detail: error.description, quitting: true)
            return
        }
        runner.tiles = config.tiles
        runner.onCommand = { [weak self] in self?.handle($0) }
        setUpIntents()
        tap = EventTap(keymap: keymap) { [weak self] actions in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.runner.run(actions) }
            }
        }
        trackFrontmostApp()
        setUpLauncher()
        setUpClipboard(limit: config.clipboard.limit)
        apps.onChange = { [weak self] in self?.refreshCatalog() }
        apps.start()
        hotkeys.start(disabling: config.disabledSymbolicHotkeys)
        store.onChange = { [weak self] in self?.apply($0) }
        store.onError = { [weak self] in self?.fail("Anaclast kept the previous config", detail: $0) }
        store.watch()
        startKeyboard()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if CapsRemap.isApplied { CapsRemap.reset() }
    }

    private func quitOnTermination() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
        source.resume()
        termination = source
    }

    private func startKeyboard() {
        guard AX.isTrusted else {
            AX.requestTrust()
            trustTimer?.invalidate()
            trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, AX.isTrusted else { return }
                    self.trustTimer?.invalidate()
                    self.startKeyboard()
                }
            }
            return
        }
        tap?.start {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { CapsRemap.apply() }
            }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { CapsRemap.reapply() }
        })
    }

    private func trackFrontmostApp() {
        tap?.setFrontmostApp(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated { self?.tap?.setFrontmostApp(bundleID) }
        })
    }

    private func setUpLauncher() {
        let panel = FloatingPanel(size: CGSize(width: 720, height: 460)) { LauncherView(model: launcherModel, status: status) }
        panel.onHide = { [status] in status.stop() }
        launcherModel.dismiss = { [weak panel] in panel?.hide() }
        launcherModel.perform = { [weak self] item in self?.perform(item) }
        launcherPanel = panel
    }

    private func setUpClipboard(limit: Int) {
        let history = ClipboardHistory(limit: limit)
        history.start()
        let model = ClipboardModel(history: history)
        let panel = FloatingPanel(size: CGSize(width: 760, height: 480)) { ClipboardView(model: model) }
        model.dismiss = { [weak panel] in panel?.hide() }
        model.paste = { entry in
            history.copy(entry)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                KeySender.post(KeyChord(key: .v, modifiers: .command))
            }
        }
        clipboardModel = model
        clipboardPanel = panel
    }

    private func setUpIntents() {
        intents.run = { [weak self] in self?.runner.run($0) }
        intents.openSettings = { [weak self] in self?.showSettings($0) }
        intents.search = { [weak self] in self?.showLauncher(query: $0) }
        intents.choices = { [weak self] in self?.choices ?? [] }
        intents.update = { [weak self] change in
            guard let store = self?.store else { throw IntentFailure(message: "Anaclast has no config loaded.") }
            try store.update(change)
        }
    }

    private func refreshCatalog() {
        guard let config = store?.config, let keymap = try? Keymap(config: config) else { return }
        let items = Catalog.items(apps: apps.apps, config: config, keymap: keymap)
        choices = Catalog.choices(from: items)
        launcherModel.update(items: items)
        SettingsWindow.refresh(config: config, choices: choices)
        AnaclastShortcuts.updateAppShortcutParameters()
    }

    private func showLauncher(query: String) {
        guard let panel = launcherPanel else { return }
        clipboardPanel?.hide()
        if !panel.isShown {
            launcherModel.presented()
            status.start()
            panel.show()
        }
        launcherModel.query = query
        launcherModel.refresh()
    }

    private func showSettings(_ pane: SettingsPane) {
        guard let store else { return }
        launcherPanel?.hide()
        SettingsWindow.show(store: store, choices: choices, pane: pane)
    }

    private func apply(_ config: Config) {
        do {
            let keymap = try Keymap(config: config)
            tap?.replace(keymap: keymap)
        } catch {
            fail("Anaclast kept the previous keymap", detail: error.description)
            return
        }
        runner.tiles = config.tiles
        clipboardModel?.history.limit = config.clipboard.limit
        hotkeys.start(disabling: config.disabledSymbolicHotkeys)
        refreshCatalog()
    }

    private func perform(_ item: LauncherItem) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                switch item.target {
                case .app(let url): AppLauncher.open(url: url)
                case .action(let action): self?.runner.run(action)
                }
            }
        }
    }

    private func handle(_ command: Command) {
        switch command {
        case .launcher:
            guard let panel = launcherPanel else { return }
            if !panel.isShown {
                launcherModel.presented()
                status.start()
            }
            clipboardPanel?.hide()
            panel.toggle()
        case .clipboardHistory:
            guard let panel = clipboardPanel else { return }
            if !panel.isShown { clipboardModel?.presented() }
            launcherPanel?.hide()
            panel.toggle()
        case .openSettings:
            showSettings(.general)
        case .applyMachineConfig:
            MachineWindow.show()
        case .reloadConfig:
            store?.reload()
        case .quit:
            NSApp.terminate(nil)
        default:
            runner.run(.command(command))
        }
    }

    private func fail(_ message: String, detail: String, quitting: Bool = false) {
        log.error("\(message, privacy: .public): \(detail, privacy: .public)")
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated {
                let alert = NSAlert()
                alert.messageText = message
                alert.informativeText = detail
                NSApp.activate()
                alert.runModal()
                if quitting { NSApp.terminate(nil) }
            }
        }
    }
}
