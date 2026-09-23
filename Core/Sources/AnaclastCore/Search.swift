import Foundation
import FuzzyMatch

public struct SearchHit<Item: Sendable>: Sendable {
    public let item: Item
    public let score: Double
    public let highlights: [Range<String.Index>]
}

public struct Searcher: Sendable {
    private let matcher = FuzzyMatcher(config: .smithWaterman)

    public init() {}

    public func rank<Item: Sendable>(
        _ items: [Item],
        query: String,
        title: (Item) -> String,
        keywords: (Item) -> [String] = { _ in [] },
        uses: (Item) -> Int = { _ in 0 }
    ) -> [SearchHit<Item>] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return items
                .map { SearchHit(item: $0, score: 0, highlights: []) }
                .sorted { lhs, rhs in
                    let left = uses(lhs.item), right = uses(rhs.item)
                    return left != right ? left > right : title(lhs.item).localizedStandardCompare(title(rhs.item)) == .orderedAscending
                }
        }
        let prepared = matcher.prepare(trimmed)
        var buffer = matcher.makeBuffer()
        var scored: [(item: Item, score: Double, prefix: Int, order: Int, titleMatched: Bool)] = []
        for (order, item) in items.enumerated() {
            let text = title(item)
            let titleScore = matcher.score(text, against: prepared, buffer: &buffer)?.score
            let keywordScore = keywords(item).compactMap { matcher.score($0, against: prepared, buffer: &buffer)?.score }.max()
            guard let best = [titleScore, keywordScore.map { $0 * 0.9 }].compactMap({ $0 }).max() else { continue }
            let boost = min(Double(uses(item)), 50) * 0.002
            let prefix = text.range(of: trimmed, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) == nil ? 0 : 1
            scored.append((item, best + boost, prefix, order, titleScore != nil))
        }
        return scored.sorted { ($0.score, $0.prefix, -$0.order) > ($1.score, $1.prefix, -$1.order) }.prefix(Self.limit).map { entry in
            let highlights = entry.titleMatched ? matcher.highlight(title(entry.item), against: prepared) ?? [] : []
            return SearchHit(item: entry.item, score: entry.score, highlights: highlights)
        }
    }

    static let limit = 60
}
