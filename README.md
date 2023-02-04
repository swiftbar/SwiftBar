[![GitHub license](https://img.shields.io/github/license/swiftbar/SwiftBar.svg)](https://github.com/swiftbar/SwiftBar/blob/master/LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/swiftbar/SwiftBar)](https://github.com/swiftbar/SwiftBar/releases/latest)
[![Github all releases](https://img.shields.io/github/downloads/swiftbar/SwiftBar/total.svg)](https://github.com/swiftbar/SwiftBar/releases/)


<p align="center">
 <img width="155" alt="SwiftBar Logo" src="Resources/logo.png">
</p>

# SwiftBar

Add custom menu bar programs on macOS in three easy steps:
- Write a shell script
- Add it to SwiftBar
- ... there is no 3rd step!

You can get plugins from awesome [BitBar repository](https://github.com/matryer/bitbar-plugins), or in SwiftBar itself using the `Get Plugins...` menu item.

## How to get SwiftBar
Download from [GitHub Releases](https://github.com/swiftbar/SwiftBar/releases)

or Install with Homebrew

```
brew install swiftbar
```

Runs on macOS Catalina (10.15) and up.

## ...or build it from source
- Clone or download a copy of this repository
- Open `SwiftBar/SwiftBar.xcodeproj`
- Press play

## Plugin Repository

SwiftBar is bundled with a Plugin Repository. You can access it at Swiftbar → Get Plugins...

<p align="center">
 <img width="600" alt="A screenshot of SwiftBar’s Plugin Repository" src="https://user-images.githubusercontent.com/222100/110520713-d5058000-80dc-11eb-9b15-baa09cb445bf.png">
</p>

If you want to add\remove plugin or have other questions about repository content please refer to this [issue](https://github.com/swiftbar/swiftbar-plugins/issues/1).

## Creating Plugins

To add a new plugin to SwiftBar, you need to create an executable script following the required format (see below) and put it into `Plugin Folder`. 

### Plugin Folder

With the first launch, Swiftbar will ask you to set the `Plugin Folder`. SwiftBar will try to import every file in this folder as a plugin.

**Important**:
* hidden folders are ignored
* nested folders are traversed by SwiftBar, including symlinks

You can hide a folder by prepending `.` or using this command `chflags hidden <folder name>`.

### Plugin Naming

Plugin files must adopt the following format:

```
{name}.{time}.{ext}
```

* **name** - Anything you want.
* **time** - Refresh interval (optional). Should be a number + duration modifier (see below)
* **ext** - File extension.

Duration modifiers:
* **ms** - milliseconds, e.g. 1ms - refresh every millisecond
* **s** - seconds, e.g. 1s - refresh every second
* **m** - minute, e.g. 10m - refresh every ten minutes
* **h** - hour, e.g. 3h - refresh every three hours
* **d** - day, e.g. 1d - refresh every day

Example filename: `date.1m.sh`

Whether you are using a plugin from the plugin repository, or creating your own, plugins will initially appear in the menu bar in no pre-determined order. However, you can reorder how they appear by holding down <kbd>Cmd</kbd> and dragging them (this process can sometimes also be used on some other non-SwiftBar icons in the menu bar too). Plugin position will be remembered unless you change the name of the plugin file, in which case they'll need to be re-positioned again.

## Plugin API

Plugin is an executable script in the language of your choice. When SwiftBar detects a new file in `Plugin Folder` it makes this file executable if needed and runs it. 

Script should produce output (`STDOUT`) in the required format (see next chapter). Script errors should be redirected to `STDERR`.

Plugin API is adopted from the [BitBar](https://github.com/matryer/bitbar), which means that SwiftBar can run any existing BitBar plugin.

### Script Output

When parsing plugin output SwiftBar recognizes the following blocks:
- **Header**: responsible for what you see in the menu bar
- **Body**: responsible for dropdown menu contents

`Header` is everything before first `---`. Each `---` after the first one will be interpreted as a menu separator.
You have one or more lines in the header.

The simplest plugin looks like this:

```bash
echo "This is Menu Title"
```

If you provide multiple titles, the provided titles will be cycled in the menu bar and shown in the dropdown menu:

```bash
echo "This is a primary Menu Title"
echo "This is a secondary Menu Title"
echo "This is a n-th Menu Title"
echo "---"
echo "This is not a Menu Title, this will be showed in the drop-down menu only"
```

Script output for both header and body is split by line (`\n`). Each line must follow this format:
```
<Item Title> | [param = ...] 
```
Where:
- **"Item Title"** can be any string, this will be used as a menu item title.
- **[param = ...]** is an optional set of parameters\modificators. Each parameter is a key-value separated by `=`. Use `|` to separate parameters from the title.


#### Parameters

**Text Formatting**:
| Parameter | Value | Description |
| ------------- | ------------- |------------- | 
| `color` | CSS color or HEX, `light_color,dark_color` | Sets item text color. If only one color is provided, it is used for both light and dark appearance. |
| `sfcolor` | CSS color or HEX, `light_color,dark_color` | Sets SF Symbol color. If only one color is provided, it is used for both light and dark appearance. If you fame multiple SF Symbols you can provide different colors by adding index, like this `sfcolor2` |
| `font` | macOS font name | Sets font name to use in item text |
| `size` | Number | Sets item text size |
| `md` | True | Enables markdown support in menu title for `**bold**` and `*italic*` |
| `sfsize` | Number | Sets size for SF Symbol image embedded in text|
| `length`| Number | Trims item text to a provided number of characters. The full title will be displayed in a tooltip. |
| `trim` | True | Trims whitespace characters |
| `ansi` | True | Enables support of ANSI color codes. **Conflicts with:** `symbolize` |
| `emojize` | False | Disables parsing of GitHub style Emojis (e.g., `:mushroom:` into 🍄). **Requires:** `symbolize=false` when setting to true. |
| `symbolize` | False | Disables parsing of [SF Symbols](https://developer.apple.com/sf-symbols/) (e.g., `"SF Symbols Test :sun.max: :cloud.fill: :gamecontroller.fill: :bookmark: :sun.dust:"` → <img width="218" alt="Screenshot of SF Symbols" src="https://user-images.githubusercontent.com/222100/102021898-2d80e780-3d51-11eb-9e99-c71e92d14837.png">). Always `False` on Catalina. |

**Visuals**:
| Parameter | Value | Description |
| ------------- | ------------- |------------- | 
| `dropdown` | False | Only applicable to items in `Header`. When set to False, item will not be displayed in dropdown menu, but will be cycled in the menu bar. |
| `alternate` | True | Marks a line as an alternative to the previous one for when the Option key (<kbd style="font-size:medium">⌥</kbd>) is pressed in the dropdown.|
| `image` | Image encoded in Base64| Sets an image for item.|
| `templateImage` | Image encoded in Base64| Same as `image`, but the image is a template image. Template images consist of black and clear colors (and an alpha channel). Template images are not intended to be used as standalone images and are usually mixed with other content to create the desired final appearance.|
| `sfimage` | SFSymbol name| Sets an image for item from [SF Symbol](https://developer.apple.com/sf-symbols/). Only available on Big Sur and above.|
| `checked` | True | Sets a checkmark in front of the item.|
| `tooltip` | Text | Sets a tooltip for the item. |

**Actions**:
| Parameter | Value | Description |
| ------------- | ------------- |------------- | 
| `refresh` | True | Plugin Script will be executed on item click |
| `href` | Absolute URL | Sets an URL to open when item clicked |
| `bash` | Absolute file path | Executable script to run in Shell |
| `terminal` | False | `bash` script will be run in the background, instead of launching the Terminal |
| `params` | `param0=`,`param1=`,`param10=`... | Parameters for `bash` script |
| `shortcut` | CMD+OPTION+T | Hotkey assigned to item. If item is in header, hotkey will show the menu; otherwise, hotkey will launch associated action. |

### Environment Variables

When running a plugin, SwiftBar sets the following environment variables:
| Variable | Value |
| -------- | ----- |
| `SWIFTBAR` | `1` |
| `SWIFTBAR_VERSION` | The running SwiftBar version number (in `x.y.z` format) |
| `SWIFTBAR_BUILD` | The running SwiftBar build number (`CFBundleVersion`) |
| `SWIFTBAR_PLUGINS_PATH` | The path to the `Plugin Folder` |
| `SWIFTBAR_PLUGIN_PATH` | The path to the running plugin |
| `SWIFTBAR_PLUGIN_CACHE_PATH` | The cache to data folder, individual per plugin |
| `SWIFTBAR_PLUGIN_DATA_PATH` | The path to data folder, individual per plugin |
| `SWIFTBAR_LAUNCH_TIME` | SwiftBar launch date and time, ISO8601 |
| `OS_APPEARANCE` | Current macOS appearance (`Light` or `Dark`) |
| `OS_VERSION_MAJOR` | The first part of the macOS version (e.g., `11` for macOS 11.0.1) |
| `OS_VERSION_MINOR` | The second part of the macOS version (e.g., `0` for macOS 11.0.1) |
| `OS_VERSION_PATCH` | The third part of the macOS version (e.g., `1` for macOS 11.0.1) |
| `OS_LAST_SLEEP_TIME` | Last OS sleep date and time, ISO8601. Empty if OS didn't sleep since SwiftBar launch. |
| `OS_LAST_WAKE_TIME` | Last OS wake from sleep date and time, ISO8601. Empty if OS didn't sleep since SwiftBar launch. |

### Script Metadata

It is recommended to include metadata in plugin script. Metadata is used in the About Plugin screen in SwiftBar. 
SwiftBar adopts metadata format suggested by BitBar:
```
# <bitbar.title>Title goes here</bitbar.title>
# <bitbar.version>v1.0</bitbar.version>
# <bitbar.author>Your Name</bitbar.author>
# <bitbar.author.github>your-github-username</bitbar.author.github>
# <bitbar.desc>Short description of what your plugin does.</bitbar.desc>
# <bitbar.image>http://www.hosted-somewhere/pluginimage</bitbar.image>
# <bitbar.dependencies>python,ruby,node</bitbar.dependencies>
# <bitbar.abouturl>http://url-to-about.com/</bitbar.abouturl>
# <bitbar.droptypes>Supported UTI's for dropping things on menu bar</bitbar.droptypes>
```

#### Hiding default items

SwiftBar supports these optional metadata flags to hide default menu items:
```
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>
```

Option+Click will show all items:
![SwiftBar](https://user-images.githubusercontent.com/222100/101261866-267e2780-3708-11eb-9042-a57ad0ac6c78.gif)

#### Refresh schedule

A special tag can be used as an alternative to refresh interval defined in plugin's [name](#plugin-naming), value adopts Cron syntax:

```
<swiftbar.schedule>01,16,31,46 * * * *</swiftbar.schedule>
```

You can configure multiple schedules, using the sepparator `|`:

```
<swiftbar.schedule>1 * * * *|2 * * * *</swiftbar.schedule>
```


#### Other Parameters

* `#<swiftbar.refreshOnOpen>true</swiftbar.refreshOnOpen>` - refreshes plugin on click, before presenting the menu
* `<swiftbar.runInBash>false</swiftbar.runInBash>` - doesn't wrap plugins in Bash when running
* `<swiftbar.type>streamable</swiftbar.type>` - mark plugin as Streamable
* `<swiftbar.environment>[var1:default value, var2:default value, ... ]</swiftbar.environment>` - this variables will be passed in plugin's environment, in later release SwiftBar will provide a UI to change values for these variables.

#### Metadata for Binary Plugins

For binary plugins metadata can be added as an extended file attribute:

`xattr -w "com.ameba.SwiftBar" "$(cat metadata.txt | base64)" <plugin_file>`

## Plugin Types
### Standard (default)

For Standard type of plugins, SwiftBar expects that plugin execution is finite, i.e., plugin runs and exits with output to stdout:

- exit with code 0 and non-empty stdout - menu bar is built from the output
- exit with code 0 and empty stdout - nothing in the menu bar
- exit with code 1 - error shown in the menu bar

Optionally, a standard plugin can be run on a repeatable schedule, configured in the plugin's file name or `schedule` metadata property.

### Streamable

Swiftbar launches a separate process for each Streamable plugin, which runs indefinitely until SwiftBar is closed or a failure.
You should use Streamable plugins only when dealing with a stream of incoming events; an example could be financial market info read from a websocket or CPU load information for a remote computer.

To let SwiftBar know when to update the menu bar item, Streamable plugins must use a special line separator `~~~`. SwiftBar will reset the menu item on each occurrence of this separator. 

In the example below, SwiftBar will show "Test 1" in the menu bar for 3 seconds, then nothing for 5 seconds, and "Test 2" indefinitely.

```
#!/bin/bash
#<swiftbar.type>streamable</swiftbar.type>

echo "Test 1"
echo "---"
echo "Test 2"
echo "Test 3"
sleep 3
echo "~~~"
sleep 5
echo "~~~"
echo "Test 2"
```

You can mark a plugin as streamable with a special metadata property `<swiftbar.type>streamable</swiftbar.type>`

## URL Scheme

Some notes:

* Instead of the plugin [name](#plugin-naming), you can (and probably should) use the plugin file name. This considered a unique plugin ID, whereas `name` can be the same between multiple plugins. If your plugin's filepath is `~/Documents/SwiftBar/myplugin.1m.sh`, then the name is `myplugin` and the ID `myplugin.1m.sh`
* When using `open(1)` to trigger scheme URLs, use `-g` to prevent the command from stealing focus from your active app.

| Endpoint | Parameter | Description | Example |
| ------------- | ------------- |------------- | ------------- | 
| refreshallplugins | none | Force refresh all loaded plugins | `swiftbar://refreshallplugins` |
| refreshplugin | `name` or `plugin` plugin [name](#plugin-naming) | Force refresh plugin by name | `swiftbar://refreshplugin?name=myplugin` |
| refreshplugin | `index` plugin index in menubar, starting from `0` | Force refresh plugin by its position in menubar | `swiftbar://refreshplugin?index=1` |
| enableplugin | `name` or `plugin` plugin [name](#plugin-naming) | Enable plugin by name | `swiftbar://enableplugin?name=myplugin` |
| disableplugin | `name` or `plugin` plugin [name](#plugin-naming) | Disable plugin by name | `swiftbar://disableplugin?name=myplugin` |
| toggleplugin | `name` or `plugin` plugin [name](#plugin-naming) | Toggle(enable\disable) plugin by name | `swiftbar://toggleplugin?name=myplugin` |
| addplugin | `src` source URL to plugin file | Add plugin to Swiftbar from URL | `swiftbar://addplugin?src=https://coolplugin` |
| notify | `name` or `plugin` plugin [name](#plugin-naming). Notification fields: `title`, `subtitle`, `body`. `href` to open an URL on click (including custom URL schemes). `silent=true` to disable sound | Show notification | `swiftbar://notify?plugin=MyPlugin&title=title&subtitle=subtitle&body=body&silent=true` |

## Preferences aka 'defaults'

List of preferences that are not exposed in SwiftBar UI:
* `defaults write com.ameba.SwiftBar StealthMode -bool YES` - hides SwiftBar menu item when all plugins are disabled 
* `defaults write com.ameba.SwiftBar DisableBashWrapper -bool YES` - doesn't wrap plugins in Bash when running
* `defaults write com.ameba.SwiftBar MakePluginExecutable -bool NO` - disables auto `chmod +x` all files in Plugin Directory
* `defaults write com.ameba.SwiftBar PluginDeveloperMode -bool YES` - enables editing in Preferences -> Plugins
* `defaults write com.ameba.Swiftbar PluginDebugMode -bool YES` - enables Plugin Debug View
* `defaults write com.ameba.SwiftBar StreamablePluginDebugOutput -bool YES` - enables debug output for Streamable plugins, Swiftbar will expose the stream data in Console.App

## Logs and Error

If plugin fails to run SwiftBar will show ⚠️ in the menu bar, you can see details by clicking on Error in dropdown menu.
Use macOS `Console.app` to view SwiftBar logs.

## Acknowledgements

SwiftBar uses these open source libraries:
* [HotKey](https://github.com/soffes/HotKey)
* [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin)
* [Preferences](https://github.com/sindresorhus/Preferences)
* [Sparkle](https://github.com/sparkle-project/Sparkle)
* [SwiftCron](https://github.com/MihaelIsaev/SwifCron)

To freeze and secure dependencies these libraries are forked to SwiftBar organization.

## Translation/Localization
SwiftBar can be translated [here](https://github.com/swiftbar/SwiftBar/tree/main/SwiftBar/Resources/Localization).

## More Apps

If you enjoy SwiftBar you may like these as well:
* [TRex](https://github.com/amebalabs/TRex) - Easy to use text extraction tool for macOS
* [Esse](https://github.com/amebalabs/Esse) - Swiss army knife of text transformation for iOS and macOS

