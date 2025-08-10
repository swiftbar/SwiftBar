# SwiftBar Development Guide

## Build Commands
- Open project: `open SwiftBar/SwiftBar.xcodeproj`
- Build: Press "Play" in Xcode
- Test: Run unit tests through Xcode's Test Navigator
- Debug: Enable Plugin Debug Mode with `defaults write com.ameba.SwiftBar PluginDebugMode -bool YES`

## Code Style Guidelines
- **Imports**: Group by standard libraries first, then third-party libraries
- **Naming**: Use descriptive camelCase variables, PascalCase for types
- **Types**: Swift strong typing with proper optionals handling
- **Error Handling**: Use do/catch blocks, proper error propagation
- **File Organization**: Keep related functionality in dedicated files
- **UI**: Use SwiftUI for new UI components when possible
- **Comments**: Document public APIs and complex logic
- **Dependencies**: SwiftBar uses HotKey, LaunchAtLogin, Preferences, Sparkle, SwiftCron

## Terminal Support
SwiftBar supports running scripts in these terminals:
- macOS Terminal.app
- iTerm2
- Ghostty

## Environment Variables
SWIFTBAR_VERSION, SWIFTBAR_BUILD, SWIFTBAR_PLUGINS_PATH, SWIFTBAR_PLUGIN_PATH, 
SWIFTBAR_PLUGIN_CACHE_PATH, SWIFTBAR_PLUGIN_DATA_PATH, SWIFTBAR_PLUGIN_REFRESH_REASON,
OS_APPEARANCE, OS_VERSION_MAJOR, OS_VERSION_MINOR, OS_VERSION_PATCH