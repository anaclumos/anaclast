import AppIntents
import AnaclastCore

@MainActor
final class IntentHost {
    var run: (Action) -> Void = { _ in }
    var openSettings: (SettingsPane) -> Void = { _ in }
    var search: (String) -> Void = { _ in }
    var choices: () -> [ActionChoice] = { [] }
    var update: ((inout Config) throws -> Void) throws -> Void = { _ in throw IntentFailure(message: "Anaclast is still starting.") }

    func change(_ edit: (inout Config) throws -> Void) throws {
        do {
            try update(edit)
        } catch let failure as IntentFailure {
            throw failure
        } catch {
            throw IntentFailure(message: String(describing: error))
        }
    }

    func choice(for entity: ActionEntity) throws -> ActionChoice {
        guard let choice = choices().first(where: { $0.id == entity.id }) else {
            throw IntentFailure(message: "\(entity.title) is no longer available.")
        }
        return choice
    }
}

struct IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

enum SettingsPane: String, AppEnum {
    case general
    case hyperKeys
    case tiles

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Settings Pane"
    static let caseDisplayRepresentations: [SettingsPane: DisplayRepresentation] = [
        .general: "General",
        .hyperKeys: "Hyper Keys",
        .tiles: "Tiles",
    ]
}

enum TapTimer: String, AppEnum {
    case capsLock
    case command

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tap Timer"
    static let caseDisplayRepresentations: [TapTimer: DisplayRepresentation] = [
        .capsLock: "Caps Lock",
        .command: "Command",
    ]
}

enum TapKey: String, AppEnum {
    case capsLock
    case leftCommand
    case rightCommand

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tap Key"
    static let caseDisplayRepresentations: [TapKey: DisplayRepresentation] = [
        .capsLock: "Caps Lock",
        .leftCommand: "Left Command",
        .rightCommand: "Right Command",
    ]
}

struct ActionEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Anaclast Action"
    static let defaultQuery = ActionEntityQuery()

    let id: String
    let title: String
    let kind: String

    init(_ choice: ActionChoice) {
        id = choice.id
        title = choice.title
        kind = choice.kind.rawValue
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(kind)")
    }
}

struct ActionEntityQuery: EnumerableEntityQuery, EntityStringQuery {
    @Dependency var host: IntentHost

    @MainActor
    func entities(for identifiers: [ActionEntity.ID]) async throws -> [ActionEntity] {
        host.choices().filter { identifiers.contains($0.id) }.map(ActionEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [ActionEntity] {
        host.choices().filter { $0.title.localizedStandardContains(string) }.map(ActionEntity.init)
    }

    @MainActor
    func allEntities() async throws -> [ActionEntity] {
        host.choices().map(ActionEntity.init)
    }
}

struct HyperKeyEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Hyper Key"
    static let defaultQuery = HyperKeyQuery()

    let id: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id.capitalized)")
    }
}

struct HyperKeyQuery: EnumerableEntityQuery {
    func entities(for identifiers: [HyperKeyEntity.ID]) async throws -> [HyperKeyEntity] {
        identifiers.filter { KeyCode(name: $0)?.isHyperSource == false }.map(HyperKeyEntity.init)
    }

    func allEntities() async throws -> [HyperKeyEntity] {
        Config.hyperKeyNames.map(HyperKeyEntity.init)
    }
}

struct OpenSettingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Anaclast Settings"
    static let description = IntentDescription("Opens the Anaclast settings window.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Pane", default: .general)
    var pane: SettingsPane

    @Dependency var host: IntentHost

    static var parameterSummary: some ParameterSummary {
        Summary("Open the \(\.$pane) settings")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        host.openSettings(pane)
        return .result()
    }
}

struct RunActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Anaclast Action"
    static let description = IntentDescription("Runs anything the Anaclast launcher can run: tiling the front window, opening an app, switching the input source or a command.")

    @Parameter(title: "Action")
    var target: ActionEntity

    @Dependency var host: IntentHost

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$target)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let choice = try host.choice(for: target)
        host.run(choice.action)
        return .result(dialog: "Ran \(choice.title).")
    }
}

struct SetTapTimeoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Anaclast Tap Timeout"
    static let description = IntentDescription("Sets how long a Caps Lock or Command press can last and still count as a tap.")

    @Parameter(title: "Tap", default: .capsLock)
    var timer: TapTimer

    @Parameter(title: "Milliseconds", inclusiveRange: (50, 2000))
    var milliseconds: Int

    @Dependency var host: IntentHost

    static var parameterSummary: some ParameterSummary {
        Summary("Set the \(\.$timer) tap timeout to \(\.$milliseconds) ms")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try host.change { config in
            switch timer {
            case .capsLock: config.hyper.tapTimeoutMilliseconds = milliseconds
            case .command: config.modifierTaps.timeoutMilliseconds = milliseconds
            }
        }
        return .result(dialog: "The tap timeout is now \(milliseconds) ms.")
    }
}

struct SetTapActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Anaclast Tap Action"
    static let description = IntentDescription("Sets what a Caps Lock, left Command or right Command tap does.")

    @Parameter(title: "Tap")
    var tap: TapKey

    @Parameter(title: "Action")
    var action: ActionEntity

    @Dependency var host: IntentHost

    static var parameterSummary: some ParameterSummary {
        Summary("Make a \(\.$tap) tap run \(\.$action)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let choice = try host.choice(for: action)
        try host.change { config in
            switch tap {
            case .capsLock: config.hyper.tap = choice.action
            case .leftCommand: config.modifierTaps.leftCommand = choice.action
            case .rightCommand: config.modifierTaps.rightCommand = choice.action
            }
        }
        return .result(dialog: "The tap now runs \(choice.title).")
    }
}

