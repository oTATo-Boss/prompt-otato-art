import Foundation

enum PromptLibrarySort: String, CaseIterable, Identifiable {
    case updated, used, created, title, manual

    var id: String { rawValue }
    var name: String {
        switch self {
        case .updated: "编辑时间"
        case .used: "使用时间"
        case .created: "创建时间"
        case .title: "名称"
        case .manual: "手动排序"
        }
    }

    func sorted(_ prompts: [Prompt], direction: PromptLibrarySortDirection) -> [Prompt] {
        prompts.sorted { a, b in
            let comparison: ComparisonResult
            switch self {
            case .updated: comparison = a.updatedAt.compare(b.updatedAt)
            case .created: comparison = a.createdAt.compare(b.createdAt)
            case .used:
                // Never-used prompts stay at the end in either direction.
                if (a.lastUsedAt == nil) != (b.lastUsedAt == nil) { return a.lastUsedAt != nil }
                comparison = (a.lastUsedAt ?? .distantPast).compare(b.lastUsedAt ?? .distantPast)
            case .title: comparison = a.title.localizedStandardCompare(b.title)
            case .manual:
                let left = a.sortIndex ?? .greatestFiniteMagnitude
                let right = b.sortIndex ?? .greatestFiniteMagnitude
                if left != right { return left < right }
                comparison = .orderedSame
            }
            if comparison != .orderedSame {
                return comparison == (direction == .ascending ? .orderedAscending : .orderedDescending)
            }
            // Ties must not depend on fetch order, favorites or editing time.
            if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            let titleOrder = a.title.localizedStandardCompare(b.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return a.id.uuidString < b.id.uuidString
        }
    }
}

enum PromptLibrarySortDirection: String, CaseIterable, Identifiable {
    case ascending, descending

    var id: String { rawValue }
    func name(for sort: PromptLibrarySort) -> String {
        if sort == .title { return self == .ascending ? "名称正序" : "名称倒序" }
        return self == .ascending ? "从旧到新" : "从新到旧"
    }
}
