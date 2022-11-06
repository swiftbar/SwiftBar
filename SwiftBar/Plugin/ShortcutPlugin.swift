import Combine
import Foundation
import os

class PersistentShortcutPlugin: Codable, Identifiable {
    var id: PluginID
    var name: String
    var shortcut: String
    var repeatString: String
    var cronString: String

    init(id: PluginID, name: String, shortcut: String, repeatString: String, cronString: String) {
        self.id = id
        self.name = name
        self.shortcut = shortcut
        self.repeatString = repeatString
        self.cronString = cronString
    }
}

class ShortcutPlugin: Plugin, Identifiable {
    var id: PluginID
    var type: PluginType = .Shortcut
    var name: String
    var file: String = "none"
    var metadata: PluginMetadata?
    var contentUpdatePublisher = PassthroughSubject<String?, Never>()
    var updateInterval: Double = 0
    var lastUpdated: Date?
    var lastState: PluginState
    var shortcut: String
    var repeatString: String
    var cronString: String

    var operation: ShortcutPluginOperation?

    var content: String? = "..." {
        didSet {
            contentUpdatePublisher.send(content)
        }
    }

    var error: ShellOutError?
    var debugInfo = PluginDebugInfo()

    lazy var invokeQueue: OperationQueue = delegate.pluginManager.pluginInvokeQueue

    let shortcutsManager = ShortcutsManager.shared

    var persistentPlugin: PersistentShortcutPlugin {
        PersistentShortcutPlugin(id: id, name: name, shortcut: shortcut, repeatString: repeatString, cronString: cronString)
    }

    init(_ persistentItem: PersistentShortcutPlugin) {
        id = persistentItem.id
        name = persistentItem.name
        shortcut = persistentItem.shortcut
        repeatString = persistentItem.repeatString
        cronString = persistentItem.cronString
        lastState = .Loading

        os_log("Initialized Shortcut plugin\n%{public}@", log: Log.plugin, description)
        refresh()
    }

    func enableTimer() {}
    func disableTimer() {}

    func refresh() {
        guard enabled else {
            os_log("Skipping refresh for disabled plugin\n%{public}@", log: Log.plugin, description)
            return
        }
        os_log("Requesting manual refresh for plugin\n%{public}@", log: Log.plugin, description)
        debugInfo.addEvent(type: .PluginRefresh, value: "Requesting manual refresh")
        disableTimer()
        operation?.cancel()

        operation = ShortcutPluginOperation(plugin: self)
        invokeQueue.addOperation(operation!)
    }

    func enable() {}

    func disable() {}

    func start() {}

    func terminate() {}

    func invoke() -> String? {
        shortcutsManager.runShortcut(shortcut: shortcut)
    }
}

final class ShortcutPluginOperation: Operation {
    weak var plugin: ShortcutPlugin?

    init(plugin: ShortcutPlugin) {
        self.plugin = plugin
        super.init()
    }

    override func main() {
        guard !isCancelled else { return }
        plugin?.content = plugin?.invoke()
        plugin?.enableTimer()
    }
}
