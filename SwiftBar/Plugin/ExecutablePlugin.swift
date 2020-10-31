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
    var contentUpdatePublisher = PassthroughSubject<Any, Never>()

    var content: String? = "..." {
        didSet {
            guard content != oldValue else {return}
            contentUpdatePublisher.send("")
        }
    }
    var error: String?


    let queue = DispatchQueue(label: "PluginQueue")
    var updateTimerPublisher: Timer.TimerPublisher {
        return Timer.TimerPublisher(interval: updateInterval, runLoop: .main, mode: .default)
    }

    var cancellable: Set<AnyCancellable> = []

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
        disableTimer()
        queue.async { [weak self] in
            self?.content = self?.invoke(params: [])
            self?.enableTimer()
        }
    }

    func terminate() {

    }

    func invoke(params : [String]) -> String? {
        lastUpdated = Date()
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
