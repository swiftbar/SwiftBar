import Foundation

/// Describes a single change between an old and new menu item list at one level of the hierarchy.
enum MenuItemChange: Equatable {
    /// The item at this position is identical (including all descendants).
    case unchanged(oldIndex: Int, newIndex: Int)

    /// The item at this position exists in both old and new but differs.
    /// The patcher should update the NSMenuItem's properties and recursively diff children.
    case update(oldIndex: Int, newIndex: Int)

    /// A new item was added at this position in the new list.
    case insert(newIndex: Int)

    /// The item at this position in the old list was removed.
    case remove(oldIndex: Int)
}

// MARK: - Shape-Based Diffing

/// A wrapper that gives MenuItemNode a shape-based identity for CollectionDifference.
/// Two nodes with the same shape fingerprint and occurrence index are considered the
/// "same item" for diffing purposes, even if their content (values, images) changed.
private struct TaggedNode: Hashable {
    let fingerprint: ShapeFingerprint
    let occurrence: Int
}

/// Compute the differences between two flat arrays of MenuItemNodes using
/// Swift's CollectionDifference with shape-based identity matching.
///
/// Items are matched by structural "shape" (separator, image, font, title prefix)
/// rather than position, so inserts and removes in the middle of the list correctly
/// track which items shifted rather than misaligning everything after the change point.
///
/// Removals are returned in reverse index order so the caller can safely remove
/// items from an NSMenu without invalidating earlier indices.
func diffMenuNodes(old: [MenuItemNode], new: [MenuItemNode]) -> [MenuItemChange] {
    let oldTagged = tagNodes(old)
    let newTagged = tagNodes(new)

    let diff = newTagged.difference(from: oldTagged).inferringMoves()

    return buildChanges(from: diff, old: old, new: new)
}

// MARK: - Private Helpers

/// Build tagged node arrays by counting occurrences of each fingerprint.
private func tagNodes(_ nodes: [MenuItemNode]) -> [TaggedNode] {
    var counts: [ShapeFingerprint: Int] = [:]
    return nodes.map { node in
        let fp = node.shapeFingerprint
        let occ = counts[fp, default: 0]
        counts[fp] = occ + 1
        return TaggedNode(fingerprint: fp, occurrence: occ)
    }
}

/// Map CollectionDifference output back to [MenuItemChange].
private func buildChanges(
    from diff: CollectionDifference<TaggedNode>,
    old: [MenuItemNode],
    new: [MenuItemNode]
) -> [MenuItemChange] {
    // Collect pure removes, pure inserts, and moves from the diff.
    var removedOldIndices = Set<Int>()
    var insertedNewIndices = Set<Int>()
    var movedOldToNew: [Int: Int] = [:]

    for change in diff {
        switch change {
        case .remove(let offset, _, let associatedWith):
            if let newOffset = associatedWith {
                movedOldToNew[offset] = newOffset
            } else {
                removedOldIndices.insert(offset)
            }
        case .insert(let offset, _, let associatedWith):
            if associatedWith == nil {
                insertedNewIndices.insert(offset)
            }
        }
    }

    // Build old→new mapping for stationary items (not moved, removed, or inserted).
    var oldToNew: [Int: Int] = movedOldToNew
    let usedOld = removedOldIndices.union(Set(movedOldToNew.keys))
    let usedNew = insertedNewIndices.union(Set(movedOldToNew.values))

    var oi = 0, ni = 0
    while oi < old.count && ni < new.count {
        if usedOld.contains(oi) { oi += 1; continue }
        if usedNew.contains(ni) { ni += 1; continue }
        oldToNew[oi] = ni
        oi += 1; ni += 1
    }

    // Check that matched items preserve relative order (no true reordering).
    // If reordered, degrade moved items to remove+insert.
    let matchedPairs = oldToNew.sorted(by: { $0.key < $1.key })
    let newIndicesInOldOrder = matchedPairs.map(\.value)
    let isOrdered = zip(newIndicesInOldOrder, newIndicesInOldOrder.dropFirst()).allSatisfy { $0 < $1 }

    if !isOrdered {
        for (oldIdx, newIdx) in movedOldToNew {
            removedOldIndices.insert(oldIdx)
            insertedNewIndices.insert(newIdx)
            oldToNew.removeValue(forKey: oldIdx)
        }
        // Rebuild stationary mapping without the moved items
        var soi = 0, sni = 0
        let sUsedOld = removedOldIndices
        let sUsedNew = insertedNewIndices
        oldToNew.removeAll()
        while soi < old.count && sni < new.count {
            if sUsedOld.contains(soi) { soi += 1; continue }
            if sUsedNew.contains(sni) { sni += 1; continue }
            oldToNew[soi] = sni
            soi += 1; sni += 1
        }
    }

    // Build the reverse map for fast lookup
    var newToOld: [Int: Int] = [:]
    for (o, n) in oldToNew { newToOld[n] = o }

    // Assemble result: removals in reverse order first, then updates/inserts forward.
    var changes: [MenuItemChange] = []

    for oldIdx in removedOldIndices.sorted(by: >) {
        changes.append(.remove(oldIndex: oldIdx))
    }

    for ni in 0 ..< new.count {
        if insertedNewIndices.contains(ni) {
            changes.append(.insert(newIndex: ni))
        } else if let oi = newToOld[ni] {
            if old[oi] == new[ni] {
                changes.append(.unchanged(oldIndex: oi, newIndex: ni))
            } else {
                changes.append(.update(oldIndex: oi, newIndex: ni))
            }
        }
    }

    return changes
}
