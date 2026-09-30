import Foundation

struct PromptLibraryFilter: Equatable {
    enum TagMatch: String, CaseIterable, Identifiable, Hashable {
        case all = "包含全部标签"
        case any = "包含任一标签"
        var id: String { rawValue }
    }

    enum Favorite: String, CaseIterable, Identifiable, Hashable {
        case any = "不限"
        case favorites = "已收藏"
        case nonFavorites = "未收藏"
        var id: String { rawValue }
    }

    enum Cover: String, CaseIterable, Identifiable, Hashable {
        case any = "不限"
        case withCover = "有封面"
        case withoutCover = "无封面"
        var id: String { rawValue }
    }

    enum Updated: String, CaseIterable, Identifiable, Hashable {
        case any = "不限"
        case today = "今天"
        case last7Days = "最近 7 天"
        case last30Days = "最近 30 天"
        var id: String { rawValue }
    }

    enum TagPresence: String, CaseIterable, Identifiable, Hashable {
        case any = "不限"
        case tagged = "有标签"
        case untagged = "无标签"
        var id: String { rawValue }
    }

    var selectedTagIDs: Set<UUID> = []
    var excludedTagIDs: Set<UUID> = []
    var tagMatch: TagMatch = .all
    var favorite: Favorite = .any
    var cover: Cover = .any
    var updated: Updated = .any
    var tagPresence: TagPresence = .any

    var isActive: Bool { activeCriterionCount > 0 }

    var activeCriterionCount: Int {
        selectedTagIDs.count + excludedTagIDs.count
            + (favorite == .any ? 0 : 1)
            + (cover == .any ? 0 : 1)
            + (updated == .any ? 0 : 1)
            + (tagPresence == .any ? 0 : 1)
    }

    /// Filters the caller's scope without changing its ordering or Trash policy.
    func apply(to prompts: [Prompt], now: Date = .now, calendar: Calendar = .current) -> [Prompt] {
        let dateRange: DateInterval?
        switch updated {
        case .any:
            dateRange = nil
        case .today:
            dateRange = calendar.dateInterval(of: .day, for: now)
        case .last7Days, .last30Days:
            let days = updated == .last7Days ? 7 : 30
            dateRange = calendar.date(byAdding: .day, value: -days, to: now)
                .map { DateInterval(start: $0, end: now) }
        }

        return prompts.filter { prompt in
            let tagIDs = Set(prompt.tags.map(\.id))
            if !selectedTagIDs.isEmpty {
                switch tagMatch {
                case .all:
                    guard selectedTagIDs.isSubset(of: tagIDs) else { return false }
                case .any:
                    guard !selectedTagIDs.isDisjoint(with: tagIDs) else { return false }
                }
            }
            guard excludedTagIDs.isDisjoint(with: tagIDs) else { return false }

            switch tagPresence {
            case .any: break
            case .tagged: guard !tagIDs.isEmpty else { return false }
            case .untagged: guard tagIDs.isEmpty else { return false }
            }

            switch favorite {
            case .any: break
            case .favorites: guard prompt.isFavorite else { return false }
            case .nonFavorites: guard !prompt.isFavorite else { return false }
            }

            let hasCover = prompt.coverPath.map { !$0.isEmpty } ?? false
            switch cover {
            case .any: break
            case .withCover: guard hasCover else { return false }
            case .withoutCover: guard !hasCover else { return false }
            }

            if let dateRange {
                // DateInterval.contains includes the end, whereas local days are half-open.
                let beforeEnd = updated == .today
                    ? prompt.updatedAt < dateRange.end
                    : prompt.updatedAt <= dateRange.end
                guard prompt.updatedAt >= dateRange.start && beforeEnd else { return false }
            }
            return true
        }
    }

    mutating func toggleTag(_ id: UUID) {
        if selectedTagIDs.remove(id) == nil {
            selectedTagIDs.insert(id)
            excludedTagIDs.remove(id)
            if tagPresence == .untagged { tagPresence = .any }
        }
    }

    mutating func toggleExcludedTag(_ id: UUID) {
        if excludedTagIDs.remove(id) == nil {
            excludedTagIDs.insert(id)
            selectedTagIDs.remove(id)
            if tagPresence == .untagged { tagPresence = .any }
        }
    }

    mutating func setTagPresence(_ value: TagPresence) {
        tagPresence = value
        if value == .untagged {
            selectedTagIDs.removeAll()
            excludedTagIDs.removeAll()
        }
    }

    mutating func clearTags() {
        selectedTagIDs.removeAll()
        excludedTagIDs.removeAll()
        tagPresence = .any
        tagMatch = .all
    }

    mutating func reset() { self = Self() }

    mutating func removeUnknownTags(validIDs: Set<UUID>) {
        selectedTagIDs.formIntersection(validIDs)
        excludedTagIDs.formIntersection(validIDs)
    }
}

struct PromptTagFilterOption: Identifiable, Equatable {
    let id: UUID
    let name: String
    let promptCount: Int
}
