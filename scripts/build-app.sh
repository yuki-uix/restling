#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_APP=false
UNIVERSAL=false
for option in "$@"; do
case "$option" in
    --install) INSTALL_APP=true ;;
    --universal) UNIVERSAL=true ;;
    -h|--help)
        echo "Usage: $0 [--universal] [--install]"
        echo "Build dist/Restling.app; --universal supports Apple Silicon and Intel."
        echo "--install also copies the app to ~/Applications."
        echo "Optional: FOREST_UPDATE_FEED_URL=https://.../update.json"
        echo "          FOREST_HOMEBREW_CASK=owner/tap/restling"
        echo "Official Restling update URLs are used by default; set both to empty to disable."
        exit 0
        ;;
    *) echo "Unknown option: $option" >&2; exit 2 ;;
esac
done

BUNDLE_ID="local.yuki.breaktime"
APP_NAME="Restling.app"
OUTPUT_APP="$PROJECT_DIR/dist/$APP_NAME"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME"

assert_our_app() {
    local candidate="$1"
    if [[ -e "$candidate" || -L "$candidate" ]]; then
        if [[ -L "$candidate" || ! -d "$candidate" ]]; then
            echo "Refusing to replace a symlink or non-app: $candidate" >&2
            exit 1
        fi
        local existing_id
        existing_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate/Contents/Info.plist" 2>/dev/null || true)
        if [[ "$existing_id" != "$BUNDLE_ID" ]]; then
            echo "Refusing to replace an app with a different bundle identifier: $candidate" >&2
            exit 1
        fi
    fi
}

assert_our_app "$OUTPUT_APP"
if "$INSTALL_APP"; then
    assert_our_app "$INSTALLED_APP"
fi

export MACOSX_DEPLOYMENT_TARGET=13.0
export FOREST_UPDATE_FEED_URL="${FOREST_UPDATE_FEED_URL-https://github.com/yuki-uix/restling/releases/latest/download/update.json}"
export FOREST_HOMEBREW_CASK="${FOREST_HOMEBREW_CASK-yuki-uix/restling/restling}"
mkdir -p "$PROJECT_DIR/dist"
STAGING_DIR="$(mktemp -d "$PROJECT_DIR/dist/.app-build.XXXXXXXX")"
trap 'rm -rf -- "$STAGING_DIR"' EXIT

STAGED_APP="$STAGING_DIR/$APP_NAME"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
if "$UNIVERSAL"; then
    for architecture in arm64 x86_64; do
        xcrun swift build --package-path "$PROJECT_DIR" -c release \
            --scratch-path "$PROJECT_DIR/.build/release-$architecture" \
            --triple "$architecture-apple-macosx13.0"
    done
    ARM_BIN="$(xcrun swift build --package-path "$PROJECT_DIR" -c release --scratch-path "$PROJECT_DIR/.build/release-arm64" --triple arm64-apple-macosx13.0 --show-bin-path)"
    INTEL_BIN="$(xcrun swift build --package-path "$PROJECT_DIR" -c release --scratch-path "$PROJECT_DIR/.build/release-x86_64" --triple x86_64-apple-macosx13.0 --show-bin-path)"
    xcrun lipo -create "$ARM_BIN/Breaktime" "$INTEL_BIN/Breaktime" -output "$STAGED_APP/Contents/MacOS/Restling"
    xcrun lipo "$STAGED_APP/Contents/MacOS/Restling" -verify_arch arm64 x86_64
else
    xcrun swift build --package-path "$PROJECT_DIR" -c release
    BIN_DIR="$(xcrun swift build --package-path "$PROJECT_DIR" -c release --show-bin-path)"
    cp "$BIN_DIR/Breaktime" "$STAGED_APP/Contents/MacOS/Restling"
fi
chmod 755 "$STAGED_APP/Contents/MacOS/Restling"
cp "$PROJECT_DIR/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
xcrun swift "$PROJECT_DIR/scripts/configure-updates.swift" "$STAGED_APP/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/ForestCredits.txt" "$STAGED_APP/Contents/Resources/ForestCredits.txt"
plutil -lint "$STAGED_APP/Contents/Info.plist"
printf 'APPL????' > "$STAGED_APP/Contents/PkgInfo"

ICONSET_DIR="$STAGING_DIR/AppIcon.iconset"
xcrun swift "$PROJECT_DIR/scripts/generate-icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$STAGED_APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"

if [[ -e "$OUTPUT_APP" ]]; then
    rm -rf -- "$OUTPUT_APP"
fi
mv "$STAGED_APP" "$OUTPUT_APP"
echo "Built: $OUTPUT_APP"

if "$INSTALL_APP"; then
    mkdir -p "$INSTALL_DIR"
    if [[ -e "$INSTALLED_APP" ]]; then
        rm -rf -- "$INSTALLED_APP"
    fi
    ditto "$OUTPUT_APP" "$INSTALLED_APP"
    codesign --verify --strict "$INSTALLED_APP"
    echo "Installed: $INSTALLED_APP"
    echo "Launch with: open \"$INSTALLED_APP\""
fi
