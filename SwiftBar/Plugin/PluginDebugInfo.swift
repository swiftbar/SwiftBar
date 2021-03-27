import Foundation

class PluginDebugInfo: ObservableObject {
    enum EventType: String {
        case ContentUpdate
        case PluginRefresh
        case Environment
        case PluginMetadata
    }

    struct Event {
        let type: EventType
        let value: String

        var eventString: String {
            "\(type): \(value)"
        }
    }

    @Published var events: [Date: Event] = [:]

    func addEvent(type: EventType, value: String) {
        guard PreferencesStore.shared.pluginDebugMode else {
            return
        }
        var newValue = value
        DispatchQueue.main.async { [weak self] in
            if type == .PluginRefresh {
                newValue = """

                ==================================
                \(newValue)
                ==================================

                """
            }
            self?.events[Date()] = Event(type: type, value: newValue)
        }
    }

    func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.events.removeAll()
        }
    }
}
