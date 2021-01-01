<p align="center">
 <img width="155" height="150" alt="SwiftBar Logo" src="Resources/logo.png">
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
brew tap melonamin/formulae
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
 <img width="600" height="500" alt="A screenshot of SwiftBar’s Plugin Repository" src="Resources/Plugin Repository.jpg">
</p>


## Creating Plugins

To add a new plugin to SwiftBar, you need to create an executable script following the required format (see below) and put it into `Plugin Folder`. 

### Plugin Folder

With the first launch, Swiftbar will ask you to set the `Plugin Folder`. SwiftBar will try to import every file in this folder as a plugin.

**Important**:
* hidden folders are ignored
* nested folders are traversed by SwiftBar

### Plugin Naming

Plugin files must adopt the following format:

```
{name}.{time}.{ext}
```

* **name** - Anything you want.
* **time** - Refresh interval (optional). Should be a number + duration modifier (see below)
* **ext** - File extension.

Duration modifiers:
* **s** - seconds, e.g. 1s - refresh every second
* **m** - minute, e.g. 10m - refresh every ten minutes
* **h** - hour, e.g. 3h - refresh every three hours
* **d** - day, e.g. 1d - refresh every day

Example filename: `date.1m.sh`

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
---
echo "This is not a Menu Title, this will be showed in the drop-down menu only"
```

Script output for both header and body is split by line (`\n`). Each line must follow this format:
```
<Item Title> | [param = ...] 
```
Where:
- **"Item Title"** can be any string, this will be used as a menu item title.
- **[param = ...]** is an optional set of parameters\modificators. Each parameter is a key-value separated by `=`. Use `|` to separate parameters from the title.

Here is the list of supported parameters:

**Text Formatting**:
| Parameter | Value | Description |
| ------------- | ------------- |------------- | 
| `color` | CSS color or HEX, `light_color,dark_color` | Sets item text color. If only one color is provided, it is used for both light and dark appearance. |
| `sfcolor` | CSS color or HEX, `light_color,dark_color` | Sets SF Symbol color. If only one color is provided, it is used for both light and dark appearance. |
| `font` | macOS font name | Sets font name to use in item text |
| `size` | Number | Sets item text size |
| `length`| Number | Trims item text to a provided number of characters. The full title will be displayed in a tooltip. |
| `trim` | True | Trims whitespace characters |
| `ansi` | True | Enables support of ANSI color codes. **Conflicts with:** `symbolize` |
| `emojize` | False | Disables parsing of GitHub style Emojis (e.g., `:mushroom:` into 🍄). **Requires:** `symbolize=false`. |
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
| `shortcut` | <kbd style="font-size:medium"><kbd style="font-size:medium">⌘</kbd>+<kbd style="font-size:medium">⌥</kbd>+<kbd style="font-size:medium">T</kbd></kbd> | Hotkey assigned to item. If item is in header, hotkey will show the menu; otherwise, hotkey will launch associated action. |

### Environment Variables

When running a plugin, SwiftBar sets the following environment variables:
| Variable | Value |
| -------- | ----- |
| `SWIFTBAR` | `1` |
| `SWIFTBAR_VERSION` | The running SwiftBar version number (in `x.y.z` format) |
| `SWIFTBAR_BUILD` | The running SwiftBar build number (`CFBundleVersion`) |
| `SWIFTBAR_PLUGINS_PATH` | The path to the `Plugin Folder` |
| `SWIFTBAR_PLUGIN_PATH` | The path to the running plugin |
| `OS_APPEARANCE` | Current macOS appearance (`Light` or `Dark`) |
| `OS_VERSION_MAJOR` | The first part of the macOS version (e.g., `11` for macOS 11.0.1). |
| `OS_VERSION_MINOR` | The second part of the macOS version (e.g., `0` for macOS 11.0.1). |
| `OS_VERSION_PATCH` | The third part of the macOS version (e.g., `1` for macOS 11.0.1). |

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
# <bitbar.droptypes>Supported UTI's for dropping things on menu bar</droptypes.abouturl>

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


## URL Scheme
| Endpoint | Parameter | Description | Example |
| ------------- | ------------- |------------- | ------------- | 
| refreshallplugins | none | Force refresh all loaded plugins | `swiftbar://refreshallplugins` |
| refreshplugin | `name` plugin [name](#plugin-naming) | Force refresh plugin by name | `swiftbar://refreshplugin?name=myplugin` |
| refreshplugin | `index` plugin index in menubar, starting from `0` | Force refresh plugin by its position in menubar | `swiftbar://refreshplugin?index=1` |
| addplugin | `src` source URL to plugin file | Add plugin to Swiftbar from URL | `swiftbar://addplugin?src=https://coolplugin` |
| notify | `plugin` plugin [name](#plugin-naming), notification fields `title`, `subtitle`, `body` and disable sound `silent=true` | Show notification | `swiftbar://notify?plugin=MyPlugin&title=title&subtitle=subtitle&body=body&silent=true` |



## Logs and Error

If plugin fails to run SwiftBar will show ⚠️ in the menu bar, you can see details by clicking on Error in dropdown menu.
Use macOS `Console.app` to view SwiftBar logs.

## Acknowledgements

SwiftBar uses these open source libraries:
* [HotKey](https://github.com/soffes/HotKey)
* [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin)
* [Sparkle](https://github.com/sparkle-project/Sparkle)
* [ShellOut](https://github.com/JohnSundell/ShellOut)

To freeze and secure dependencies these libraries are forked to SwiftBar organization.
