#!/bin/bash
#
# Checks that this Mac can build TalkToMyMac, and says how to fix whatever is missing.
# Run by `make install` and `make run` before building; `make check-deps` runs it alone.
#
# What's needed
# -------------
#  - macOS 26 or later (the app targets it).
#  - Xcode 26 or later, not just the Command Line Tools: the build and tests need the full
#    macOS SDK and XCTest that ship with Xcode. If Xcode is missing, this opens its App Store
#    page.
#  - Xcode selected as the active developer directory and its license accepted, so its
#    macOS SDK and Swift compiler are what the build uses.
#
# Exits non-zero, before anything is built, if something is missing.

set -euo pipefail

MIN_MACOS=26
MIN_XCODE=26
XCODE_APP_STORE_URL="macappstore://apps.apple.com/app/id497799835"

ok()   { echo "  ✅ $1"; }
fail() { echo "  ❌ $1"; }

# Asks a yes/no question; "no" when there's no terminal to ask on (e.g. CI).
confirm() {
    [ -t 0 ] || return 1
    local reply
    read -r -p "  $1 [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

echo "Checking build dependencies…"

# macOS version
macos_version=$(sw_vers -productVersion)
if [ "${macos_version%%.*}" -lt "$MIN_MACOS" ]; then
    fail "macOS $macos_version — TalkToMyMac needs macOS $MIN_MACOS or later."
    echo "     Update in System Settings → General → Software Update."
    exit 1
fi
ok "macOS $macos_version"

# Xcode itself: the usual location, then anywhere Spotlight knows about (Xcode-beta, renamed copies).
xcode_app=""
if [ -d /Applications/Xcode.app ]; then
    xcode_app=/Applications/Xcode.app
else
    xcode_app=$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null | head -n 1 || true)
fi

if [ -z "$xcode_app" ]; then
    fail "Xcode is not installed. TalkToMyMac needs Xcode $MIN_XCODE or later to build."
    echo "     Opening Xcode in the App Store — install it, open it once, then re-run this command."
    open "$XCODE_APP_STORE_URL" || echo "     Get it at https://apps.apple.com/app/xcode/id497799835"
    exit 1
fi

xcode_version=$(defaults read "$xcode_app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo 0)
if [ "${xcode_version%%.*}" -lt "$MIN_XCODE" ]; then
    fail "Xcode $xcode_version at $xcode_app — TalkToMyMac needs Xcode $MIN_XCODE or later."
    echo "     Opening Xcode in the App Store — update it, then re-run this command."
    open "$XCODE_APP_STORE_URL" || true
    exit 1
fi
ok "Xcode $xcode_version ($xcode_app)"

# Active developer directory: with only the Command Line Tools selected, `swift build` uses
# their SDK instead of Xcode's.
developer_dir="$xcode_app/Contents/Developer"
selected_dir=$(xcode-select -p 2>/dev/null || true)
if [ "$selected_dir" != "$developer_dir" ] && [ "${DEVELOPER_DIR:-}" != "$developer_dir" ]; then
    fail "The active developer directory is ${selected_dir:-not set}, not Xcode."
    if confirm "Switch it to $developer_dir now? (needs your password)"; then
        sudo xcode-select --switch "$developer_dir"
        ok "Switched to $developer_dir"
    else
        echo "     Run: sudo xcode-select --switch \"$developer_dir\""
        exit 1
    fi
else
    ok "Xcode is the active developer directory"
fi

# License: until it's accepted, every developer tool refuses to run.
if ! xcodebuild -license check >/dev/null 2>&1; then
    fail "The Xcode license hasn't been accepted."
    if confirm "Review and accept it now? (needs your password)"; then
        sudo xcodebuild -license
    else
        echo "     Run: sudo xcodebuild -license accept"
        exit 1
    fi
fi
ok "Xcode license accepted"

# The SDK and compiler the build actually uses, resolved through the steps above.
sdk_version=$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || echo 0)
if [ "${sdk_version%%.*}" -lt "$MIN_MACOS" ] || ! xcrun --find swift >/dev/null 2>&1; then
    fail "Xcode's macOS SDK (${sdk_version}) or Swift compiler isn't usable — TalkToMyMac needs the macOS $MIN_MACOS SDK."
    echo "     Open Xcode once to finish its setup, then re-run this command."
    exit 1
fi
ok "macOS $sdk_version SDK and Swift $(xcrun swift --version 2>/dev/null | sed -n 's/.*Swift version \([0-9.]*\).*/\1/p' | head -n 1)"

echo "All build dependencies are in place."
