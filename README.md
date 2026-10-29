# Restling

**A little rest. A little growth.**

A gentle macOS menu bar reminder that turns short eye breaks into a growing pixel forest. 默认每用眼 **20 分钟**，提醒抬头看远处 **20 秒**。应用界面目前为中文。

<img src="Resources/RestlingIcon.png" width="128" alt="Restling sprout icon">

## Install

Requires **macOS 13 or later**. The universal app supports Apple silicon and Intel Macs.

```sh
brew install --cask yuki-uix/restling/restling
```

Open **Restling** from Applications. It lives in the menu bar; closing its main window keeps reminders running. Choose “开启休息提醒” to start.

You can also download the app from [GitHub Releases](https://github.com/yuki-uix/restling/releases).

**Community preview:** the current release uses a local ad-hoc signature and has not been notarized by Apple. macOS may block its first launch. After attempting to open it, go to **System Settings → Privacy & Security → Open Anyway** if macOS offers that option, and confirm the app you downloaded. See [Apple’s instructions](https://support.apple.com/en-us/102445). Homebrew installation does not remove this first-launch requirement.

## Your rest forest

- Start with bare earth. The first completed break brings a sprout, the second a sapling, and the third a lasting tree and more land.
- Unlock pine and blossom trees after 3 and 6 completed breaks. Every 3 breaks adds another tree; full groves make room for new ones.
- Browse the tree catalogue and choose which unlocked species to grow. Existing trees stay as they are.
- Enjoy sunlight, moving clouds, breeze and rain. Weather changes the atmosphere, not your progress; Reduce Motion freezes animation.
- Rest behind a native frosted-glass overlay. There is nothing to feed or collect during the break. Press Esc to leave early; your existing forest stays safe.
- Keep separate local forest profiles. Previewing or skipping a break does not earn growth.

The default rhythm is adjustable. Sleep pauses the timer, and waking resumes it. This is a rest companion, with no streak penalty or withering trees.

## Updates

Restling checks its [public release feed](https://github.com/yuki-uix/restling/releases/latest/download/update.json) at most once every 24 hours automatically. You can disable automatic checks or choose “检查更新” in the app or menu bar at any time.

When an update is available, Restling shows release notes and a command you can copy. It does not download or install app updates itself.

```sh
brew update
brew upgrade --cask yuki-uix/restling/restling
```

## Local data and privacy

Forests, settings and update preferences stay on your Mac. There are no accounts, ads, analytics or cloud sync. The frosted overlay uses native macOS material and needs no screen recording permission. Update checks contact GitHub without sending forest data. See [PRIVACY.md](PRIVACY.md).

The bundle identifier remains `local.yuki.breaktime` so existing local forests from 小憩 are retained. Quit the earlier app before running Restling to avoid duplicate reminders.

## Build

Use macOS with Xcode Command Line Tools and a compatible Swift toolchain.

```sh
swift test
./scripts/build-app.sh --universal
open dist/Restling.app
```

To build and copy the app into your user Applications folder:

```sh
./scripts/build-app.sh --install
open "$HOME/Applications/Restling.app"
```

The app is built with SwiftUI and AppKit. Forest scenes and trees are drawn by project code; the Restling icon was designed with built-in image generation and compiled into platform icon assets with AppKit. This distribution contains no Forest or 1Break code or branding, and no earlier experimental cat videos.

Release packaging and Homebrew maintenance are documented in [RELEASING.md](RELEASING.md).
