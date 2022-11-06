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

    init(plugin: T) {
        self.plugin = plugin
        super.init()
    }

    override func main() {
        guard !isCancelled else { return }
        plugin?.content = plugin?.invoke()
        (plugin as? ExecutablePlugin)?.enableTimer()
        (plugin as? ShortcutPlugin)?.enableTimer()
    }
}
