import Foundation

/// A lightweight local text index shared by every search entry point.
@MainActor
enum PromptSearch {
    enum Scope: String, CaseIterable, Sendable {
        case all
        case title
        case tags
        case favorites
        case recentlyEdited
        case recentlyUsed
        case trash
    }

    private struct IndexedText: Sendable {
        let updatedAt: Date
        let title: String
        let tags: String
    }

    private struct Candidate: Sendable {
        let id: UUID
        let title: String
        let text: IndexedText
        let isFavorite: Bool
        let lastUsedAt: Date?
        let deletedAt: Date?
    }

    private struct Ranked {
        let id: UUID
        let score: Int
        let title: String
        let updatedAt: Date
        let lastUsedAt: Date?
        let deletedAt: Date?
    }

    private static var index: [UUID: IndexedText] = [:]
    private static var preparationGeneration = 0
    private nonisolated static let searchLocale = Locale(identifier: "en_US_POSIX")

    static func invalidate(_ prompt: Prompt) {
        index.removeValue(forKey: prompt.id)
        preparationGeneration += 1
    }

    static func clearIndex() {
        index.removeAll()
        preparationGeneration += 1
    }

    /// Index title and tag metadata only; prompt bodies and folder names are
    /// excluded from every search entry point.
    static func prepareIndex(_ prompts: [Prompt], folders: [Folder] = []) async {
        let generation = preparationGeneration
        await Task.yield()
        for start in stride(from: 0, to: prompts.count, by: 4) {
            if Task.isCancelled || generation != preparationGeneration { return }
            var batch: [(UUID, IndexedText)] = []
            for prompt in prompts[start..<min(start + 4, prompts.count)] where index[prompt.id]?.updatedAt != prompt.updatedAt {
                batch.append((prompt.id, IndexedText(updatedAt: prompt.updatedAt,
                    title: prompt.title, tags: prompt.tagNames.joined(separator: " "))))
            }
            guard !batch.isEmpty else { continue }
            let inputs = batch
            let worker = Task.detached(priority: .utility) {
                inputs.map { id, text in
                    (id, IndexedText(updatedAt: text.updatedAt,
                        title: normalized(text.title), tags: normalized(text.tags)))
                }
            }
            let prepared = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            if Task.isCancelled || generation != preparationGeneration { return }
            for (id, text) in prepared { index[id] = text }
            await Task.yield()
        }
    }

