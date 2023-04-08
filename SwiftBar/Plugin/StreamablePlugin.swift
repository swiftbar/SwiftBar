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
    var lastRefreshReason: PluginRefreshReason = .FirstLaunch
    var updateInterval = 0.0

    var contentUpdatePublisher = PassthroughSubject<String?, Never>()

    var streamInProgressContent: String = ""
    var content: String? = "" {
        didSet {
            guard content != oldValue else { return }
            lastUpdated = Date()
            contentUpdatePublisher.send(content)
        }
    }

    var error: Error?
    var debugInfo = PluginDebugInfo()

    lazy var invokeQueue: OperationQueue = delegate.pluginManager.pluginInvokeQueue

    var procces: Process?
    let prefs = PreferencesStore.shared

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
        createSupportDirs()
        os_log("Initialized streamable plugin\n%{public}@", log: Log.plugin, description)
        invokeQueue.addOperation { [weak self] in self?.invoke() }
    }

    func refresh(reason _: PluginRefreshReason = .FirstLaunch) {
        os_log("Refreshing Streamable plugin\n%{public}@", log: Log.plugin, description)
        terminate()
        invokeQueue.addOperation { [weak self] in self?.invoke() }
    }

    func start() {
        invokeQueue.addOperation { [weak self] in self?.invoke() }
    }

    func disable() {
        lastState = .Disabled
        content = ""
        procces?.terminate()
        prefs.disabledPlugins.append(id)
    }

    func terminate() {
        lastState = .Disabled
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
                                    env: env,
                                    runInBash: metadata?.shouldRunInBash ?? true,
                                    streamOutput: true,
                                    onOutputUpdate: { [weak self] str in
                                        if self?.prefs.streamablePluginDebugOutput == true,
                                           let str = str,
                                           let name = self?.name
                                        {
                                            os_log("Streaming %{public}@: %{public}@", log: Log.plugin, name, str)
                                        }
                                        guard let str = str else {
                                            self?.streamInProgressContent.removeAll()
                                            self?.content = nil
                                            return
                                        }
                                        guard str.contains("\n") || !str.contains(streamSeparator) else {
                                            self?.streamInProgressContent.append(contentsOf: str)
                                            return
                                        }

                                        guard self?.metadata?.useTrailingStreamSeparator == true else {
                                            // Process leading separator
                                            if str.contains(streamSeparator) {
                                                self?.content = str.components(separatedBy: streamSeparator).last
                                                return
                                            }
                                            self?.content?.append(str)
                                            return
                                        }
                                        // Process trailing separator
                                        if str.contains(streamSeparator) {
                                            // we expect streamSeparator on a separate line
                                            let lines = str.components(separatedBy: .newlines)
                                            let linesCount = lines.count
                                            let endsOnNewLine = str.last == "\n"
                                            for (i, s) in lines.enumerated() {
                                                if s == streamSeparator {
                                                    self?.content = self?.streamInProgressContent
                                                    self?.streamInProgressContent.removeAll()
                                                    continue
                                                }
                                                self?.streamInProgressContent.append(s)
                                                if !endsOnNewLine, i == linesCount - 1 {
                                                    continue
                                                }
                                                self?.streamInProgressContent.append("\n")
                                            }
                                            return
                                        }
                                        self?.streamInProgressContent.append(str)
                                    })
            error = nil
            lastState = .Streaming
            os_log("Successfully executed script \n%{public}@", log: Log.plugin, file)
            if let err = out.err, err != "" {
                debugInfo.addEvent(type: .ContentUpdateError, value: err)
                os_log("Error output from the script: \n%{public}@", log: Log.plugin, err)
            }
            return out.out
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
