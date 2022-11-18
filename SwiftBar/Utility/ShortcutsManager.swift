import AppKit
import Combine
import Foundation
import ScriptingBridge

public struct RunShortcutError: Swift.Error {
    public enum FailReason {
        case NoPermissions
        case ShortcutNotFound
        case NoShortcutOutput
        case CantParseShortcutOutput
    }

    public let errorReason: FailReason
    public var message: String
}

@objc protocol ShortcutsEvents {
    @objc optional var shortcuts: SBElementArray { get }
}

@objc protocol Shortcut {
    @objc optional var name: String { get }
    @objc optional func run(withInput: Any?) -> Any?
}

extension SBApplication: ShortcutsEvents {}
extension SBObject: Shortcut {}

public class ShortcutsManager: ObservableObject {
    static let shared = ShortcutsManager()
    var task: Process?
    var shortcutsURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
    var shellURL = URL(fileURLWithPath: "/bin/zsh")
    var prefs = PreferencesStore.shared
    var cancellable: AnyCancellable?

    @Published public var shortcuts: [String] = []
    @Published public var folders: [String] = []

    lazy var shortcutInputPath: URL = {
        let directory = NSTemporaryDirectory()
        return NSURL.fileURL(withPathComponents: [directory, "shortcutInput"])!
    }()

    public init() {
        if #available(macOS 12, *) {
            getShortcutsFolders()
            getShortcuts()
            cancellable = prefs.$shortcutsFolder.receive(on: RunLoop.main).sink { [weak self] folder in
                self?.getShortcuts(folder: folder)
            }
        }
    }

    public func getShortcuts(folder: String? = nil) {
        task = Process()
        task?.executableURL = shortcutsURL
        task?.arguments = ["list", "-f", "\(folder ?? prefs.shortcutsFolder)"]

        let pipe = Pipe()
        task?.standardOutput = pipe
        task?.launch()
        task?.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        shortcuts = output.components(separatedBy: .newlines).sorted()
    }

    public func getShortcutsFolders() {
        task = Process()
        task?.executableURL = shortcutsURL
        task?.arguments = ["list", "--folders"]

        let pipe = Pipe()
        task?.standardOutput = pipe
        task?.launch()
        task?.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        folders = output.components(separatedBy: .newlines).sorted()
    }

    public func runShortcut(shortcut: String, input: Any? = nil) throws -> String {
        guard let app: ShortcutsEvents? = SBApplication(bundleIdentifier: "com.apple.shortcuts.events") else {
            throw RunShortcutError(errorReason: .NoPermissions, message: "Can't access Shortcuts.app, please verify the permissions")
        }
        guard let shortcut = app?.shortcuts?.object(withName: shortcut) as? Shortcut else {
            throw RunShortcutError(errorReason: .ShortcutNotFound, message: "Can't find shortcut named \(shortcut).")
        }

        let res = shortcut.run?(withInput: input)
        guard let res else {
            throw RunShortcutError(errorReason: .NoShortcutOutput, message: "Shortcut \(shortcut) didn't produced output.")
        }
        guard let out = (res as? [String])?.first else {
            throw RunShortcutError(errorReason: .CantParseShortcutOutput, message: "Shortcut \(shortcut) produced unparsable result - \(res)")
        }

        return out
    }

    public func viewCurrentShortcut(shortcut: String) {
        task = Process()
        task?.executableURL = shellURL
        task?.arguments = ["-c", "-l", "shortcuts view '\(shortcut)'"]

        task?.launch()
        task?.waitUntilExit()
    }

    public func createShortcut() {
        NSWorkspace.shared.open(URL(string: "shortcuts://create-shortcut")!)
    }

    public func refresh() {
        getShortcutsFolders()
        getShortcuts()
    }
}
