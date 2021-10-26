import Intents

public class DisablePluginIntentHandler: NSObject, DisablePluginIntentHandling {
    @available(macOS 11.0, *)
    public func handle(intent: DisablePluginIntent, completion: @escaping (DisablePluginIntentResponse) -> Void) {
        guard let pluginID = intent.plugin?.identifier,
              let plugin = delegate.pluginManager.plugins.first(where: { $0.id == pluginID })
        else {
            completion(DisablePluginIntentResponse(code: .failure, userActivity: nil))
            return
        }
        delegate.pluginManager.disablePlugin(plugin: plugin)
        completion(DisablePluginIntentResponse(code: .success, userActivity: nil))
    }

    @available(macOS 11.0, *)
    public func resolvePlugin(for intent: DisablePluginIntent, with completion: @escaping (SKPluginResolutionResult) -> Void) {
        guard let plugin = intent.plugin else {
            completion(.needsValue())
            return
        }
        completion(.success(with: plugin))
    }

    @available(macOS 11.0, *)
    public func providePluginOptionsCollection(for _: DisablePluginIntent, with completion: @escaping (INObjectCollection<SKPlugin>?, Error?) -> Void) {
        let plugins = delegate.pluginManager.plugins.map { SKPlugin(identifier: $0.id, display: $0.name) }
        completion(INObjectCollection(items: plugins), nil)
    }
}
