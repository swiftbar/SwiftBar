#!/usr/bin/env bash
# Test smoke-check failure and cleanup paths without desktop interaction.
set -euo pipefail
scripts=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$scripts/../.." && pwd)
fixture_root=$(mktemp -d)
trap '/bin/rm -r "$fixture_root"' EXIT
fixture="$fixture_root/work"
mkdir -p "$fixture/Scripts/release" "$fixture_root/bin"
cp "$scripts/make-smoke-icon.swift" "$scripts/measure-smoke-icon.swift" "$fixture/Scripts/release/"
export SMOKE_TEST_LOG="$fixture_root/calls"
cat > "$fixture_root/bin/open" <<'EOF'
#!/bin/bash
printf 'open\n' >> "$SMOKE_TEST_LOG"
printf '%s\n' "${@: -1}" > "$SMOKE_TEST_LOG.plugin-directory"
EOF
cat > "$fixture_root/bin/pkill" <<'EOF'
#!/bin/bash
printf 'cleanup\n' >> "$SMOKE_TEST_LOG"
EOF
cat > "$fixture_root/bin/sleep" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$fixture_root/bin/screencapture" <<'EOF'
#!/bin/bash
# macOS can report capture failure while returning success.
if [ -n "${SMOKE_TEST_IMAGE:-}" ]; then cp "$SMOKE_TEST_IMAGE" "${@: -1}"; fi
EOF
chmod +x "$fixture_root/bin/"*
export PATH="$fixture_root/bin:$PATH"
cd "$fixture"
swift Scripts/release/make-smoke-icon.swift > /dev/null
cp Scripts/release/.smoke-icon.png "$fixture_root/good.png"
sed 's/let px = 54/let px = 52/' Scripts/release/make-smoke-icon.swift > "$fixture_root/wrong.swift"
swift "$fixture_root/wrong.swift" > /dev/null
cp Scripts/release/.smoke-icon.png "$fixture_root/wrong.png"

run_smoke() { just --justfile "$repo/Justfile" --working-directory "$fixture" smoke-test; }
assert_cleanup() {
    grep -qx cleanup "$SMOKE_TEST_LOG"
    test ! -e Scripts/release/.smoke-bar.png
    test ! -e Scripts/release/.smoke-icon.png
    test ! -d "$(cat "$SMOKE_TEST_LOG.plugin-directory")"
}

# Preexisting screenshots must not hide a failed new capture.
cp "$fixture_root/good.png" Scripts/release/.smoke-bar.png
export SMOKE_TEST_IMAGE=""
if run_smoke > "$fixture_root/missing.log" 2>&1; then echo 'ERROR: missing capture accepted'; exit 1; fi
grep -q 'ERROR: no screen capture was written' "$fixture_root/missing.log"
assert_cleanup

export SMOKE_TEST_IMAGE="$fixture_root/wrong.png"
if run_smoke > "$fixture_root/wrong.log" 2>&1; then echo 'ERROR: 52-pixel image accepted'; exit 1; fi
grep -q 'magenta block: 52 x 52 px' "$fixture_root/wrong.log"
assert_cleanup

export SMOKE_TEST_IMAGE="$fixture_root/good.png"
run_smoke > "$fixture_root/good.log" 2>&1
grep -q 'smoke-test OK' "$fixture_root/good.log"
assert_cleanup

if swift Scripts/release/measure-smoke-icon.swift "$fixture_root/absent.png" > "$fixture_root/measure.log" 2>&1; then
    echo 'ERROR: detector accepted missing input'; exit 1
fi
grep -q 'ERROR: smoke capture is missing or invalid' "$fixture_root/measure.log"
echo 'smoke fixtures passed (missing/stale input, 52px rejection, 54px success, cleanup)'
