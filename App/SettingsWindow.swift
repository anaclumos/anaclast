import AppKit
import Observation
import SwiftUI
import AnaclastCore

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    private static var tabs: NSTabViewController?
    private static var model: SettingsModel?

    static func show(store: ConfigStore, choices: [ActionChoice], pane: SettingsPane = .general) {
        let model = self.model ?? SettingsModel(store: store)
        model.refresh(config: store.config, choices: choices)
        self.model = model
        let tabs = self.tabs ?? makeTabs(model: model)
        self.tabs = tabs
        let window = self.window ?? makeWindow(tabs: tabs)
        self.window = window
        tabs.selectedTabViewItemIndex = SettingsPane.allCases.firstIndex(of: pane) ?? 0
        window.makeKeyAndOrderFront(nil)
        NSApp.bringForward()
    }

    static func refresh(config: Config, choices: [ActionChoice]) {
        model?.refresh(config: config, choices: choices)
    }

    private static func makeTabs(model: SettingsModel) -> NSTabViewController {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for pane in SettingsPane.allCases {
            let controller = NSHostingController(rootView: SettingsPaneView(pane: pane, model: model))
            controller.sizingOptions = .preferredContentSize
            controller.title = pane.title
            let item = NSTabViewItem(viewController: controller)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: nil)
            tabs.addTabViewItem(item)
        }
        return tabs
    }

    private static func makeWindow(tabs: NSTabViewController) -> NSWindow {
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

private extension SettingsPane {
    var title: String {
        String(localized: Self.caseDisplayRepresentations[self]?.title ?? "\(rawValue)")
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .hyperKeys: "keyboard"
        case .tiles: "rectangle.split.2x1"
        }
    }

    var height: CGFloat {
        switch self {
        case .general: 524
        case .hyperKeys, .tiles: 620
        }
    }
}

@MainActor
@Observable
final class SettingsModel {
    private(set) var config: Config
    private(set) var choices: [ActionChoice] = []
    private(set) var error: String?
    @ObservationIgnored private let store: ConfigStore

    init(store: ConfigStore) {
        self.store = store
        config = store.config
    }

    func refresh(config: Config, choices: [ActionChoice]) {
        self.config = config
        self.choices = choices
    }

    @discardableResult
    func change(_ edit: (inout Config) throws -> Void) -> Bool {
        do {
            try store.update(edit)
            config = store.config
            error = nil
            return true
        } catch {
            self.error = String(describing: error)
            return false
        }
    }

    func binding<Value>(_ keyPath: WritableKeyPath<Config, Value>) -> Binding<Value> {
        Binding(get: { self.config[keyPath: keyPath] }, set: { value in self.change { $0[keyPath: keyPath] = value } })
    }
}

private struct SettingsPaneView: View {
    let pane: SettingsPane
    let model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            switch pane {
            case .general: GeneralPane(model: model)
            case .hyperKeys: HyperKeysPane(model: model)
            case .tiles: TilesPane(model: model)
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
        }
        .frame(width: 560, height: pane.height)
    }
}

private struct GeneralPane: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section("Caps Lock") {
                ActionPicker(title: "Tap", selection: model.binding(\.hyper.tap), choices: model.choices)
                StepperRow(title: "Tap timeout", value: model.binding(\.hyper.tapTimeoutMilliseconds), range: 50...2000, step: 10, unit: "ms")
            }
            Section("Command") {
                OptionalActionPicker(title: "Tap left ⌘", selection: model.binding(\.modifierTaps.leftCommand), choices: model.choices)
                OptionalActionPicker(title: "Tap right ⌘", selection: model.binding(\.modifierTaps.rightCommand), choices: model.choices)
                StepperRow(title: "Tap timeout", value: model.binding(\.modifierTaps.timeoutMilliseconds), range: 50...2000, step: 10, unit: "ms")
            }
            Section("Clipboard") {
                Toggle("Keep all history", isOn: Binding(get: { model.config.clipboard.limit == nil }, set: { keepAll in model.change { $0.clipboard.limit = keepAll ? nil : 500 } }))
                if let limit = model.config.clipboard.limit {
                    StepperRow(title: "Keep the last", value: Binding(get: { limit }, set: { value in model.change { $0.clipboard.limit = value } }), range: 50...5000, step: 50, unit: "items")
                }
            }
            Section("Config file") {
                LabeledContent {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.configURL.resolvingSymlinksInPath()])
                    }
                } label: {
                    Text((ConfigStore.configURL.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct StepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text("\(value) \(unit)")
                    .monospacedDigit()
                Stepper(title, value: $value, in: range, step: step)
                    .labelsHidden()
            }
        }
    }
}

private struct HyperKeysPane: View {
    let model: SettingsModel
    @State private var newKey = ""
    @State private var newAction = Action.command(.launcher)

