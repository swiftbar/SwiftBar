import AppKit
import Intents

extension AppDelegate {
    @available(macOS 11.0, *)
    func application(_: NSApplication, handlerFor intent: INIntent) -> Any? {
        switch intent {
        case is GetPluginsIntent:
            GetPluginsIntentHandler()
        case is EnablePluginIntent:
            EnablePluginIntentHandler()
        case is DisablePluginIntent:
            DisablePluginIntentHandler()
        case is ReloadPluginIntent:
            ReloadPluginIntentHandler()
        case is SetEphemeralPluginIntent:
            SetEphemeralPluginIntentHandler()
        default:
            nil
        }
    }
}
