import Combine
import Foundation
import os

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

    var contentUpdatePublisher = PassthroughSubject<String?, Never>()

    var content: String? = "" {
        didSet {
            guard content != oldValue else { return }
            lastUpdated = Date()
            contentUpdatePublisher.send(content)
        }
    }

    var error: ShellOutError?

    lazy var invokeQueue: OperationQueue = {
        delegate.pluginManager.pluginInvokeQueue
    }()

    var procces: Process?
    let prefs = Preferences.shared

    init?(fileURL: URL) {
        let nameComponents = fileURL.lastPathComponent.components(separatedBy: ".")
        id = fileURL.lastPathComponent
        name = nameComponents.first ?? ""
        file = fileURL.path
        lastState = .Streaming
        makeScriptExecutable(file: file)
        refreshPluginMetadata()
        guard metadata?.type == .Streamable else { return nil }
        guard enabled else { return }
        os_log("Initialized streamable plugin\n%{public}@", log: Log.plugin, description)
        invokeQueue.addOperation { [weak self] in self?.invoke() }
    }

    func refresh() {
        os_log("Manual refresh is not available for Streamable plugin\n%{public}@", log: Log.plugin, description)
    }

    func disable() {
        lastState = .Disabled
        content = ""
        procces?.terminate()
        prefs.disabledPlugins.append(id)
    }

    func terminate() {
        procces?.terminate()
    }

    func enable() {
        prefs.disabledPlugins.removeAll(where: { $0 == id })
        invokeQueue.addOperation { [weak self] in self?.invoke() }
    }

    @discardableResult func invoke() -> String? {
        lastUpdated = Date()
        do {
            procces = Process()
            guard let procces = procces else { return nil }
            let out = try runScript(to: file, process: procces,
                                    env: [
                                        EnvironmentVariables.swiftPluginPath.rawValue: file,
                                        EnvironmentVariables.osAppearance.rawValue: AppShared.isDarkTheme ? "Dark" : "Light",
                                    ],
                                    runInBash: metadata?.shouldRunInBash ?? true,
                                    onOutputUpdate: { [weak self] str in
                                        guard str != "\n" else {
                                            return
                                        }
                                        if self?.prefs.streamablePluginDebugOutput == true,
                                           let str = str,
                                           let name = self?.name
                                        {
                                            os_log("Streaming %{public}@: %{public}@", log: Log.plugin, name, str)
                                        }
                                        guard let str = str else {
                                            self?.content = nil
                                            return
                                        }
                                        if str.contains(streamSeparator) {
                                            self?.content = str.components(separatedBy: streamSeparator).last
                                            return
                                        }
                                        self?.content?.append(str)
                                    })
            error = nil
            lastState = .Success
            os_log("Successfully executed script \n%{public}@", log: Log.plugin, file)
            return out
        } catch {
            guard lastState != .Disabled,
                  let error = error as? ShellOutError else { return nil }
            os_log("Failed to execute script\n%{public}@\n%{public}@", log: Log.plugin, type: .error, file, error.message)
            self.error = error
            lastState = .Failed
            content = nil
        }
        return nil
    }
}
