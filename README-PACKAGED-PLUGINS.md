# SwiftBar Packaged Plugins

SwiftBar now supports packaged plugins, which allow you to organize related files into a single plugin package rather than a single script file.

## Creating a Packaged Plugin

A packaged plugin is a directory with the `.swiftbar` extension containing multiple files, including a main script file named `plugin.*`. Here's how to create one:

1. Create a directory with the `.swiftbar` extension (e.g., `weather.swiftbar`)
2. Inside this directory, create a main script file named `plugin.sh` (or `plugin.py`, `plugin.js`, etc.)
3. Add any additional resources your plugin needs (libraries, helper scripts, assets, etc.)
4. Make sure your main `plugin.*` script is executable

## Example Structure

```
weather.swiftbar/
├── Contents/
│   ├── Info.plist    # Bundle information (makes macOS treat it as a bundle)
│   ├── Resources/    # Bundle resources
│   │   └── plugin-icon.icns  # Custom icon for the plugin (optional)
├── plugin.sh         # Main entry point (REQUIRED, must be executable)
├── lib/              # Supporting library scripts
│   ├── weather_api.sh
│   └── formatting.sh
├── assets/           # Images and other assets
│   └── icons/
│       ├── sunny.png
│       └── cloudy.png
└── config.json       # Configuration files
```

### Bundle Structure (Optional)

To make your packaged plugin appear as a bundle in Finder with a custom icon:

1. Create a `Contents` directory and add an `Info.plist` file:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.yourname.swiftbar.weather</string>
    <key>CFBundleName</key>
    <string>Weather</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSTypeIsPackage</key>
    <true/>
</dict>
</plist>
```

2. Optionally add a custom icon in `Contents/Resources/plugin-icon.icns`

## Writing the Main Script

Your main script (`plugin.sh`) should source or import any required libraries:

```bash
#!/bin/bash

# Source supporting libraries
source "$PACKAGE_LIB_DIR/weather_api.sh"
source "$PACKAGE_LIB_DIR/formatting.sh"

# Use functions from the libraries
get_weather_data
format_output

echo "☀️ 72°F"
echo "---"
echo "Humidity: 45%"
echo "Wind: 5 mph NW"
```

## Environment Variables

In packaged plugins, SwiftBar provides these additional environment variables:

| Variable | Description |
|----------|-------------|
| `PACKAGE_DIR` | Full path to the package directory |
| `PACKAGE_LIB_DIR` | Full path to the `lib` directory inside the package |
| `PACKAGE_BIN_DIR` | Full path to the `bin` directory inside the package |
| `PACKAGE_ASSETS_DIR` | Full path to the `assets` directory inside the package |
| `PACKAGE_RESOURCES_DIR` | Full path to the `resources` directory inside the package |

Use these variables to reference files within your package, ensuring your plugin works regardless of where it's installed.

## Important Notes

1. **Plugin Entry Point**: The main script must be named `plugin.*` with any extension (e.g., `plugin.sh`, `plugin.py`, etc.)
2. **Package Extension**: The package directory must have the `.swiftbar` extension
3. **Working Directory**: When your main script runs, the working directory is set to the package directory, so relative paths will work
4. **Executable Permission**: Make sure your main script has executable permissions: `chmod +x plugin.sh`

## Command Line Example

```bash
# Create a packaged plugin
mkdir -p weather.swiftbar/lib
mkdir -p weather.swiftbar/assets
mkdir -p weather.swiftbar/Contents/Resources

# Create the Info.plist to make it display as a bundle
cat > weather.swiftbar/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.example.swiftbar.weather</string>
    <key>CFBundleName</key>
    <string>Weather</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSTypeIsPackage</key>
    <true/>
</dict>
</plist>
EOF

# Create the main script
cat > weather.swiftbar/plugin.sh << 'EOF'
#!/bin/bash

# Use the built-in environment variables to source libraries
source "$PACKAGE_LIB_DIR/weather_api.sh"

# Get weather data using functions from the library
get_weather_data

# Output to menu bar
echo "☀️ 72°F"
echo "---"
echo "Humidity: 45%"
echo "Wind: 5 mph NW"
EOF

# Create a supporting library
cat > weather.swiftbar/lib/weather_api.sh << 'EOF'
#!/bin/bash

get_weather_data() {
  # This would normally call an API, but we'll use static data for the example
  echo "Weather data retrieved"
}
EOF

# Make scripts executable
chmod +x weather.swiftbar/plugin.sh
chmod +x weather.swiftbar/lib/weather_api.sh

# Copy to SwiftBar plugins directory
cp -r weather.swiftbar ~/Documents/SwiftBar/
```