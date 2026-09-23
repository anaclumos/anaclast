import AppKit
import Observation
import SwiftUI
import AnaclastCore

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    private static var model: SettingsModel?

    static func show(store: ConfigStore, choices: [ActionChoice], pane: SettingsPane = .general) {
        let model = self.model ?? SettingsModel(store: store)
        model.refresh(config: store.config, choices: choices)
        model.pane = pane
        self.model = model
        let window = self.window ?? makeWindow(model: model)
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.bringForward()
    }

    static func refresh(config: Config, choices: [ActionChoice]) {
        model?.refresh(config: config, choices: choices)
    }

    private static func makeWindow(model: SettingsModel) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
        window.title = "Anaclast Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(CGSize(width: 640, height: 600))
        window.center()
        return window
    }
}

@MainActor
@Observable
final class SettingsModel {
    private(set) var config: Config
    private(set) var choices: [ActionChoice] = []
    private(set) var error: String?
    var pane = SettingsPane.general
    @ObservationIgnored private let store: ConfigStore

    init(store: ConfigStore) {
        self.store = store
        config = store.config
    }

    func refresh(config: Config, choices: [ActionChoice]) {
        self.config = config
        self.choices = choices
    }

    func change(_ edit: (inout Config) throws -> Void) {
        do {
            try store.update(edit)
            config = store.config
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    func binding<Value>(_ keyPath: WritableKeyPath<Config, Value>) -> Binding<Value> {
        Binding(get: { self.config[keyPath: keyPath] }, set: { value in self.change { $0[keyPath: keyPath] = value } })
    }
}

struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $model.pane) {
                Tab("General", systemImage: "gearshape", value: SettingsPane.general) {
                    GeneralPane(model: model)
                }
                Tab("Hyper Keys", systemImage: "keyboard", value: SettingsPane.hyperKeys) {
                    HyperKeysPane(model: model)
                }
                Tab("Tiles", systemImage: "rectangle.split.2x1", value: SettingsPane.tiles) {
                    TilesPane(model: model)
                }
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .frame(minWidth: 560, minHeight: 480)
    }
}

