import Combine
import Foundation
import os
import ShellOut

class ExecutablePlugin: Plugin {
    var id: PluginID
    let type: PluginType = .Executable
    let name: String
    let file: String

    var updateInterval: Double = 60 * 60 * 24 * 100 // defaults to "never", for NOT timed scripts
    var metadata: PluginMetadata?
    var lastUpdated: Date?
    var lastState: PluginState
    var contentUpdatePublisher = PassthroughSubject<Any, Never>()

    var content: String? = "..." {
        didSet {
            guard content != oldValue else { return }
            contentUpdatePublisher.send("")
        }
    }

    var error: ShellOutError?

    lazy var invokeQueue: OperationQueue = {
        delegate.pluginManager.pluginInvokeQueue
    }()

    var updateTimerPublisher: Timer.TimerPublisher {
        Timer.TimerPublisher(interval: updateInterval, runLoop: .main, mode: .default)
    }

    var cancellable: Set<AnyCancellable> = []

    let prefs = Preferences.shared

    init(fileURL: URL) {
        let nameComponents = fileURL.lastPathComponent.components(separatedBy: ".")
        id = fileURL.lastPathComponent
        name = nameComponents.first ?? ""
        file = fileURL.path
        if metadata?.nextDate == nil, nameComponents.count > 2, let interval = Double(nameComponents[1].dropLast()) {
            let intervalStr = nameComponents[1]
            if intervalStr.hasSuffix("s") {
                updateInterval = interval
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

        lastState = .Loading
        makeScriptExecutable(file: file)
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
        disableTimer()
        // TODO: Cancel only operations from this plugin
//        invokeQueue.cancelAllOperations()
        refreshPluginMetadata()

        guard invokeQueue.operationCount < invokeQueue.maxConcurrentOperationCount else {
            os_log("Failed to schedule refresh of script\n%{public}@\n%{public}@. Execution queue is full!", log: Log.plugin, type: .error, file)
            return
        }
        invokeQueue.addOperation { [weak self] in
            self?.content = self?.invoke()
            self?.enableTimer()
        }
    }

    func invoke() -> String? {
        lastUpdated = Date()
        do {
            let out = try runScript(to: "'\(file)'", env: [
                EnvironmentVariables.swiftPluginPath.rawValue: file,
                EnvironmentVariables.osAppearance.rawValue: App.isDarkTheme ? "Dark" : "Light",
            ])
            error = nil
            lastState = .Success
            os_log("Successfully executed script \n%{public}@", log: Log.plugin, file)
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
