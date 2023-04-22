import Combine
import Foundation
import os

class EphemeralPlugin: Plugin {
    var id: PluginID
    let type: PluginType = .Ephemeral
    let name: String = "Ephemeral"
    let file: String = "none"
    var refreshEnv: [String: String] = [:]

    var updateInterval: Double = 60 * 60 * 24 * 100 {
        didSet {
            cancellable.forEach { $0.cancel() }
            cancellable.removeAll()

            guard updateInterval != 0 else { return }
            updateTimerPublisher
                .autoconnect()
                .receive(on: RunLoop.main)
                .sink(receiveValue: { [weak self] _ in
                    self?.terminate()
                }).store(in: &cancellable)
        }
    }

    var metadata: PluginMetadata?
    var lastUpdated: Date?
    var lastState: PluginState
    var lastRefreshReason: PluginRefreshReason = .FirstLaunch
    var contentUpdatePublisher = PassthroughSubject<String?, Never>()
    var operation: RunPluginOperation<ExecutablePlugin>?

    var content: String? = "..." {
        didSet {
            guard content != oldValue else { return }
            lastUpdated = Date()
            contentUpdatePublisher.send(content)
        }
    }

    var error: Error?
    var debugInfo = PluginDebugInfo()

    lazy var invokeQueue: OperationQueue = delegate.pluginManager.pluginInvokeQueue

    var updateTimerPublisher: Timer.TimerPublisher {
        Timer.TimerPublisher(interval: updateInterval, runLoop: .main, mode: .default)
    }

    var cronTimer: Timer?

    var cancellable: Set<AnyCancellable> = []

    let prefs = PreferencesStore.shared

    init(id: PluginID, content: String, exitAfter: Double) {
        self.id = id
        lastState = .Success
        os_log("Initialized ephemeral plugin\n%{public}@", log: Log.plugin, description)
        refresh(reason: .FirstLaunch)
        self.content = content
        lastUpdated = Date()
        if exitAfter != 0 {
            updateInterval = exitAfter
            updateTimerPublisher
                .autoconnect()
                .receive(on: invokeQueue)
                .sink(receiveValue: { [weak self] _ in
                    self?.terminate()
                }).store(in: &cancellable)
        }
    }

    func disable() {}

    func terminate() {
        delegate.pluginManager.setEphemeralPlugin(pluginId: id, content: "")
    }

    func enable() {}

    func start() {}

    func refresh(reason _: PluginRefreshReason) {}

    func invoke() -> String? {
        nil
    }
}
