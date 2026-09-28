import Foundation

/// A lightweight local text index shared by every search entry point.
@MainActor
enum PromptSearch {
    enum Scope: String, CaseIterable {
        case all
        case title
        case tags
        case content
        case favorites
        case recentlyEdited
        case recentlyUsed
        case trash
    }

    private struct IndexedText {
        let updatedAt: Date
        let folderID: UUID?
        let title: String
        let tags: String
        let content: String
        var folder: String
    }

    private struct Ranked {
        let prompt: Prompt
        let score: Int
        let title: String
        let updatedAt: Date
        let lastUsedAt: Date?
        let deletedAt: Date?
    }

    private static var index: [UUID: IndexedText] = [:]
    private static var folderSignature: Int?
    private static let searchLocale = Locale(identifier: "en_US_POSIX")

    static func invalidate(_ prompt: Prompt) {
        index.removeValue(forKey: prompt.id)
    }

    static func clearIndex() {
        index.removeAll()
        folderSignature = nil
    }

    /// Call after the library first loads to spread cold indexing across run-loop turns.
    static func prepareIndex(_ prompts: [Prompt], folders: [Folder] = []) async {
        let folderNames = Dictionary(folders.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        updateFolderCache(for: folders, names: folderNames)
        for (offset, prompt) in prompts.enumerated() {
            if Task.isCancelled { return }
            let id = prompt.id
            let updatedAt = prompt.updatedAt
            if index[id]?.updatedAt != updatedAt {
                let folderID = prompt.folderID
                index[id] = IndexedText(
                    updatedAt: updatedAt,
                    folderID: folderID,
                    title: normalized(prompt.title),
                    tags: normalized(prompt.tagNames.joined(separator: " ")),
                    content: normalized(prompt.content),
                    folder: normalized(folderID.flatMap { folderNames[$0] } ?? "")
                )
            }
            if offset.isMultiple(of: 128) { await Task.yield() }
        }
    }

    static func search(
        _ prompts: [Prompt],
        query: String,
        scope: Scope = .all,
        folders: [Folder] = [],
        limit: Int? = nil
    ) -> [Prompt] {
        let words = query.split(whereSeparator: \.isWhitespace).map { normalized(String($0)) }
        let folderNames = Dictionary(folders.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        if !words.isEmpty {
            updateFolderCache(for: folders, names: folderNames)
            if index.count > 10_000 { index.removeAll() }
        }

        var ranked: [Ranked] = []
        ranked.reserveCapacity(prompts.count)
        for prompt in prompts {
            let deletedAt = prompt.deletedAt
            if scope == .trash {
                guard deletedAt != nil else { continue }
            } else {
                guard deletedAt == nil else { continue }
            }
            if scope == .favorites && !prompt.isFavorite { continue }
            let lastUsedAt = prompt.lastUsedAt
            if scope == .recentlyUsed && lastUsedAt == nil { continue }
            let updatedAt = prompt.updatedAt

            if words.isEmpty {
                ranked.append(Ranked(
                    prompt: prompt, score: 0, title: prompt.title,
                    updatedAt: updatedAt, lastUsedAt: lastUsedAt, deletedAt: deletedAt
                ))
                continue
            }

            let id = prompt.id
            let entry: IndexedText
            if let cached = index[id], cached.updatedAt == updatedAt {
                entry = cached
            } else {
                let folderID = prompt.folderID
                let refreshed = IndexedText(
                    updatedAt: updatedAt,
                    folderID: folderID,
                    title: normalized(prompt.title),
                    tags: normalized(prompt.tagNames.joined(separator: " ")),
                    content: normalized(prompt.content),
                    folder: normalized(folderID.flatMap { folderNames[$0] } ?? "")
                )
                index[id] = refreshed
                entry = refreshed
            }

            var score = 0
            var matchesAllWords = true
            for word in words {
                let titleHit = scope != .tags && scope != .content && entry.title.contains(word)
                let wordScore: Int
                switch scope {
                case .title:
                    wordScore = titleHit ? 100 : 0
                case .tags:
                    wordScore = entry.tags.contains(word) ? 70 : 0
                case .content:
                    wordScore = containsInBody(word, entry.content) ? 30 : 0
                case .all, .favorites, .recentlyEdited, .recentlyUsed, .trash:
                    wordScore = titleHit ? 100
                        : entry.tags.contains(word) ? 70
                        : containsInBody(word, entry.content) ? 30
                        : entry.folder.contains(word) ? 10 : 0
                }
                if wordScore == 0 {
                    matchesAllWords = false
                    break
                }
                score += wordScore
                if titleHit && scope != .tags && scope != .content && entry.title.hasPrefix(word) {
                    score += 20
                }
            }
            if matchesAllWords {
                ranked.append(Ranked(
                    prompt: prompt, score: score, title: prompt.title,
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
        if let limit { return Array(ranked.prefix(max(0, limit)).map(\.prompt)) }
        return ranked.map(\.prompt)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: searchLocale)
    }

    private static func containsInBody(_ word: String, _ content: String) -> Bool {
        // Index and query are already folded; literal search avoids the slower
        // canonical-equivalence search performed by String.contains.
        content.range(of: word, options: .literal) != nil
    }

    private static func updateFolderCache(for folders: [Folder], names: [UUID: String]) {
        var hasher = Hasher()
        for folder in folders {
            hasher.combine(folder.id)
            hasher.combine(folder.name)
        }
        let signature = hasher.finalize()
        guard folderSignature != signature else { return }
        index = index.mapValues { item in
            var updated = item
            updated.folder = normalized(item.folderID.flatMap { names[$0] } ?? "")
            return updated
        }
        folderSignature = signature
    }
}
