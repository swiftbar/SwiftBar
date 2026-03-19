#!/bin/bash

# <xbar.title>Issue #456 Terminal Actions Manual Test</xbar.title>
# <xbar.version>v1.0</xbar.version>
# <xbar.author>Codex</xbar.author>
# <xbar.desc>Manual verification plugin for terminal=true actions in Terminal, iTerm, and Ghostty.</xbar.desc>

set -euo pipefail

plugin_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
helper="${plugin_dir}/.issue-456-terminal-helper.sh"

echo "Terminal Actions"
echo "---"
echo "Simple Launch | bash='${helper}' param1='simple' terminal=true refresh=false"
echo "Quoted Args | bash='${helper}' param1='quotes' terminal=true refresh=false"
echo "Environment | bash='${helper}' param1='env' terminal=true refresh=false"
echo "System Info | bash='${helper}' param1='system' terminal=true refresh=false"
echo "---"
echo "Copy this plugin and its hidden helper into your plugin folder. | color=gray"
