import Foundation

enum PromptLibrarySort: String, CaseIterable, Identifiable {
    case title, updated

    var id: String { rawValue }
    var name: String {
        switch self {
        case .title: "A～Z"
        case .updated: "修改时间"
        }
    }

    func sorted(_ prompts: [Prompt]) -> [Prompt] {
        prompts.sorted { a, b in
            let comparison: ComparisonResult
            switch self {
            case .updated: comparison = b.updatedAt.compare(a.updatedAt)
            case .title: comparison = a.title.localizedStandardCompare(b.title)
            }
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            // Ties must not depend on fetch order, favorites or editing time.
            if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            let titleOrder = a.title.localizedStandardCompare(b.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return a.id.uuidString < b.id.uuidString
        }
    }
}
