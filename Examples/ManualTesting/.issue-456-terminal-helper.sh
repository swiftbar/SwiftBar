#!/bin/bash

set -euo pipefail

mode="${1:-simple}"

printf 'SwiftBar Manual Terminal Test\n'
printf 'mode=%s\n' "$mode"
printf 'shell=%s\n' "${SHELL:-}"
printf 'pwd=%s\n' "$PWD"
printf 'TERM_PROGRAM=%s\n' "${TERM_PROGRAM:-}"
printf 'SWIFTBAR_PLUGIN_PATH=%s\n' "${SWIFTBAR_PLUGIN_PATH:-}"
printf 'SWIFTBAR_PLUGINS_PATH=%s\n' "${SWIFTBAR_PLUGINS_PATH:-}"
printf 'SWIFTBAR_PLUGIN_REFRESH_REASON=%s\n' "${SWIFTBAR_PLUGIN_REFRESH_REASON:-}"
printf '\n'

case "$mode" in
simple)
    printf 'simple launch ok\n'
    ;;
quotes)
    printf 'quoted arg ok: %s\n' "hello world"
    printf 'double quotes ok: %s\n' 'say "hello"'
    printf 'single quote ok: %s\n' "it's working"
    ;;
env)
    printf 'environment propagation ok\n'
    env | grep '^SWIFTBAR_' | sort
    ;;
system)
    printf 'command execution ok\n'
    uname -a
    ;;
*)
    printf 'unknown mode: %s\n' "$mode"
    ;;
esac

printf '\nPress return to exit...'
IFS= read -r _
