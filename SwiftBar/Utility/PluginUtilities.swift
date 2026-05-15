import Foundation

func parseRefreshInterval(intervalStr: String, baseUpdateinterval: Double) -> Double? {
    guard let interval = Double(intervalStr.filter("0123456789.".contains)) else { return nil }
    var updateInterval: Double = baseUpdateinterval

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

    return updateInterval
}

final class RunPluginOperation<T: Plugin>: Operation {
    weak var plugin: T?
    private let scheduledTimerGeneration: UInt?
    private let timerRearmLock = NSLock()
    private var timerRearmHandled = false

    init(plugin: T) {
        self.plugin = plugin
        scheduledTimerGeneration = (plugin as? TimerArmingPlugin)?.timerGeneration
        super.init()
    }

    override func cancel() {
        super.cancel()
        if !isExecuting {
            rearmTimerIfCurrent()
        }
    }

    override func main() {
        defer { rearmTimerIfCurrent() }
        guard !isCancelled else { return }
        let result = plugin?.invoke()
        // Check again after invoke - operation may have been cancelled while script was running
        guard !isCancelled else { return }
        plugin?.content = result
    }

    private func rearmTimerIfCurrent() {
        timerRearmLock.lock()
        guard !timerRearmHandled else {
            timerRearmLock.unlock()
            return
        }
        timerRearmHandled = true
        timerRearmLock.unlock()

        guard let timerPlugin = plugin as? TimerArmingPlugin,
              timerPlugin.timerArmingEnabled,
              timerPlugin.timerGeneration == scheduledTimerGeneration
        else {
            return
        }
        timerPlugin.enableTimer()
    }
}