private struct GeneralPane: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section("Caps Lock") {
                ActionPicker(title: "Tap action", selection: model.binding(\.hyper.tap), choices: model.choices)
                Stepper(value: model.binding(\.hyper.tapTimeoutMilliseconds), in: 50...2000, step: 10) {
                    LabeledContent("Tap timeout", value: "\(model.config.hyper.tapTimeoutMilliseconds) ms")
                }
            }
            Section("Command taps") {
                OptionalActionPicker(title: "Left ⌘ tap", selection: model.binding(\.modifierTaps.leftCommand), choices: model.choices)
                OptionalActionPicker(title: "Right ⌘ tap", selection: model.binding(\.modifierTaps.rightCommand), choices: model.choices)
                Stepper(value: model.binding(\.modifierTaps.timeoutMilliseconds), in: 50...2000, step: 10) {
                    LabeledContent("Tap timeout", value: "\(model.config.modifierTaps.timeoutMilliseconds) ms")
                }
            }
            Section("Clipboard") {
                Stepper(value: model.binding(\.clipboard.limit), in: 50...5000, step: 50) {
                    LabeledContent("History limit", value: "\(model.config.clipboard.limit) items")
                }
            }
            Section("Config file") {
                LabeledContent("Location") {
                    Text(ConfigStore.configURL.path(percentEncoded: false))
                        .textSelection(.enabled)
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.configURL.resolvingSymlinksInPath()])
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct HyperKeysPane: View {
    let model: SettingsModel
    @State private var newKey = ""
    @State private var newAction = Action.command(.launcher)

    var body: some View {
        Form {
            Section("Bindings") {
                ForEach(model.config.hyper.keys.keys.sorted(), id: \.self) { key in
                    HStack {
                        ActionPicker(title: "Hyper \(key.capitalized)", selection: binding(for: key), choices: model.choices)
                        Button("Remove", systemImage: "minus.circle") {
                            model.change { $0.hyper.keys[key] = nil }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
            }
            Section("Add a binding") {
                Picker("Key", selection: $newKey) {
                    Text("Choose a key").tag("")
                    ForEach(Config.hyperKeyNames.filter { model.config.hyper.keys[$0] == nil }, id: \.self) { name in
                        Text(name.capitalized).tag(name)
                    }
                }
                ActionPicker(title: "Action", selection: $newAction, choices: model.choices)
                Button("Add") {
                    model.change { $0.hyper.keys[newKey] = newAction }
                    newKey = ""
                }
                .disabled(newKey.isEmpty)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for key: String) -> Binding<Action> {
        Binding(get: { model.config.hyper.keys[key] ?? .command(.launcher) }, set: { value in model.change { $0.hyper.keys[key] = value } })
    }
}

private struct TilesPane: View {
    let model: SettingsModel
    @State private var newName = ""

    var body: some View {
        Form {
            Section("Tiles, as fractions of the screen") {
                ForEach(model.config.tiles.sorted { $0.key < $1.key }, id: \.key) { name, frame in
                    TileRow(model: model, name: name, frame: frame)
                }
            }
            Section("Add a tile") {
                TextField("Name", text: $newName)
                Button("Add") {
                    model.change { $0.tiles[newName] = TileFrame(x: 0, y: 0, w: 1, h: 1) }
                    newName = ""
                }
                .disabled(newName.isEmpty || model.config.tiles[newName] != nil)
            }
        }
        .formStyle(.grouped)
    }
}

private struct TileRow: View {
    let model: SettingsModel
    let name: String
    let frame: TileFrame
    @State private var draft: TileFrame

    init(model: SettingsModel, name: String, frame: TileFrame) {
        self.model = model
        self.name = name
        self.frame = frame
        _draft = State(initialValue: frame)
    }

    var body: some View {
        HStack {
            Text(name)
                .frame(minWidth: 140, alignment: .leading)
            ForEach(TileEdge.allCases, id: \.self) { edge in
                TextField(edge.rawValue, value: Binding(get: { edge.value(in: draft) }, set: { draft = edge.replacing(in: draft, with: $0) }), format: .number.precision(.fractionLength(0...4)))
                    .frame(width: 64)
            }
            Button("Save", systemImage: "checkmark.circle") { save() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            Button("Remove", systemImage: "minus.circle") {
                model.change { $0.tiles[name] = nil }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .onSubmit { save() }
        .onChange(of: frame) { draft = frame }
    }

    private func save() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        model.change { $0.tiles[name] = draft }
    }
}

private enum TileEdge: String, CaseIterable {
    case x, y, w, h

    func value(in frame: TileFrame) -> Double {
        switch self {
        case .x: frame.x
        case .y: frame.y
        case .w: frame.w
        case .h: frame.h
        }
    }

    func replacing(in frame: TileFrame, with value: Double) -> TileFrame {
        TileFrame(x: self == .x ? value : frame.x, y: self == .y ? value : frame.y, w: self == .w ? value : frame.w, h: self == .h ? value : frame.h)
    }
}

private struct ActionPicker: View {
    let title: String
    @Binding var selection: Action
    let choices: [ActionChoice]

    var body: some View {
        Picker(title, selection: $selection) {
            if !choices.contains(where: { $0.action == selection }) {
                Text(ActionChoice.describe(selection)).tag(selection)
            }
            ActionChoiceSections(choices: choices) { $0 }
        }
    }
}

private struct OptionalActionPicker: View {
    let title: String
    @Binding var selection: Action?
    let choices: [ActionChoice]

    var body: some View {
        Picker(title, selection: $selection) {
            Text("None").tag(Action?.none)
            if let selection, !choices.contains(where: { $0.action == selection }) {
                Text(ActionChoice.describe(selection)).tag(Action?.some(selection))
            }
            ActionChoiceSections(choices: choices) { Action?.some($0) }
        }
    }
}

private struct ActionChoiceSections<Tag: Hashable>: View {
    let choices: [ActionChoice]
    let tag: (Action) -> Tag

    var body: some View {
        ForEach(ActionChoice.Kind.allCases, id: \.self) { kind in
            let group = choices.filter { $0.kind == kind }
            if !group.isEmpty {
                Section(kind.rawValue) {
                    ForEach(group) { choice in
                        Text(choice.title).tag(tag(choice.action))
                    }
                }
            }
        }
    }
}
