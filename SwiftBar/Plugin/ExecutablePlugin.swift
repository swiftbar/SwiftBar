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
    var operation: RunPluginOperation<ExecutablePlugin>?

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

    var cronTimer: Timer?

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

        if metadata?.nextDate == nil, nameComponents.count > 2 {
            updateInterval = nameComponents.dropFirst().compactMap { parseRefreshInterval(intervalStr: $0, baseUpdateinterval: updateInterval) }.reduce(updateInterval, min)
        }
        createSupportDirs()
        os_log("Initialized executable plugin\n%{public}@", log: Log.plugin, description)
        refresh()
    }

    // this function called each time plugin updated(manual or scheduled)
    func enableTimer() {
        // handle cron scheduled plugins
        if let nextDate = metadata?.nextDate {
            cronTimer?.invalidate()
            cronTimer = Timer(fireAt: nextDate, interval: 0, target: self, selector: #selector(scheduledContentUpdate), userInfo: nil, repeats: false)
            if let cronTimer {
                RunLoop.main.add(cronTimer, forMode: .common)
            }
            return
        }
        guard cancellable.isEmpty else { return }
        updateTimerPublisher
            .autoconnect()
            .receive(on: invokeQueue)
            .sink(receiveValue: { [weak self] _ in
                self?.invokeQueue.addOperation(RunPluginOperation<ExecutablePlugin>(plugin: self!))
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

    func start() {
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
        operation?.cancel()

        refreshPluginMetadata()
        operation = RunPluginOperation<ExecutablePlugin>(plugin: self)
        invokeQueue.addOperation(operation!)
    }

    func invoke() -> String? {
        lastUpdated = Date()
        do {
            let out = try runScript(to: file, env: env,
                                    runInBash: metadata?.shouldRunInBash ?? true)
            error = nil
            lastState = .Success
            os_log("Successfully executed script \n%{public}@", log: Log.plugin, file)
            debugInfo.addEvent(type: .ContentUpdate, value: out.out)
            if let err = out.err, err != "" {
                debugInfo.addEvent(type: .ContentUpdateError, value: err)
                os_log("Error output from the script: \n%{public}@:", log: Log.plugin, err)
            }
            return out.out
        } catch {
            guard let error = error as? ShellOutError else { return nil }
            os_log("Failed to execute script\n%{public}@\n%{public}@", log: Log.plugin, type: .error, file, error.message)
            os_log("Error output from the script: \n%{public}@", log: Log.plugin, error.message)
            self.error = error
            debugInfo.addEvent(type: .ContentUpdateError, value: error.message)
            lastState = .Failed
        }
        return nil
    }

    @objc func scheduledContentUpdate() {
        refresh()
    }
}
