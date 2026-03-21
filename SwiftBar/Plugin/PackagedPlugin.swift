import Combine
import Foundation
import os

/// Represents a packaged plugin — a `.swiftbar` directory containing a main
/// executable script (`plugin.*`) alongside supporting files (libraries, assets, etc.).
class PackagedPlugin: Plugin {
    var id: PluginID
    var type: PluginType = .Executable
    var name: String
    var file: String
    let packageDirectory: URL
    let mainExecutable: URL
    var updateInterval: Double = 60 * 60 * 24 * 100 // defaults to "never"
    var refreshEnv: [String: String] = [:]

    private var _metadata: PluginMetadata?
    private let metadataQueue = DispatchQueue(label: "com.ameba.SwiftBar.PackagedPlugin.metadata", attributes: .concurrent)

    var metadata: PluginMetadata? {
        get {
            metadataQueue.sync { _metadata }
        }
        set {
            metadataQueue.async(flags: .barrier) { [weak self] in
                self?._metadata = newValue
            }
        }
    }

    var lastUpdated: Date?
    var lastState: PluginState
    var lastRefreshReason: PluginRefreshReason = .FirstLaunch
    var contentUpdatePublisher = PassthroughSubject<String?, Never>()
    var operation: RunPluginOperation<PackagedPlugin>?

    var content: String? = "..." {
        didSet {
            guard content != oldValue || PluginRefreshReason.manualReasons().contains(lastRefreshReason) else { return }
            contentUpdatePublisher.send(content)
        }
    }

    var error: Error?
    var debugInfo = PluginDebugInfo()

    lazy var invokeQueue: OperationQueue = delegate.pluginManager.pluginInvokeQueue

    var updateTimerPublisher: Timer.TimerPublisher {
        Timer.TimerPublisher(interval: updateInterval, runLoop: .main, mode: .common)
    }

    var cronTimer: Timer?

    var cancellable: Set<AnyCancellable> = []

    let prefs = PreferencesStore.shared

    // MARK: - Initialization

    /// Initialize with a `.swiftbar` directory URL.
    init?(packageDirectory: URL) {
        guard packageDirectory.lastPathComponent.hasSuffix(".swiftbar") else {
            os_log("Directory %{public}@ is not a valid packaged plugin (must end with .swiftbar)",
                   log: Log.plugin, type: .error, packageDirectory.path)
            return nil
        }

        self.packageDirectory = packageDirectory
        name = packageDirectory.lastPathComponent.replacingOccurrences(of: ".swiftbar", with: "")
        id = packageDirectory.resolvingSymlinksInPath().path

        guard let mainExecutable = PackagedPlugin.findMainExecutable(in: packageDirectory) else {
            os_log("Failed to find plugin.* entry point in packaged plugin %{public}@",
                   log: Log.plugin, type: .error, packageDirectory.path)
            return nil
        }

        self.mainExecutable = mainExecutable
        file = mainExecutable.path
        lastState = .Loading

        makeScriptExecutable(file: file)
        refreshPluginMetadata()

        if let metadata, metadata.type == .Streamable {
            type = .Streamable
        }

        let nameComponents = mainExecutable.lastPathComponent.components(separatedBy: ".")
        if metadata?.nextDate == nil, nameComponents.count > 2 {
            updateInterval = nameComponents.dropFirst()
                .compactMap { parseRefreshInterval(intervalStr: $0, baseUpdateinterval: updateInterval) }
                .reduce(updateInterval, min)
        }

        createSupportDirs()
        os_log("Initialized packaged plugin\n%{public}@", log: Log.plugin, description)
        refresh(reason: .FirstLaunch)
    }

    // MARK: - Entry Point Discovery

    /// Finds the `plugin.*` entry point inside a `.swiftbar` directory.
    static func findMainExecutable(in directory: URL) -> URL? {
        guard directory.lastPathComponent.hasSuffix(".swiftbar") else {
            return nil
        }

        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }

        var candidates = contents.filter { url in
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
                return false
            }
            return url.lastPathComponent.hasPrefix("plugin.")
        }

        // Prefer already-executable files, break ties alphabetically for determinism
        candidates.sort {
            let exec0 = fileManager.isExecutableFile(atPath: $0.path)
            let exec1 = fileManager.isExecutableFile(atPath: $1.path)
            if exec0 != exec1 { return exec0 && !exec1 }
            return $0.lastPathComponent < $1.lastPathComponent
        }

        if let pluginFile = candidates.first {
            os_log("Found plugin entry point: %{public}@", log: Log.plugin, type: .debug, pluginFile.path)
            return pluginFile
        }

        os_log("No plugin.* entry point found in %{public}@", log: Log.plugin, type: .error, directory.path)
        return nil
    }

    // MARK: - Plugin Protocol

    func enableTimer() {
        if let nextDate = metadata?.nextDate {
            cronTimer?.invalidate()
            cronTimer = Timer(fireAt: nextDate, interval: 0, target: self,
                              selector: #selector(scheduledContentUpdate), userInfo: nil, repeats: false)
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
                guard let self else { return }
                self.lastRefreshReason = .Schedule
                self.invokeQueue.addOperation(RunPluginOperation<PackagedPlugin>(plugin: self))
            }).store(in: &cancellable)
    }

    func disableTimer() {
        cancellable.forEach { $0.cancel() }
        cancellable.removeAll()
        cronTimer?.invalidate()
        cronTimer = nil
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
        refresh(reason: .FirstLaunch)
    }

    func start() {
        if lastUpdated != nil {
            if let metadata, metadata.nextDate != nil {
                refreshPluginMetadata()
                enableTimer()
            } else if updateInterval > 0, updateInterval < 60 * 60 * 24 * 100 {
                if let lastUpdated {
                    let nextUpdateTime = lastUpdated.addingTimeInterval(updateInterval)
                    if Date() > nextUpdateTime {
                        refresh(reason: .WakeFromSleep)
                    } else {
                        enableTimer()
                    }
                }
            } else {
                refresh(reason: .WakeFromSleep)
            }
        } else {
            refresh(reason: .FirstLaunch)
        }
    }

    func refresh(reason: PluginRefreshReason) {
        guard enabled else {
            os_log("Skipping refresh for disabled plugin\n%{public}@", log: Log.plugin, description)
            return
        }
        os_log("Requesting refresh for packaged plugin\n%{public}@", log: Log.plugin, description)
        debugInfo.addEvent(type: .PluginRefresh, value: "Requesting refresh")
        disableTimer()
        operation?.cancel()

        refreshPluginMetadata()
        lastRefreshReason = reason
        operation = RunPluginOperation<PackagedPlugin>(plugin: self)
        invokeQueue.addOperation(operation!)
    }

    func invoke() -> String? {
        lastUpdated = Date()
        do {
            let out = try runScript(to: mainExecutable.path,
                                    env: env,
                                    workingDirectory: packageDirectory.path,
                                    runInBash: metadata?.shouldRunInBash ?? true)
            error = nil
            lastState = .Success
            os_log("Successfully executed packaged plugin script \n%{public}@", log: Log.plugin, file)
            debugInfo.addEvent(type: .ContentUpdate, value: out.out)
            if let err = out.err, err != "" {
                debugInfo.addEvent(type: .ContentUpdateError, value: err)
                os_log("Error output from the script: \n%{public}@:", log: Log.plugin, err)
            }
            return out.out
        } catch let shellError as ShellOutError {
            os_log("Failed to execute packaged plugin script\n%{public}@\n%{public}@",
                   log: Log.plugin, type: .error, file, shellError.message)
            self.error = shellError
            debugInfo.addEvent(type: .ContentUpdateError, value: shellError.message)
            lastState = .Failed
        } catch {
            os_log("Failed to execute packaged plugin script\n%{public}@\n%{public}@",
                   log: Log.plugin, type: .error, file, error.localizedDescription)
            self.error = error
            lastState = .Failed
        }
        return nil
    }

    @objc func scheduledContentUpdate() {
        refresh(reason: .Schedule)
    }

    // MARK: - Environment

    var env: [String: String] {
        var pluginEnv = [
            Environment.Variables.swiftBarPluginPath.rawValue: file,
            Environment.Variables.osAppearance.rawValue: AppShared.isDarkTheme ? "Dark" : "Light",
            Environment.Variables.swiftBarPluginCachePath.rawValue: cacheDirectoryPath,
            Environment.Variables.swiftBarPluginDataPath.rawValue: dataDirectoryPath,
            Environment.Variables.swiftBarPluginRefreshReason.rawValue: lastRefreshReason.rawValue,
            Environment.Variables.swiftBarPluginPackagePath.rawValue: packageDirectory.path,
        ]

        metadata?.environment.forEach { k, v in
            pluginEnv[k] = v
        }

        for (k, v) in refreshEnv {
            pluginEnv[k] = v
        }
        refreshEnv.removeAll()

        if let variables = metadata?.variables, !variables.isEmpty {
            let userValues = PluginVariableStorage.loadUserValues(pluginFile: file)
            let varEnv = PluginVariableStorage.buildEnvironment(variables: variables, userValues: userValues)
            for (k, v) in varEnv {
                pluginEnv[k] = v
            }
        }

        return pluginEnv
    }
}
