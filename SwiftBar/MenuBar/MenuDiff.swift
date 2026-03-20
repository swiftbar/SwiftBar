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

/// Compute the differences between two flat arrays of MenuItemNodes at the same hierarchy level.
///
/// Uses positional comparison: items at the same index are compared directly.
/// Insertions and removals are detected at the tail. This handles the common case
/// of same-structure updates (titles/values change but item count stays the same).
///
/// Removals are returned in reverse index order so the caller can safely remove
/// items from an NSMenu without invalidating earlier indices.
func diffMenuNodes(old: [MenuItemNode], new: [MenuItemNode]) -> [MenuItemChange] {
    var changes: [MenuItemChange] = []
    let minCount = min(old.count, new.count)

    for i in 0 ..< minCount {
        if old[i] == new[i] {
            changes.append(.unchanged(oldIndex: i, newIndex: i))
        } else {
            changes.append(.update(oldIndex: i, newIndex: i))
        }
    }

    for i in minCount ..< new.count {
        changes.append(.insert(newIndex: i))
    }

    // Reverse order so removing by index doesn't shift later indices
    if old.count > minCount {
        for i in stride(from: old.count - 1, through: minCount, by: -1) {
            changes.append(.remove(oldIndex: i))
        }
    }

    return changes
}
