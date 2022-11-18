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
    var updateInterval: Double = 60 * 60 * 24 * 100
    var lastUpdated: Date?
    var lastState: PluginState
    var lastRefreshReason: PluginRefreshReason = .FirstLaunch
    var shortcut: String
    var repeatString: String
    var cronString: String

    var operation: RunPluginOperation<ShortcutPlugin>?

    var content: String? = "..." {
        didSet {
            contentUpdatePublisher.send(content)
        }
    }

    var error: Error?
    var debugInfo = PluginDebugInfo()

    lazy var invokeQueue: OperationQueue = delegate.pluginManager.pluginInvokeQueue

    var updateTimerPublisher: Timer.TimerPublisher {
        Timer.TimerPublisher(interval: updateInterval, runLoop: .main, mode: .default)
    }

    var cancellable: Set<AnyCancellable> = []

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
        updateInterval = parseRefreshInterval(intervalStr: repeatString, baseUpdateinterval: updateInterval) ?? updateInterval
        os_log("Initialized Shortcut plugin\n%{public}@", log: Log.plugin, description)
        refresh(reason: .FirstLaunch)
    }

    func enableTimer() {
        guard cancellable.isEmpty else { return }
        updateTimerPublisher
            .autoconnect()
            .receive(on: invokeQueue)
            .sink(receiveValue: { [weak self] _ in
                self?.lastRefreshReason = .Schedule
                self?.invokeQueue.addOperation(RunPluginOperation<ShortcutPlugin>(plugin: self!))
            }).store(in: &cancellable)
    }

    func disableTimer() {
        cancellable.forEach { $0.cancel() }
        cancellable.removeAll()
    }

    func refresh(reason: PluginRefreshReason) {
        guard enabled else {
            os_log("Skipping refresh for disabled plugin\n%{public}@", log: Log.plugin, description)
            return
        }
        os_log("Requesting manual refresh for plugin\n%{public}@", log: Log.plugin, description)
        debugInfo.addEvent(type: .PluginRefresh, value: "Requesting manual refresh")
        disableTimer()
        operation?.cancel()

        lastRefreshReason = reason
        operation = RunPluginOperation<ShortcutPlugin>(plugin: self)
        invokeQueue.addOperation(operation!)
    }

    func enable() {
        prefs.disabledPlugins.removeAll(where: { $0 == id })
        refresh(reason: .FirstLaunch)
    }

    func disable() {
        lastState = .Disabled
        disableTimer()
        prefs.disabledPlugins.append(id)
    }

    func start() {
        refresh(reason: .FirstLaunch)
    }

    func terminate() {
        disableTimer()
    }

    func invoke() -> String? {
        lastUpdated = Date()
        do {
            let out = try shortcutsManager.runShortcut(shortcut: shortcut)
            error = nil
            lastState = .Success
            os_log("Successfully executed Shortcut plugin: %{public}@", log: Log.plugin, "\(name)(\(shortcut))")
            debugInfo.addEvent(type: .ContentUpdate, value: out)
            return out
        } catch {
            guard let error = error as? RunShortcutError else { return nil }
            os_log("Failed to execute Shortcut plugin: %{public}@\n%{public}@", log: Log.plugin, type: .error, "\(name)(\(shortcut))", error.message)
            self.error = error
            debugInfo.addEvent(type: .ContentUpdateError, value: error.message)
            lastState = .Failed
        }
        return nil
    }
}
