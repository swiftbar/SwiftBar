import Combine
import Foundation
import os

class ExecutablePlugin: Plugin {
    var id: PluginID
    let type: PluginType = .Executable
    let name: String
    let file: String

    var updateInterval: Double = 60 * 60 * 24 * 100 // defaults to "never", for NOT timed scripts
    var metadata: PluginMetadata?
    var lastUpdated: Date?
    var lastState: PluginState
    var contentUpdatePublisher = PassthroughSubject<String?, Never>()

    var content: String? = "..." {
        didSet {
            guard content != oldValue else { return }
            contentUpdatePublisher.send(content)
        }
    }

    var error: ShellOutError?
    var debugInfo = PluginDebugInfo()

    lazy var invokeQueue: OperationQueue = {
        delegate.pluginManager.pluginInvokeQueue
    }()

    var updateTimerPublisher: Timer.TimerPublisher {
        Timer.TimerPublisher(interval: updateInterval, runLoop: .main, mode: .default)
    }

    var cancellable: Set<AnyCancellable> = []

    let prefs = PreferencesStore.shared

    init(fileURL: URL) {
        let nameComponents = fileURL.lastPathComponent.components(separatedBy: ".")
        id = fileURL.lastPathComponent
        name = nameComponents.first ?? ""
        file = fileURL.path

        lastState = .Loading
        makeScriptExecutable(file: file)
        refreshPluginMetadata()

        if metadata?.nextDate == nil, nameComponents.count > 2, let interval = Double(nameComponents[1].filter("0123456789.".contains)) {
            let intervalStr = nameComponents[1]
            if intervalStr.hasSuffix("s") {
                updateInterval = interval
                if intervalStr.hasSuffix("ms") {
                    updateInterval = interval / 1000
                }
            }
            if intervalStr.hasSuffix("m") {
                updateInterval = interval * 60
            }
            if intervalStr.hasSuffix("h") {
                updateInterval = interval * 60 * 60
            }
            if intervalStr.hasSuffix("d") {
                updateInterval = interval * 60 * 60 * 24
            }
        }

        os_log("Initialized executable plugin\n%{public}@", log: Log.plugin, description)
        refresh()
    }

    func enableTimer() {
        // handle cron scheduled plugins
        if let nextDate = metadata?.nextDate {
            let timer = Timer(fireAt: nextDate, interval: 0, target: self, selector: #selector(scheduledContentUpdate), userInfo: nil, repeats: false)
            RunLoop.main.add(timer, forMode: .common)
            return
        }
        guard cancellable.isEmpty else { return }
        updateTimerPublisher
            .autoconnect()
            .receive(on: invokeQueue)
            .sink(receiveValue: { [weak self] _ in
                self?.content = self?.invoke()
            }).store(in: &cancellable)
    }

    func disableTimer() {
        cancellable.forEach { $0.cancel() }
        cancellable.removeAll()
    }

    func disable() {
        lastState = .Disabled
        disableTimer()
        prefs.disabledPlugins.append(id)
    }

    func terminate() {
        disableTimer()
    }

    func enable() {
        prefs.disabledPlugins.removeAll(where: { $0 == id })
        refresh()
    }

    func refresh() {
        guard enabled else {
            os_log("Skipping refresh for disabled plugin\n%{public}@", log: Log.plugin, description)
            return
        }
        os_log("Requesting manual refresh for plugin\n%{public}@", log: Log.plugin, description)
        debugInfo.addEvent(type: .PluginRefresh, value: "Requesting manual refresh")
        disableTimer()
        // TODO: Cancel only operations from this plugin
//        invokeQueue.cancelAllOperations()
        refreshPluginMetadata()

        if invokeQueue.operationCount == invokeQueue.maxConcurrentOperationCount {
            os_log("Failed to schedule refresh of script\n%{public}@\n%{public}@. Execution queue is full!", log: Log.plugin, type: .error, file)
            os_log("Cancelling all scheduled plugin updates, to free the queue", log: Log.plugin, type: .error)
            invokeQueue.cancelAllOperations()
        }

        invokeQueue.addOperation { [weak self] in
            self?.content = self?.invoke()
            self?.enableTimer()
        }
    }

    func invoke() -> String? {
        lastUpdated = Date()
        do {
            let out = try runScript(to: file, env: [
                EnvironmentVariables.swiftPluginPath.rawValue: file,
                EnvironmentVariables.osAppearance.rawValue: AppShared.isDarkTheme ? "Dark" : "Light",
            ],
            runInBash: metadata?.shouldRunInBash ?? true)
            error = nil
            lastState = .Success
            os_log("Successfully executed script \n%{public}@", log: Log.plugin, file)
            debugInfo.addEvent(type: .ContentUpdate, value: out)
            return out
        } catch {
            guard let error = error as? ShellOutError else { return nil }
            os_log("Failed to execute script\n%{public}@\n%{public}@", log: Log.plugin, type: .error, file, error.message)
            self.error = error
            lastState = .Failed
        }
        return nil
    }

    @objc func scheduledContentUpdate() {
        content = invoke()
        enableTimer()
    }
}
