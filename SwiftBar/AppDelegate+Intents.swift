import AppKit
import Intents

extension AppDelegate {
    @available(macOS 11.0, *)
    func application(_: NSApplication, handlerFor intent: INIntent) -> Any? {
        switch intent {
        case is GetPluginsIntent:
            return GetPluginsIntentHandler()
        case is EnablePluginIntent:
            return EnablePluginIntentHandler()
        case is DisablePluginIntent:
            return DisablePluginIntentHandler()
        case is ReloadPluginIntent:
            return ReloadPluginIntentHandler()
        default:
            return nil
        }
    }
}
