import Intents

public class ReloadPluginIntentHandler: NSObject, ReloadPluginIntentHandling {
    @available(macOS 11.0, *)
    public func handle(intent: ReloadPluginIntent, completion: @escaping (ReloadPluginIntentResponse) -> Void) {
        guard let pluginID = intent.plugin?.identifier,
              let plugin = delegate.pluginManager.plugins.first(where: { $0.id == pluginID })
        else {
            completion(ReloadPluginIntentResponse(code: .failure, userActivity: nil))
            return
        }
        plugin.refresh()
        completion(ReloadPluginIntentResponse(code: .success, userActivity: nil))
    }

    @available(macOS 11.0, *)
    public func resolvePlugin(for intent: ReloadPluginIntent, with completion: @escaping (SKPluginResolutionResult) -> Void) {
        guard let plugin = intent.plugin else {
            completion(.needsValue())
            return
        }
        completion(.success(with: plugin))
    }

    @available(macOS 11.0, *)
    public func providePluginOptionsCollection(for _: ReloadPluginIntent, with completion: @escaping (INObjectCollection<SKPlugin>?, Error?) -> Void) {
        let plugins = delegate.pluginManager.plugins.map { SKPlugin(identifier: $0.id, display: $0.name) }
        completion(INObjectCollection(items: plugins), nil)
    }
}
