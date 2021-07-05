import Intents

public class GetPluginsIntentHandler: NSObject, GetPluginsIntentHandling {
    @available(macOS 11.0, *)
    public func handle(intent _: GetPluginsIntent, completion: @escaping (GetPluginsIntentResponse) -> Void) {
        let plugins = delegate.pluginManager.plugins.map { SKPlugin(identifier: $0.id, display: $0.name) }
        completion(GetPluginsIntentResponse.success(plugins: plugins))
    }
}
