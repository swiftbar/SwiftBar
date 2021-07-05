import AppKit
import Intents

extension AppDelegate {
    @available(macOS 11.0, *)
    func application(_: NSApplication, handlerFor intent: INIntent) -> Any? {
        switch intent {
        case is GetPluginsIntent:
            return GetPluginsIntentHandler()
        default:
            return nil
        }
    }
}
