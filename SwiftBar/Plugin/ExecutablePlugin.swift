import Foundation
import Combine
import ShellOut

class ExecutablePlugin: Plugin {
    var id: PluginID {
        return file
    }
    let type: PluginType = .Executable
    let name: String
    let file: String
    var updateInterval: Double = 60
    let metadata: PluginMetadata?
    var lastUpdated: Date? = nil
    var lastRefreshSuccesseful:Bool = false
    var refreshPublisher = PassthroughSubject<Any, Never>()

    var content: String? {
        didSet {
            guard content != oldValue else {return}
            refreshPublisher.send("")
        }
    }
    var error: String?


    let queue = DispatchQueue(label: "PluginQueue")
    var updateTimerPublisher: Timer.TimerPublisher {
        return Timer.TimerPublisher(interval: updateInterval, runLoop: .main, mode: .default)
    }

    var cancellable: AnyCancellable? = nil

    init(fileURL: URL) {
        let nameComponents = fileURL.lastPathComponent.components(separatedBy: ".")
        self.name = nameComponents.first ?? ""
        self.file = fileURL.absoluteString
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

        refresh()
    }

    func enableTimer() {
        cancellable?.cancel()
        cancellable = updateTimerPublisher
            .autoconnect()
            .receive(on: queue)
            .sink(receiveValue: {[weak self] _ in
                self?.content = self?.invoke(params: [])
            })
    }

    func disableTimer() {
        cancellable?.cancel()
    }

    func refresh() {
        disableTimer()
        content = invoke(params: [])
        enableTimer()
    }

    func terminate() {

    }

    func invoke(params : [String]) -> String? {
        do {
            let out = try shellOut(to: String(file.dropFirst(7)))
            self.error = nil
            return out
        } catch {
            guard let error = error as? ShellOutError else {return nil}
            print(error.message)
            self.error = error.message
        }
        return nil
    }
}
