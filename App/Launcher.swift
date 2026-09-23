import AppKit
import Observation
import SwiftUI
import AnaclastCore

struct LauncherItem: Identifiable, Hashable, Sendable {
    enum Icon: Hashable, Sendable {
        case file(URL)
        case symbol(String)
    }

    enum Target: Hashable, Sendable {
        case app(URL)
        case action(Action)
    }

    let id: String
    let title: String
    let subtitle: String
    let keywords: [String]
    let icon: Icon
    let target: Target
    let hint: String?
}

@MainActor
@Observable
final class LauncherModel {
    var query = ""
    var selection = 0
    private(set) var results: [SearchHit<LauncherItem>] = []
    private(set) var presentation = 0
    private var items: [LauncherItem] = []
    @ObservationIgnored private var uses: [String: Int]
    @ObservationIgnored private let searcher = Searcher()
    @ObservationIgnored var perform: (LauncherItem) -> Void = { _ in }
    @ObservationIgnored var dismiss: () -> Void = {}

    static let usesKey = "launcherUses"

    init() {
        uses = UserDefaults.standard.dictionary(forKey: Self.usesKey)?.compactMapValues { $0 as? Int } ?? [:]
    }

    func update(items: [LauncherItem]) {
        self.items = items
        refresh()
    }

    func presented() {
        query = ""
        presentation += 1
        refresh()
    }

    var browsing: Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func refresh() {
        results = browsing ? [] : searcher.rank(items, query: query, title: \.title, keywords: \.keywords) { [uses] in uses[$0.id] ?? 0 }
        selection = 0
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    var selected: LauncherItem? {
        results.indices.contains(selection) ? results[selection].item : nil
    }

    func activate() {
        guard let item = selected else { return }
        uses[item.id, default: 0] += 1
        UserDefaults.standard.set(uses, forKey: Self.usesKey)
        dismiss()
        perform(item)
    }
}

struct LauncherView: View {
    @Bindable var model: LauncherModel
    let status: SystemStatus
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search apps and commands", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($searchFocused)
                    .onSubmit { model.activate() }
                    .onKeyPress(.upArrow) { model.move(-1); return .handled }
                    .onKeyPress(.downArrow) { model.move(1); return .handled }
                    .onKeyPress(.escape) { model.dismiss(); return .handled }
            }
            .padding(.horizontal, 20)
            .frame(height: 58)
            Divider()
            if model.browsing {
                BentoGrid(status: status)
            } else {
                ResultList(model: model)
            }
        }
        .containerShape(.rect(cornerRadius: IslandShape.bottomRadius))
        .onChange(of: model.query) { model.refresh() }
        .onChange(of: model.presentation, initial: true) { searchFocused = true }
    }
}

private struct ResultList: View {
    @Bindable var model: LauncherModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.element.item.id) { index, hit in
                        ResultRow(hit: hit, selected: index == model.selection)
                            .id(hit.item.id)
                            .contentShape(.rect)
                            .onTapGesture {
                                model.selection = index
                                model.activate()
                            }
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selection) {
                guard let item = model.selected else { return }
                proxy.scrollTo(item.id)
            }
        }
    }
}

private struct ResultRow: View {
    let hit: SearchHit<LauncherItem>
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ItemIcon(icon: hit.item.icon)
                .frame(width: 26, height: 26)
            Text(highlighted)
                .font(.system(size: 14))
                .lineLimit(1)
            Text(hit.item.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 12)
            if let hint = hit.item.hint {
                Text(hint)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text(kind)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .frame(height: 40)
        .background {
            if selected {
                Rectangle().fill(.primary.opacity(0.1))
            }
        }
    }

    private var kind: String {
        if case .app = hit.item.target { return "Application" }
        return "Command"
    }

    private var highlighted: AttributedString {
        var text = AttributedString(hit.item.title)
        for range in hit.highlights {
            guard let lower = AttributedString.Index(range.lowerBound, within: text),
                  let upper = AttributedString.Index(range.upperBound, within: text) else { continue }
            text[lower..<upper].font = .system(size: 14, weight: .bold)
        }
        return text
    }
}

struct ItemIcon: View {
    let icon: LauncherItem.Icon

    var body: some View {
        switch icon {
        case .file(let url):
            Image(nsImage: IconCache.icon(for: url))
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 26, height: 26)
                .background(.quaternary, in: .rect(cornerRadius: 6))
        }
    }
}