struct BindHyperKeyIntent: AppIntent {
    static let title: LocalizedStringResource = "Bind Anaclast Hyper Key"
    static let description = IntentDescription("Binds Caps Lock plus a key to an Anaclast action.")

    @Parameter(title: "Key")
    var key: HyperKeyEntity

    @Parameter(title: "Action")
    var action: ActionEntity

    @Dependency var host: IntentHost

    static var parameterSummary: some ParameterSummary {
        Summary("Bind Hyper \(\.$key) to \(\.$action)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let choice = try host.choice(for: action)
        try host.change { config in
            config.hyper.keys = config.hyper.keys.filter { KeyCode(name: $0.key) != KeyCode(name: key.id) }
            config.hyper.keys[key.id] = choice.action
        }
        return .result(dialog: "Hyper \(key.id.capitalized) now runs \(choice.title).")
    }
}

struct UnbindHyperKeyIntent: AppIntent {
    static let title: LocalizedStringResource = "Unbind Anaclast Hyper Key"
    static let description = IntentDescription("Removes the action bound to Caps Lock plus a key.")

    @Parameter(title: "Key")
    var key: HyperKeyEntity

    @Dependency var host: IntentHost

    static var parameterSummary: some ParameterSummary {
        Summary("Unbind Hyper \(\.$key)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try host.change { config in
            let bound = config.hyper.keys.filter { KeyCode(name: $0.key) == KeyCode(name: key.id) }
            guard !bound.isEmpty else { throw IntentFailure(message: "Hyper \(key.id.capitalized) is not bound.") }
            config.hyper.keys = config.hyper.keys.filter { bound[$0.key] == nil }
        }
        return .result(dialog: "Hyper \(key.id.capitalized) is unbound.")
    }
}

struct SetClipboardLimitIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Anaclast Clipboard Limit"
    static let description = IntentDescription("Sets how many items the clipboard history keeps.")

    @Parameter(title: "Items", inclusiveRange: (50, 5000))
    var limit: Int

    @Dependency var host: IntentHost

    static var parameterSummary: some ParameterSummary {
        Summary("Keep \(\.$limit) clipboard items")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try host.change { $0.clipboard.limit = limit }
        return .result(dialog: "Clipboard history now keeps \(limit) items.")
    }
}

struct SettingsPaneEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Anaclast Settings Pane"
    static let defaultQuery = SettingsPaneQuery()

    let pane: SettingsPane

    var id: String { pane.rawValue }

    var displayRepresentation: DisplayRepresentation {
        SettingsPane.caseDisplayRepresentations[pane] ?? DisplayRepresentation(title: "\(pane.rawValue)")
    }
}

struct SettingsPaneQuery: EnumerableEntityQuery {
    func entities(for identifiers: [SettingsPaneEntity.ID]) async throws -> [SettingsPaneEntity] {
        identifiers.compactMap(SettingsPane.init(rawValue:)).map(SettingsPaneEntity.init)
    }

    func allEntities() async throws -> [SettingsPaneEntity] {
        SettingsPane.allCases.map(SettingsPaneEntity.init)
    }
}

@AppIntent(schema: .system.open)
struct OpenSettingsPaneIntent: OpenIntent {
    var target: SettingsPaneEntity

    @Dependency var host: IntentHost

    @MainActor
    func perform() async throws -> some IntentResult {
        host.openSettings(target.pane)
        return .result()
    }
}

@AppIntent(schema: .system.searchInApp)
struct SearchLauncherIntent: ShowInAppSearchResultsIntent {
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @Dependency var host: IntentHost

    @MainActor
    func perform() async throws -> some IntentResult {
        host.search(criteria.term)
        return .result()
    }
}

struct AnaclastShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenSettingsIntent(),
            phrases: ["Open \(.applicationName) settings", "Show \(.applicationName) settings", "Open \(.applicationName) \(\.$pane) settings"],
            shortTitle: "Settings",
            systemImageName: "gearshape"
        )
        AppShortcut(
            intent: RunActionIntent(),
            phrases: ["\(.applicationName) \(\.$target)", "Run \(\.$target) with \(.applicationName)", "Run an \(.applicationName) action"],
            shortTitle: "Run Action",
            systemImageName: "bolt"
        )
        AppShortcut(
            intent: SetTapTimeoutIntent(),
            phrases: ["Set the \(\.$timer) tap timeout in \(.applicationName)", "Change the \(.applicationName) tap timeout"],
            shortTitle: "Tap Timeout",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: SetTapActionIntent(),
            phrases: ["Change the \(\.$tap) tap in \(.applicationName)", "Change what a tap does in \(.applicationName)"],
            shortTitle: "Tap Action",
            systemImageName: "hand.tap"
        )
        AppShortcut(
            intent: BindHyperKeyIntent(),
            phrases: ["Bind Hyper \(\.$key) in \(.applicationName)", "Bind a Hyper key in \(.applicationName)"],
            shortTitle: "Bind Hyper Key",
            systemImageName: "keyboard"
        )
        AppShortcut(
            intent: UnbindHyperKeyIntent(),
            phrases: ["Unbind Hyper \(\.$key) in \(.applicationName)", "Unbind a Hyper key in \(.applicationName)"],
            shortTitle: "Unbind Hyper Key",
            systemImageName: "keyboard.badge.ellipsis"
        )
        AppShortcut(
            intent: SetClipboardLimitIntent(),
            phrases: ["Set the \(.applicationName) clipboard limit", "Change the \(.applicationName) clipboard size"],
            shortTitle: "Clipboard Limit",
            systemImageName: "list.clipboard"
        )
    }
}
