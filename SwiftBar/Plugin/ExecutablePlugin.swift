import Combine
import Foundation
import os
import ShellOut

class ExecutablePlugin: Plugin {
    var id: PluginID
    let type: PluginType = .Executable
    let name: String
    let file: String
    var enabled: Bool {
        !prefs.disabledPlugins.contains(id)
    }

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

    let queue = OperationQueue()
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
        if nameComponents.count > 2, let interval = Double(nameComponents[1].dropLast()) {
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

    func refreshPluginMetadata() {
        let url = URL(fileURLWithPath: file)
        if let script = try? String(contentsOf: url) {
            metadata = PluginMetadata.parser(script: script)
        } else {
            metadata = nil
        }
    }

    func enableTimer() {
        guard cancellable.isEmpty else { return }
        updateTimerPublisher
            .autoconnect()
            .receive(on: queue)
            .sink(receiveValue: { [weak self] _ in
                self?.content = self?.invoke(params: [])
            }).store(in: &cancellable)
    }

    func disableTimer() {
        cancellable.forEach { $0.cancel() }
        cancellable.removeAll()
    }

    func refresh() {
        guard enabled else {
            os_log("Skipping refresh for disabled plugin\n%{public}@", log: Log.plugin, description)
            return
        }
        os_log("Requesting manual refresh for plugin\n%{public}@", log: Log.plugin, description)
        disableTimer()
        queue.cancelAllOperations()
        refreshPluginMetadata()
        queue.addOperation { [weak self] in
            self?.content = self?.invoke(params: [])
            self?.enableTimer()
        }
    }

    func terminate() {}

    func invoke(params _: [String]) -> String? {
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

    func makeScriptExecutable(file: String) {
        guard prefs.makePluginExecutable else { return }
        let script = """
        if [[ -x "\(file)" ]]
        then
            echo "File "\(file)" is executable"
        else
            chmod +x "\(file)"
        fi
        """
        _ = try? shellOut(to: script)
    }
}
