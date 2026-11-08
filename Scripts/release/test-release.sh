#!/usr/bin/env bash
# Exercises release channels and rejection paths without publishing to GitHub.
set -euo pipefail
scripts=$(cd "$(dirname "$0")" && pwd)
fixture_root=$(mktemp -d)
trap '/bin/rm -r "$fixture_root"' EXIT
mkdir "$fixture_root/repo" "$fixture_root/bin"
export RELEASE_TEST_LOG="$fixture_root/calls" RELEASE_TEST_FEED="$fixture_root/feed.xml"
export PATH="$fixture_root/bin:$PATH"
cat > "$fixture_root/bin/gh" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >> "$RELEASE_TEST_LOG"
EOF
cat > "$fixture_root/bin/curl" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >> "$RELEASE_TEST_LOG"
cat "$RELEASE_TEST_FEED"
EOF
cat > "$fixture_root/bin/sleep" <<'EOF'
#!/bin/bash
# A rejected feed exits promptly instead of polling for ten minutes.
exit 1
EOF
cat > "$fixture_root/bin/xcrun" <<'EOF'
#!/bin/bash
[[ $1 == stapler && $2 == validate ]] || exit 1
printf '%s\n' "$@" >> "$RELEASE_TEST_LOG"
EOF
chmod +x "$fixture_root/bin/gh" "$fixture_root/bin/curl" "$fixture_root/bin/sleep" "$fixture_root/bin/xcrun"
git init -q --bare "$fixture_root/origin.git"
cd "$fixture_root/repo"
git init -q
git config user.email release-test@example.invalid
git config user.name 'Release Test'
git config commit.gpgsign false
git config tag.gpgsign false
git remote add origin "$fixture_root/origin.git"
printf '*.app/\n*.zip\n' > .gitignore
printf 'Release fixture\n' > notes.md
git add .gitignore notes.md
git commit -qm 'test fixture'
git tag -a -m 'beta fixture' v2.1.2-beta-6
git tag v2.1.2
git push -q origin --tags
app="$fixture_root/repo/SwiftBar.app"
mkdir -p "$app/Contents/MacOS"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.swiftbar.release-fixture</string>
<key>CFBundleExecutable</key><string>SwiftBar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>2.1.2</string>
<key>CFBundleVersion</key><string>624</string>
</dict></plist>
EOF
cp /usr/bin/true "$app/Contents/MacOS/SwiftBar"
codesign --force --sign - "$app" 2>/dev/null
ditto -c -k --keepParent "$app" SwiftBar.v2.1.2.b624.zip

bash "$scripts/publish.sh" beta v2.1.2-beta-6 notes.md "$app" swiftbar/SwiftBar
grep -qx -- --prerelease "$RELEASE_TEST_LOG"
grep -qx -- --latest=false "$RELEASE_TEST_LOG"
grep -qx -- stapler "$RELEASE_TEST_LOG"
: > "$RELEASE_TEST_LOG"
bash "$scripts/publish.sh" stable v2.1.2 notes.md "$app" swiftbar/SwiftBar
grep -qx -- --latest "$RELEASE_TEST_LOG"
if grep -qx -- --prerelease "$RELEASE_TEST_LOG"; then exit 1; fi

expect_rejected() {
    if "$@" > /dev/null 2>&1; then echo "Expected rejection: $*" >&2; exit 1; fi
}
expect_rejected bash "$scripts/publish.sh" stable v2.1.2-beta-6 notes.md "$app" swiftbar/SwiftBar
expect_rejected bash "$scripts/publish.sh" beta v2.1.2 notes.md "$app" swiftbar/SwiftBar
expect_rejected bash "$scripts/publish.sh" beta v2.1.3-beta-1 notes.md "$app" swiftbar/SwiftBar
mkdir -p "$fixture_root/corrupt"
ditto "$app" "$fixture_root/corrupt/SwiftBar.app"
mkdir -p "$fixture_root/corrupt/SwiftBar.app/Contents/Resources"
printf 'Unexpected ZIP-only payload\n' > "$fixture_root/corrupt/SwiftBar.app/Contents/Resources/injected.txt"
mv SwiftBar.v2.1.2.b624.zip "$fixture_root/original.zip"
ditto -c -k --keepParent "$fixture_root/corrupt/SwiftBar.app" SwiftBar.v2.1.2.b624.zip
expect_rejected bash "$scripts/publish.sh" beta v2.1.2-beta-6 notes.md "$app" swiftbar/SwiftBar
mv "$fixture_root/original.zip" SwiftBar.v2.1.2.b624.zip
printf changed >> notes.md
expect_rejected bash "$scripts/publish.sh" beta v2.1.2-beta-6 notes.md "$app" swiftbar/SwiftBar
git restore notes.md
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 625' "$app/Contents/Info.plist"
expect_rejected bash "$scripts/publish.sh" beta v2.1.2-beta-6 notes.md "$app" swiftbar/SwiftBar
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 624' "$app/Contents/Info.plist"

write_feed() {
    cat > "$RELEASE_TEST_FEED" <<EOF
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
<enclosure url="https://github.com/swiftbar/SwiftBar/releases/download/$1/SwiftBar.v2.1.2.b$2.zip" sparkle:version="$2" sparkle:shortVersionString="${1#v}" length="1234"/>
</item></channel></rss>
EOF
}
write_feed v2.1.2-beta-6 624
: > "$RELEASE_TEST_LOG"
bash "$scripts/appcast.sh" beta v2.1.2-beta-6 "$app" swiftbar/SwiftBar
grep -qx 'https://swiftbar.github.io/SwiftBar/appcast-beta.xml' "$RELEASE_TEST_LOG"
write_feed v2.1.2 624
: > "$RELEASE_TEST_LOG"
bash "$scripts/appcast.sh" stable v2.1.2 "$app" swiftbar/SwiftBar
grep -qx 'https://swiftbar.github.io/SwiftBar/appcast.xml' "$RELEASE_TEST_LOG"
write_feed v2.1.2-beta-6 1624
expect_rejected bash "$scripts/appcast.sh" beta v2.1.2-beta-6 "$app" swiftbar/SwiftBar
write_feed v2.1.2-beta-5 624
expect_rejected bash "$scripts/appcast.sh" beta v2.1.2-beta-6 "$app" swiftbar/SwiftBar
echo 'Release channel, metadata, dirty checkout, and exact appcast checks passed.'
