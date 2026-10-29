# Releasing Restling

The source repository is [yuki-uix/restling](https://github.com/yuki-uix/restling). Homebrew distribution uses the separate [yuki-uix/homebrew-restling](https://github.com/yuki-uix/homebrew-restling) tap.

## Prepare a version

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `Resources/Info.plist`. Update the version in `Resources/ForestCredits.txt` and the relevant release notes.
2. Keep `CFBundleIdentifier` as `local.yuki.breaktime` so existing forest profiles and preferences remain accessible.
3. Run `swift test`, then build and inspect the app:

```sh
./scripts/build-app.sh --universal
open dist/Restling.app
```

Check the menu bar timer, a break preview, tree catalogue and update window. The release binary must contain both `arm64` and `x86_64`; `LSMinimumSystemVersion` remains 13.0 unless support requirements deliberately change.

```sh
lipo -archs dist/Restling.app/Contents/MacOS/Restling
codesign --verify --deep --strict dist/Restling.app
```

The current release is ad-hoc signed, without a Developer ID certificate or Apple notarization. Signature verification checks package integrity; it does not establish Developer ID trust. Keep this limitation explicit in the release notes and installation instructions. Do not describe a successful local signature check as notarization.

## Package

```sh
./scripts/package-release.sh
```

Use the paths printed by the script. It produces a versioned app ZIP, `update.json`, `SHA256SUMS` and a Homebrew cask definition from the same build. Inspect them before uploading: app version and architecture, download URL, ZIP checksum, release notes and macOS requirement must agree.

Default update configuration is injected before signing:

```text
ForestUpdateFeedURL = https://github.com/yuki-uix/restling/releases/latest/download/update.json
ForestHomebrewCask = yuki-uix/restling/restling
```

Do not modify the built `Info.plist` after signing. Build-time overrides, when needed, use `FOREST_UPDATE_FEED_URL` and `FOREST_HOMEBREW_CASK`.

## Publish

1. Commit the release changes to the source repository and push them to GitHub.
2. Create a GitHub Release tagged `vVERSION` for that commit. Upload the versioned ZIP, `update.json` and `SHA256SUMS`. Publish the release as the latest stable release so the update-feed URL resolves to its `update.json` asset.
3. Copy the generated cask to `Casks/restling.rb` in the Homebrew tap. Confirm its immutable release URL and SHA-256 match the uploaded ZIP, then commit and push the tap.
4. Download the public release assets and verify their checksums. Validate the tap’s cask and test a Homebrew installation using the public URL:

```sh
brew install --cask yuki-uix/restling/restling
```

For an existing Homebrew installation:

```sh
brew update
brew upgrade --cask yuki-uix/restling/restling
```

Check that the installed app reports the released version and that “检查更新” reads the public feed successfully. Normal install, upgrade and uninstall must preserve forest progress; clearing preferences belongs only to an explicit `--zap` uninstall.

## Feed contract

`update.json` contains `version`, `releaseNotes`, `releaseURL` and `minimumMacOSVersion`. The app accepts valid HTTPS links and limits the document to 128 KiB. Keep the version consistent with the app and release tag. The feed is release metadata, not an installer.

Every later stable release must upload a fresh `update.json` and update the cask. A new Git tag alone does not update Homebrew or notify app users.
