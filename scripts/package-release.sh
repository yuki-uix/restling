#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
case "${1:-}" in
    "")
        xcrun swift test --package-path "$PROJECT_DIR"
        "$PROJECT_DIR/scripts/build-app.sh" --universal
        ;;
    --skip-build) ;;
    *) echo "Usage: $0 [--skip-build]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo "Too many arguments." >&2; exit 2; }

DIST="$PROJECT_DIR/dist"
APP="$DIST/Restling.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Resources/Info.plist")
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Expected a stable x.y.z version." >&2; exit 1; }
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
[[ "$APP_VERSION" == "$VERSION" ]] || { echo "The app bundle version is stale." >&2; exit 1; }
FEED=$(/usr/libexec/PlistBuddy -c 'Print :ForestUpdateFeedURL' "$APP/Contents/Info.plist")
CASK=$(/usr/libexec/PlistBuddy -c 'Print :ForestHomebrewCask' "$APP/Contents/Info.plist")
[[ "$FEED" == 'https://github.com/yuki-uix/restling/releases/latest/download/update.json' && "$CASK" == 'yuki-uix/restling/restling' ]] || {
    echo "Public release packaging requires the official Restling update configuration." >&2; exit 1;
}
NOTES="$PROJECT_DIR/release-notes/$VERSION.md"
[[ -f "$NOTES" ]] || { echo "Missing release notes: $NOTES" >&2; exit 1; }
codesign --verify --strict "$APP"
xcrun lipo "$APP/Contents/MacOS/Restling" -verify_arch arm64 x86_64

ARCHIVE="Restling-$VERSION-universal.zip"
rm -f -- "$DIST/$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$ARCHIVE"
SHA=$(shasum -a 256 "$DIST/$ARCHIVE" | awk '{print $1}')
printf '%s  %s\n' "$SHA" "$ARCHIVE" > "$DIST/SHA256SUMS"
xcrun swift "$PROJECT_DIR/scripts/make-update-feed.swift" \
    --version "$VERSION" \
    --release-url "https://github.com/yuki-uix/restling/releases/tag/v$VERSION" \
    --notes-file "$NOTES" --minimum-macos 13.0.0 --output "$DIST/update.json"

cat > "$DIST/restling.rb" <<EOF
cask "restling" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/yuki-uix/restling/releases/download/v#{version}/Restling-#{version}-universal.zip"
  name "Restling"
  desc "Gentle eye-rest reminders that grow a personal pixel forest"
  homepage "https://github.com/yuki-uix/restling"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "Restling.app"

  uninstall quit: "local.yuki.breaktime"

  zap trash: [
    "~/Library/Preferences/local.yuki.breaktime.plist",
    "~/Library/Saved Application State/local.yuki.breaktime.savedState",
  ]

  caveats <<~EOS
    Restling is an ad-hoc-signed preview and is not notarized by Apple.
    If macOS blocks the first launch, review it in System Settings >
    Privacy & Security > Open Anyway.
  EOS
end
EOF
echo "Packaged $ARCHIVE ($SHA)"
echo "Release assets: $DIST/$ARCHIVE, $DIST/update.json, $DIST/SHA256SUMS"
echo "Homebrew definition: $DIST/restling.rb"
echo "No files have been uploaded."
