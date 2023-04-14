import Intents

@available(macOS 11.0, *)
public class SetEphemeralPluginIntentHandler: NSObject, SetEphemeralPluginIntentHandling {
    @MainActor
    public func handle(intent: SetEphemeralPluginIntent) async -> SetEphemeralPluginIntentResponse {
        guard let id = intent.name, let content = intent.content, let exitAfter = intent.exitAfter else {
            return SetEphemeralPluginIntentResponse()
        }
        delegate.pluginManager.setEphemeralPlugin(pluginId: id, content: content, exitAfter: Double(truncating: exitAfter))
        return SetEphemeralPluginIntentResponse()
    }

    public func resolveName(for intent: SetEphemeralPluginIntent) async -> INStringResolutionResult {
        guard let name = intent.name, !name.isEmpty else {
            return INStringResolutionResult.needsValue()
        }
        return INStringResolutionResult.success(with: name)
    }

    public func resolveContent(for intent: SetEphemeralPluginIntent) async -> INStringResolutionResult {
        guard let content = intent.content, !content.isEmpty else {
            return INStringResolutionResult.needsValue()
        }
        return INStringResolutionResult.success(with: content)
    }

    public func resolveExitAfter(for intent: SetEphemeralPluginIntent) async -> INTimeIntervalResolutionResult {
        INTimeIntervalResolutionResult.success(with: TimeInterval(truncating: intent.exitAfter ?? 0))
    }
}
