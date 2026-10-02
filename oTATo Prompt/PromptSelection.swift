import Foundation

/// The anchor stays fixed while Shift extends a range in the current sort order.
struct PromptSelection: Equatable {
    private(set) var ids: Set<UUID> = []
    private(set) var focusedID: UUID?
    private var anchorID: UUID?

    mutating func single(_ id: UUID?) {
        ids = Set(id.map { [$0] } ?? [])
        focusedID = id
        anchorID = id
    }

    mutating func select(_ id: UUID, orderedIDs: [UUID], toggle: Bool, extend: Bool) {
        if extend, let anchorID, let start = orderedIDs.firstIndex(of: anchorID),
           let end = orderedIDs.firstIndex(of: id) {
            let range = Set(orderedIDs[min(start, end)...max(start, end)])
            ids = toggle ? ids.union(range) : range
            focusedID = id
        } else if toggle {
            if !ids.insert(id).inserted { ids.remove(id) }
            focusedID = ids.contains(id) ? id : orderedIDs.last(where: ids.contains)
            anchorID = focusedID
        } else {
            single(id)
        }
    }

    mutating func all(_ orderedIDs: [UUID]) {
        ids = Set(orderedIDs)
        focusedID = orderedIDs.first
        anchorID = focusedID
    }

    mutating func retain(_ orderedIDs: [UUID]) {
        ids.formIntersection(orderedIDs)
        if let focusedID, !ids.contains(focusedID) { self.focusedID = orderedIDs.first(where: ids.contains) }
        if let anchorID, !ids.contains(anchorID) { self.anchorID = focusedID }
    }
}