    var body: some View {
        Form {
            Section("Hold Caps Lock and press") {
                ForEach(model.config.hyper.keys.keys.sorted(by: KeyCap.order), id: \.self) { key in
                    LabeledContent {
                        HStack(spacing: 8) {
                            ActionPicker(title: "Hyper \(KeyCap.label(key))", selection: binding(for: key), choices: model.choices)
                                .labelsHidden()
                            RemoveButton { model.change { $0.hyper.keys[key] = nil } }
                        }
                    } label: {
                        KeyCap(name: key)
                    }
                }
            }
            Section("Add a key") {
                Picker("Key", selection: $newKey) {
                    Text("Choose a key").tag("")
                    ForEach(Config.hyperKeyNames.filter { model.config.hyper.keys[$0] == nil }.sorted(by: KeyCap.order), id: \.self) { name in
                        Text(KeyCap.label(name)).tag(name)
                    }
                }
                ActionPicker(title: "Action", selection: $newAction, choices: model.choices)
                LabeledContent {
                    Button("Add") {
                        model.change { $0.hyper.keys[newKey] = newAction }
                        newKey = ""
                    }
                    .disabled(newKey.isEmpty)
                } label: {
                    EmptyView()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for key: String) -> Binding<Action> {
        Binding(get: { model.config.hyper.keys[key] ?? .command(.launcher) }, set: { value in model.change { $0.hyper.keys[key] = value } })
    }
}

private struct KeyCap: View {
    let name: String

    var body: some View {
        Text(Self.label(name))
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 7)
            .frame(minWidth: 26, minHeight: 22)
            .background(.quaternary, in: .rect(cornerRadius: 6))
    }

    private static let glyphs = [
        "grave": "`", "minus": "-", "equal": "=", "leftbracket": "[", "rightbracket": "]", "backslash": "\\",
        "semicolon": ";", "quote": "'", "comma": ",", "period": ".", "slash": "/",
        "left": "←", "right": "→", "up": "↑", "down": "↓", "return": "↩", "enter": "⌤", "tab": "⇥",
        "delete": "⌫", "forwarddelete": "⌦", "escape": "esc", "space": "Space",
        "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟",
    ]

    static func label(_ name: String) -> String {
        glyphs[name] ?? (name.count == 1 ? name.uppercased() : name.capitalized)
    }

    static func order(_ lhs: String, _ rhs: String) -> Bool {
        func rank(_ name: String) -> (Int, String) {
            let cap = label(name)
            guard cap.count == 1, let glyph = cap.first else { return (2, cap) }
            return (glyph.isLetter || glyph.isNumber ? 0 : 1, cap)
        }
        return rank(lhs) < rank(rhs)
    }
}

private struct TilesPane: View {
    let model: SettingsModel
    @State private var newName = ""

    var body: some View {
        Form {
            Section("Share of the screen") {
                LabeledContent {
                    HStack(spacing: 6) {
                        ForEach(TileEdge.allCases, id: \.self) { edge in
                            Text(edge.title)
                                .frame(width: TileRow.fieldWidth, alignment: .trailing)
                        }
                        RemoveButton {}.hidden()
                    }
                } label: {
                    EmptyView()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(model.config.tiles.sorted { $0.key < $1.key }, id: \.key) { name, frame in
                    TileRow(model: model, name: name, frame: frame)
                }
            }
            Section("Add a tile") {
                TextField("Name", text: $newName)
                LabeledContent {
                    Button("Add") {
                        model.change { $0.tiles[newName] = TileFrame(x: 0, y: 0, w: 1, h: 1) }
                        newName = ""
                    }
                    .disabled(newName.isEmpty || model.config.tiles[newName] != nil)
                } label: {
                    EmptyView()
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct TileRow: View {
    static let fieldWidth: CGFloat = 56

    let model: SettingsModel
    let name: String
    let frame: TileFrame

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                ForEach(TileEdge.allCases, id: \.self) { edge in
                    PercentField(title: edge.title, value: edge.value(in: frame)) { value in
                        model.change { $0.tiles[name] = edge.replacing(in: frame, with: value) }
                    }
                }
                RemoveButton { model.change { $0.tiles[name] = nil } }
            }
        } label: {
            HStack(spacing: 10) {
                TilePreview(frame: frame)
                Text(name.replacingOccurrences(of: "-", with: " ").capitalized)
                    .lineLimit(1)
            }
        }
    }

}

// A value-bound TextField writes its binding on every keystroke, so typing 80 would save 8% first. The draft commits once, on Return or when focus leaves.
private struct PercentField: View {
    let title: String
    let value: Double
    let commit: (Double) -> Bool
    @State private var draft: Double
    @FocusState private var focused: Bool

    init(title: String, value: Double, commit: @escaping (Double) -> Bool) {
        self.title = title
        self.value = value
        self.commit = commit
        _draft = State(initialValue: value)
    }

    var body: some View {
        TextField(title, value: $draft, format: .percent.precision(.fractionLength(0...2)))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: TileRow.fieldWidth)
            .focused($focused)
            .onSubmit(save)
            .onChange(of: focused) { if !focused { save() } }
            .onChange(of: value) { draft = value }
    }

    private func save() {
        guard draft != value, !commit(draft) else { return }
        draft = value
    }
}

private struct TilePreview: View {
    let frame: TileFrame

    var body: some View {
        let size = CGSize(width: 32, height: 20)
        RoundedRectangle(cornerRadius: 3)
            .strokeBorder(.secondary, lineWidth: 1)
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.tint)
                    .frame(width: max(2, (size.width - 4) * frame.w), height: max(2, (size.height - 4) * frame.h))
                    .offset(x: 2 + (size.width - 4) * frame.x, y: 2 + (size.height - 4) * frame.y)
            }
            .frame(width: size.width, height: size.height)
    }
}

private enum TileEdge: CaseIterable {
    case x, y, w, h

    var title: String {
        switch self {
        case .x: "Left"
        case .y: "Top"
        case .w: "Width"
        case .h: "Height"
        }
    }

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

private struct RemoveButton: View {
    let action: () -> Void

    var body: some View {
        Button("Remove", systemImage: "minus.circle", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
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
