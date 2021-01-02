import Combine
import Foundation
import os
import ShellOut

private let streamSeparator = "~~~"

class StreamablePlugin: Plugin {
    var id: PluginID
    let type: PluginType = .Streamable
    let name: String
    let file: String

    var metadata: PluginMetadata?
    var lastUpdated: Date?
    var lastState: PluginState
    var updateInterval = 0.0

    var contentUpdatePublisher = PassthroughSubject<Any, Never>()

    var content: String? = "" {
        didSet {
            guard content != oldValue else { return }
            lastUpdated = Date()
            print(content)
            contentUpdatePublisher.send("")
        }
    }

    var error: ShellOutError?

    lazy var invokeQueue: OperationQueue = {
        delegate.pluginManager.pluginInvokeQueue
    }()

    var cancellable: Set<AnyCancellable> = []

    let prefs = Preferences.shared
    var operation: PluginOperation?

    init?(fileURL: URL) {
        let nameComponents = fileURL.lastPathComponent.components(separatedBy: ".")
        id = fileURL.lastPathComponent
        name = nameComponents.first ?? ""
        file = fileURL.path
        lastState = .Loading
        makeScriptExecutable(file: file)
        refreshPluginMetadata()
        guard metadata?.streamable == true else { return nil }
        os_log("Initialized streamable plugin\n%{public}@", log: Log.plugin, description)
        operation = PluginOperation(code: { [weak self] in self?.invoke() })
        if let operation = operation {
            invokeQueue.addOperation(operation)
        }
    }

    func refresh() {
        os_log("Manual refresh is not available for Streamable plugin\n%{public}@", log: Log.plugin, description)
    }

    func disable() {
        lastState = .Disabled
        operation?.cancel()
        prefs.disabledPlugins.append(id)
    }

    func enable() {
        prefs.disabledPlugins.removeAll(where: { $0 == id })
        if let operation = operation {
            invokeQueue.addOperation(operation)
        }
    }

    @discardableResult func invoke() -> String? {
        lastUpdated = Date()
        do {
            let out = try runScript(to: "'\(file)'", onOutputUpdate: { [weak self] str in
                guard let str = str else {
                    self?.content = nil
                    return
                }
                if str.contains(streamSeparator) {
                    self?.content = str.components(separatedBy: streamSeparator).last
                    return
                }
                self?.content?.append(str)
            },
            env: [
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
}
