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

/// Delay before re-running a plugin invocation that just failed, or nil when
/// the failure should surface immediately.
///
/// A wake-from-sleep refresh races the network stack coming back up, so
/// network-dependent plugins can fail spuriously right after wake. Such runs
/// get a few short retries before the error state reaches the menu bar;
/// every other refresh reason keeps the regular fail-fast behavior.
func wakeRefreshRetryDelay(reason: PluginRefreshReason, failedAttempts: Int) -> TimeInterval? {
    guard reason == .WakeFromSleep else { return nil }
    let delays: [TimeInterval] = [2, 4, 8]
    guard failedAttempts >= 1, failedAttempts <= delays.count else { return nil }
    return delays[failedAttempts - 1]
}

final class RunPluginOperation<T: Plugin>: Operation {
    weak var plugin: T?
    private let scheduledTimerGeneration: UInt?
    private let timerRearmLock = NSLock()
    private var timerRearmHandled = false
    private let retryDelay: (PluginRefreshReason, Int) -> TimeInterval?

    init(plugin: T, retryDelay: @escaping (PluginRefreshReason, Int) -> TimeInterval? = wakeRefreshRetryDelay(reason:failedAttempts:)) {
        self.plugin = plugin
        self.retryDelay = retryDelay
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
        var result = plugin?.invoke()
        var failedAttempts = 1
        while result == nil,
              let plugin,
              plugin.lastState == .Failed,
              let delay = retryDelay(plugin.lastRefreshReason, failedAttempts)
        {
            guard waitUnlessCancelled(for: delay) else { return }
            result = plugin.invoke()
            failedAttempts += 1
        }
        // Check again after invoke - operation may have been cancelled while script was running
        guard !isCancelled else { return }
        plugin?.content = result
    }

    /// Sleeps for the given interval in short slices so cancellation is
    /// noticed promptly. Returns false when the operation was cancelled.
    private func waitUnlessCancelled(for delay: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(delay)
        while Date() < deadline {
            if isCancelled { return false }
            Thread.sleep(forTimeInterval: min(0.1, max(0, deadline.timeIntervalSinceNow)))
        }
        return !isCancelled
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
