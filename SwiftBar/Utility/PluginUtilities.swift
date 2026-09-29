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
/// get a few short retries before the failure is published to the menu bar;
/// every other refresh reason keeps the regular fail-fast behavior. The
/// plugin's error state is still recorded between attempts, so a menu opened
/// mid-retry can show the error until a retry recovers or the budget runs out.
func wakeRefreshRetryDelay(reason: PluginRefreshReason, failedAttempts: Int) -> TimeInterval? {
    guard reason == .WakeFromSleep else { return nil }
    let delays: [TimeInterval] = [2, 4, 8]
    guard failedAttempts >= 1, failedAttempts <= delays.count else { return nil }
    return delays[failedAttempts - 1]
}

final class RunPluginOperation<T: Plugin>: Operation {
    weak var plugin: T?
    private weak var queue: OperationQueue?
    private let scheduledTimerGeneration: UInt?
    private let timerRearmLock = NSLock()
    private var timerRearmHandled = false
    /// Refresh reason captured at creation so concurrent changes to the
    /// plugin's shared state cannot alter the retry decision mid-flight.
    private let refreshReason: PluginRefreshReason
    /// Number of attempts of this refresh that already failed before this one.
    private let failedAttempts: Int
    private let retryDelay: (PluginRefreshReason, Int) -> TimeInterval?

    init(plugin: T,
         queue: OperationQueue?,
         reason: PluginRefreshReason? = nil,
         failedAttempts: Int = 0,
         retryDelay: @escaping (PluginRefreshReason, Int) -> TimeInterval? = wakeRefreshRetryDelay(reason:failedAttempts:))
    {
        self.plugin = plugin
        self.queue = queue
        refreshReason = reason ?? plugin.lastRefreshReason
        self.failedAttempts = failedAttempts
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
        guard !isCancelled, let plugin else { return }
        if failedAttempts > 0 {
            // A retry only runs while its failure is still current: the
            // plugin may have been disabled or terminated during the wait,
            // recovered through another refresh path, or entered a new
            // refresh cycle that owns the schedule now.
            guard plugin.enabled, plugin.lastState == .Failed, isCurrentTimerGeneration else { return }
        }
        let previousContent = plugin.content
        let result = plugin.invoke()
        // Check again after invoke - operation may have been cancelled while script was running
        guard !isCancelled else { return }

        if result == nil, plugin.lastState == .Failed,
           let delay = retryDelay(refreshReason, failedAttempts + 1),
           let queue
        {
            scheduleRetry(after: delay, for: plugin, on: queue)
            return
        }

        guard plugin.enabled else { return }
        plugin.content = result
        if failedAttempts > 0, result != nil, result == previousContent {
            // The content didSet guard drops updates with unchanged output,
            // which would leave the error icon up after a recovered retry —
            // publish explicitly so the menu leaves the error state.
            plugin.contentUpdatePublisher.send(result)
        }
    }

    /// Runs the retry chain without occupying an invoke-queue slot during
    /// the wait: the successor operation is created immediately, so a newer
    /// refresh can cancel it through `plugin.operation`, but it is enqueued
    /// only once the backoff delay elapses.
    private func scheduleRetry(after delay: TimeInterval, for plugin: T, on queue: OperationQueue) {
        let successor = RunPluginOperation(plugin: plugin,
                                           queue: queue,
                                           reason: refreshReason,
                                           failedAttempts: failedAttempts + 1,
                                           retryDelay: retryDelay)
        plugin.operation = successor
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak queue] in
            guard !successor.isCancelled else { return }
            queue?.addOperation(successor)
        }
    }

    private var isCurrentTimerGeneration: Bool {
        guard let timerPlugin = plugin as? TimerArmingPlugin else { return true }
        return timerPlugin.timerGeneration == scheduledTimerGeneration
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
