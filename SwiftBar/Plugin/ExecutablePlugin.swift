import Foundation
import Combine
import ShellOut
import os

class ExecutablePlugin: Plugin {
    var id: PluginID
    let type: PluginType = .Executable
    let name: String
    let file: String
    var enabled: Bool {
        !prefs.disabledPlugins.contains(id)
    }
    var updateInterval: Double = 60
    let metadata: PluginMetadata?
    var lastUpdated: Date? = nil
    var lastRefreshSuccesseful:Bool = false
    var contentUpdatePublisher = PassthroughSubject<Any, Never>()

    var content: String? = "..." {
        didSet {
            guard content != oldValue else {return}
            contentUpdatePublisher.send("")
        }
    }
    var error: ShellOutError?


    let queue = OperationQueue()
    var updateTimerPublisher: Timer.TimerPublisher {
        return Timer.TimerPublisher(interval: updateInterval, runLoop: .main, mode: .default)
    }

    var cancellable: Set<AnyCancellable> = []

    let prefs = Preferences.shared

    init(fileURL: URL) {
        let nameComponents = fileURL.lastPathComponent.components(separatedBy: ".")
        self.id = fileURL.lastPathComponent
        self.name = nameComponents.first ?? ""
        self.file = fileURL.path
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
        if let script = try? String(contentsOf: fileURL) {
            self.metadata = PluginMetadata.bitbarParser(script: script)
        } else {
            metadata = nil
        }
        makeScriptExecutable(file: file)
        os_log("Initialized executable plugin\n%s", log: Log.plugin, description)
        refresh()
    }

    func enableTimer() {
        disableTimer()
        updateTimerPublisher
            .autoconnect()
            .receive(on: queue)
            .sink(receiveValue: {[weak self] _ in
                self?.content = self?.invoke(params: [])
            }).store(in: &cancellable)
    }

    func disableTimer() {
        cancellable.forEach{$0.cancel()}
    }

    func refresh() {
        os_log("Requesting manual refresh for plugin\n%s", log: Log.plugin, description)
        disableTimer()
        queue.cancelAllOperations()
        queue.addOperation { [weak self] in
            self?.content = self?.invoke(params: [])
            self?.enableTimer()
        }
    }

    func terminate() {

    }

    func invoke(params : [String]) -> String? {
        lastUpdated = Date()
        do {
            let out = try shellOut(to: "'\(file)'")
            self.error = nil
            os_log("Successfully executed script \n%s", log: Log.plugin, file)
            return out
        } catch {
            guard let error = error as? ShellOutError else {return nil}
            os_log("Failed to execute script\n%s\n%s", log: Log.plugin, type:.error, file, error.message)
            self.error = error
        }
        return nil
    }

    func makeScriptExecutable(file: String) {
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
