import Cocoa

let delegate = AppDelegate()
let menu = AppMenu()
NSApplication.shared.mainMenu = menu
NSApplication.shared.delegate = delegate

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
