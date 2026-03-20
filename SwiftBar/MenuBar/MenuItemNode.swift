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

// MARK: - Line Parsing

extension MenuItemNode {
    /// Parse a raw plugin output line into its level, separator status, and stripped content.
    /// Replicates the `--` prefix counting logic from `MenuBarItem.addMenuItem(from:)`.
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
