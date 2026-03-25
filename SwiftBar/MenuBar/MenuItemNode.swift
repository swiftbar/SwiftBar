import Foundation

/// Represents a single parsed item from plugin output, organized into a tree
/// that mirrors the NSMenu hierarchy. Children correspond to submenu items.
struct MenuItemNode: Equatable {
    let line: String
    let level: Int
    let isSeparator: Bool
    let workingLine: String
    var children: [MenuItemNode]

    /// Compare only this node's own properties, ignoring children.
    /// Use this to decide whether an NSMenuItem needs its properties patched.
    func contentEqual(to other: MenuItemNode) -> Bool {
        line == other.line && level == other.level &&
            isSeparator == other.isSeparator && workingLine == other.workingLine
    }
}

// MARK: - Shape Fingerprint

/// A structural fingerprint that identifies the "role" of a menu item,
/// independent of volatile content like numbers, colors, or image data.
/// Used by the diff algorithm to match items across position shifts.
struct ShapeFingerprint: Hashable {
    let isSeparator: Bool
    let hasImage: Bool
    let fontName: String?
    let hasFold: Bool
    let titleKey: String
    let hasChildren: Bool
}

extension MenuItemNode {
    /// Compute a shape fingerprint for diffing. Two nodes with the same fingerprint
    /// are considered the "same item" even if their content changed.
    var shapeFingerprint: ShapeFingerprint {
        if isSeparator {
            return ShapeFingerprint(isSeparator: true, hasImage: false, fontName: nil, hasFold: false, titleKey: "", hasChildren: false)
        }
        let params = MenuLineParameters(line: workingLine)
        return ShapeFingerprint(
            isSeparator: false,
            hasImage: params.params["image"] != nil || params.params["templateimage"] != nil,
            fontName: params.font,
            hasFold: params.fold,
            titleKey: Self.extractTitleKey(from: params.title),
            hasChildren: !children.isEmpty
        )
    }

    /// Extract the stable "key" portion of a title.
    /// "Battery: 78% ████████░░" → "Battery:"
    /// "Climate: On  Set: 72°F" → "Climate:"
    /// "Home" → "Home"
    /// "" (image-only) → ""
    static func extractTitleKey(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "" }
        // If title contains a colon, take everything up to and including it
        if let colonIdx = trimmed.firstIndex(of: ":") {
            return String(trimmed[...colonIdx])
        }
        // Otherwise take the first word
        let firstWord = trimmed.prefix(while: { !$0.isWhitespace })
        return String(firstWord)
    }
}

// MARK: - Line Parsing

extension MenuItemNode {
    /// Parse a raw plugin output line into its level, separator status, and stripped content.
    /// This is the single source of truth for `--` prefix counting, used by both
    /// tree building and `MenuBarItem.addMenuItem(from:)`.
    static func parseLine(_ line: String) -> (level: Int, isSeparator: Bool, workingLine: String) {
        if line == "---" {
            return (level: 0, isSeparator: true, workingLine: "---")
        }

        var workingLine = line
        var level = 0

        while workingLine.hasPrefix("--") {
            workingLine = String(workingLine.dropFirst(2))
            level += 1
            if workingLine == "---" {
                break
            }
        }

        return (level: level, isSeparator: workingLine == "---", workingLine: workingLine)
    }
}

// MARK: - Tree Building

extension MenuItemNode {
    /// Build a tree of MenuItemNodes from the body lines of plugin output.
    /// The body lines are those returned by `splitScriptOutput().body`, which
    /// typically starts with a "---" separator.
    ///
    /// The tree structure mirrors how `addMenuItem(from:)` builds NSMenu items
    /// with submenus: items with `--` prefixes become children of the preceding
    /// item at a shallower depth.
    static func buildMenuTree(from bodyLines: [String]) -> [MenuItemNode] {
        // Use a class-based builder for reference semantics during construction,
        // then freeze into value-type MenuItemNodes at the end.
        let root = NodeBuilder(line: "", level: -1, isSeparator: false, workingLine: "")
        var stack: [(level: Int, node: NodeBuilder)] = [(-1, root)]

        for line in bodyLines {
            let (level, isSeparator, workingLine) = parseLine(line)
            if !isSeparator, !MenuLineParameters(line: workingLine).dropdown {
                continue
            }
            let node = NodeBuilder(line: line, level: level, isSeparator: isSeparator, workingLine: workingLine)

            // Pop entries at or above current level to find the parent.
            // This mirrors the prevItems stack logic in addMenuItem(from:).
            while stack.count > 1 && stack.last!.level >= level {
                stack.removeLast()
            }

            stack.last!.node.children.append(node)
            stack.append((level, node))
        }

        return root.children.map { $0.freeze() }
    }
}

// MARK: - Internal Builder

private final class NodeBuilder {
    let line: String
    let level: Int
    let isSeparator: Bool
    let workingLine: String
    var children: [NodeBuilder] = []

    init(line: String, level: Int, isSeparator: Bool, workingLine: String) {
        self.line = line
        self.level = level
        self.isSeparator = isSeparator
        self.workingLine = workingLine
    }

    func freeze() -> MenuItemNode {
        MenuItemNode(
            line: line,
            level: level,
            isSeparator: isSeparator,
            workingLine: workingLine,
            children: children.map { $0.freeze() }
        )
    }
}