    static func search(
        _ prompts: [Prompt], query: String, scope: Scope = .all,
        folders: [Folder] = [], limit: Int? = nil
    ) -> [Prompt] {
        let words = query.split(whereSeparator: \.isWhitespace).map { normalized(String($0)) }
        let candidates = prompts.map { snapshot($0) }
        let ids = rankedIDs(candidates, words: words, scope: scope, limit: limit)
        let byID = Dictionary(prompts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    /// Only value snapshots cross actors; SwiftData models stay on the main actor.
    /// Cancellation prevents superseded queries from replacing newer results.
    static func searchAsync(
        _ prompts: [Prompt], query: String, scope: Scope = .all,
        folders: [Folder] = [], limit: Int? = nil
    ) async -> [Prompt] {
        let words = query.split(whereSeparator: \.isWhitespace).map { normalized(String($0)) }
        if words.isEmpty { return search(prompts, query: query, scope: scope, folders: folders, limit: limit) }
        var candidates: [Candidate] = []
        candidates.reserveCapacity(prompts.count)
        for start in stride(from: 0, to: prompts.count, by: 32) {
            guard !Task.isCancelled else { return [] }
            for prompt in prompts[start..<min(start + 32, prompts.count)] {
                candidates.append(snapshot(prompt))
            }
            await Task.yield()
        }
        let inputs = candidates
        let worker = Task.detached(priority: .userInitiated) {
            rankedIDs(inputs, words: words, scope: scope, limit: limit)
        }
        let ids = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled else { return [] }
        let byID = Dictionary(prompts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    static func revision(_ prompts: [Prompt], folders: [Folder]) -> Int {
        var hasher = Hasher()
        for prompt in prompts {
            hasher.combine(prompt.id); hasher.combine(prompt.updatedAt)
            hasher.combine(prompt.deletedAt); hasher.combine(prompt.isFavorite); hasher.combine(prompt.lastUsedAt)
        }
        for folder in folders { hasher.combine(folder.id); hasher.combine(folder.name) }
        return hasher.finalize()
    }

    private static func snapshot(_ prompt: Prompt) -> Candidate {
        let entry: IndexedText
        if let cached = index[prompt.id], cached.updatedAt == prompt.updatedAt { entry = cached }
        else {
            let refreshed = IndexedText(updatedAt: prompt.updatedAt,
                title: normalized(prompt.title), tags: normalized(prompt.tagNames.joined(separator: " ")))
            index[prompt.id] = refreshed
            entry = refreshed
        }
        return Candidate(id: prompt.id, title: prompt.title, text: entry,
                         isFavorite: prompt.isFavorite, lastUsedAt: prompt.lastUsedAt, deletedAt: prompt.deletedAt)
    }

    private nonisolated static func rankedIDs(
        _ candidates: [Candidate], words: [String], scope: Scope, limit: Int?
    ) -> [UUID] {
        var ranked: [Ranked] = []
        ranked.reserveCapacity(candidates.count)
        for candidate in candidates {
            if Task.isCancelled { return [] }
            let deletedAt = candidate.deletedAt
            if scope == .trash {
                guard deletedAt != nil else { continue }
            } else {
                guard deletedAt == nil else { continue }
            }
            if scope == .favorites && !candidate.isFavorite { continue }
            let lastUsedAt = candidate.lastUsedAt
            if scope == .recentlyUsed && lastUsedAt == nil { continue }
            let updatedAt = candidate.text.updatedAt

            if words.isEmpty {
                ranked.append(Ranked(
                    id: candidate.id, score: 0, title: candidate.title,
                    updatedAt: updatedAt, lastUsedAt: lastUsedAt, deletedAt: deletedAt
                ))
                continue
            }

            let entry = candidate.text

            var score = 0
            var matchesAllWords = true
            for word in words {
                let titleHit = scope != .tags && entry.title.contains(word)
                let wordScore: Int
                switch scope {
                case .title:
                    wordScore = titleHit ? 100 : 0
                case .tags:
                    wordScore = entry.tags.contains(word) ? 70 : 0
                case .all, .favorites, .recentlyEdited, .recentlyUsed, .trash:
                    wordScore = titleHit ? 100
                        : entry.tags.contains(word) ? 70 : 0
                }
                if wordScore == 0 {
                    matchesAllWords = false
                    break
                }
                score += wordScore
                if titleHit && scope != .tags && entry.title.hasPrefix(word) {
                    score += 20
                }
            }
            if matchesAllWords {
                ranked.append(Ranked(
                    id: candidate.id, score: score, title: candidate.title,
                    updatedAt: updatedAt, lastUsedAt: lastUsedAt, deletedAt: deletedAt
                ))
            }
        }

        ranked.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if words.isEmpty {
                if scope == .trash && lhs.deletedAt != rhs.deletedAt {
                    return (lhs.deletedAt ?? .distantPast) > (rhs.deletedAt ?? .distantPast)
                }
                if scope != .favorites && scope != .recentlyUsed && scope != .trash && lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
            }
            if lhs.lastUsedAt != rhs.lastUsedAt {
                return (lhs.lastUsedAt ?? .distantPast) > (rhs.lastUsedAt ?? .distantPast)
            }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        if let limit { return Array(ranked.prefix(max(0, limit)).map(\.id)) }
        return ranked.map(\.id)
    }

    private nonisolated static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: searchLocale)
    }

    static func pruneIndex(keeping ids: Set<UUID>) {
        for id in Array(index.keys) where !ids.contains(id) { index.removeValue(forKey: id) }
    }
}
