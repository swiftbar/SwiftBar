#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 5 ]]; then
    echo "usage: publish.sh beta|stable tag notes app repo" >&2
    exit 2
fi
channel=$1 tag=$2 notes=$3 app=$4 repo=$5
case "$channel" in
    beta)
        [[ $tag =~ ^v([0-9]+\.[0-9]+\.[0-9]+)-beta-[1-9][0-9]*$ ]] || { echo "Expected a beta tag" >&2; exit 2; }
        title="${tag#v}"
        title="${title/-beta-/ BETA }"
        flags=(--prerelease --latest=false)
        ;;
    stable)
        [[ $tag =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || { echo "Expected a stable tag" >&2; exit 2; }
        title="${tag#v}"
        flags=(--latest)
        ;;
    *) echo "Unknown release channel: $channel" >&2; exit 2 ;;
esac
tag_version=${BASH_REMATCH[1]}
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
[[ $version == "$tag_version" && $build =~ ^[0-9]+$ ]] || { echo "Tag does not match app version/build" >&2; exit 1; }
archive="SwiftBar.v${version}.b${build}.zip"
[[ -s $notes && -s $archive ]] || { echo "Missing release notes or archive" >&2; exit 1; }
[[ -z $(git status --porcelain) ]] || { echo "Release checkout must be clean" >&2; exit 1; }
head=$(git rev-parse HEAD)
[[ $(git rev-parse "${tag}^{commit}") == "$head" ]] || { echo "Tag does not identify this checkout" >&2; exit 1; }
remote_head=$(git ls-remote --exit-code origin "refs/tags/$tag" "refs/tags/$tag^{}" | awk 'END {print $1}')
[[ $remote_head == "$head" ]] || { echo "Remote tag does not identify this checkout" >&2; exit 1; }

archived_version=$(unzip -p "$archive" SwiftBar.app/Contents/Info.plist | plutil -extract CFBundleShortVersionString raw -o - -)
archived_build=$(unzip -p "$archive" SwiftBar.app/Contents/Info.plist | plutil -extract CFBundleVersion raw -o - -)
[[ $archived_version == "$version" && $archived_build == "$build" ]] || { echo "Archive metadata does not match app" >&2; exit 1; }
archived_hash=$(unzip -p "$archive" SwiftBar.app/Contents/MacOS/SwiftBar | shasum -a 256 | awk '{print $1}')
app_hash=$(shasum -a 256 "$app/Contents/MacOS/SwiftBar" | awk '{print $1}')
[[ $archived_hash == "$app_hash" ]] || { echo "Archive executable does not match app" >&2; exit 1; }
archive_directory=$(mktemp -d)
trap '/bin/rm -r "$archive_directory"' EXIT
ditto -x -k "$archive" "$archive_directory"
archived_app="$archive_directory/SwiftBar.app"
# The archive is what users receive. Verifying the separate build directory
# would miss changed resources or frameworks inside an otherwise matching ZIP.
codesign --verify --deep --strict "$archived_app"
xcrun stapler validate "$archived_app"
gh release create "$tag" --repo "$repo" --verify-tag "${flags[@]}" --title "$title" --notes-file "$notes" "$archive"
