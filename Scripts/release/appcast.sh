#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 4 ]]; then
    echo "usage: appcast.sh beta|stable tag app repo" >&2
    exit 2
fi
channel=$1 tag=$2 app=$3 repo=$4
case "$channel" in
    beta)
        [[ $tag =~ ^v([0-9]+\.[0-9]+\.[0-9]+)-beta-[1-9][0-9]*$ ]] || exit 2
        feed=appcast-beta.xml
        ;;
    stable)
        [[ $tag =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || exit 2
        feed=appcast.xml
        ;;
    *) echo "Unknown release channel: $channel" >&2; exit 2 ;;
esac
tag_version=${BASH_REMATCH[1]}
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
[[ $version == "$tag_version" && $build =~ ^[0-9]+$ ]] || { echo "Tag does not match app" >&2; exit 1; }
expected_url="https://github.com/$repo/releases/download/$tag/SwiftBar.v${version}.b${build}.zip"
expected_version=${tag#v}
gh api -X POST "repos/$repo/pages/builds" --jq .status
echo "Waiting for $feed to serve $tag (build $build)..."
for ((attempt = 0; attempt < 40; attempt++)); do
    if xml=$(curl -fsSL "https://swiftbar.github.io/SwiftBar/$feed"); then
        matches=$(printf '%s' "$xml" | xmllint --xpath "boolean(/rss/channel/item/enclosure[@url='$expected_url'][@*[local-name()='version']='$build'][@*[local-name()='shortVersionString']='$expected_version'][@length > 0])" - 2>/dev/null) || matches=false
        if [[ $matches == true ]]; then
            echo "appcast OK: $feed serves the exact release asset"
            exit 0
        fi
    fi
    sleep 15
done
echo "ERROR: $feed did not serve the expected release within 10 minutes" >&2
exit 1
