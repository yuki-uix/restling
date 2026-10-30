# Restling privacy

Applies to the Restling 0.9.0 community preview.

## What stays on your Mac

Restling stores forest profiles, tree species and growth, reminder settings, onboarding preferences, weather choices and update-check preferences in macOS UserDefaults. Reminder settings include selected weekdays and local hours, pre-warning, idle and return-grace choices, and sound preferences. The saved timer contains its remaining time, running/paused intention, any active rest's identifier and forest, and temporary do-not-disturb or snooze deadlines. Cached update metadata may include the last check time, release notes and an ignored version.

There is no account system or cloud sync. Restling has no advertising, analytics, tracking SDKs or developer-operated data collection endpoint. It does not upload forest names, growth, timer activity or settings.

The native frosted-glass break overlay does not capture or save screenshots. It needs no Screen Recording permission. Weather is generated locally and does not use your location.

## Presence and login items

To pause reminders while you are away, Restling reads the system's elapsed time since keyboard or mouse input, together with lock/session, display-sleep and system-sleep state. It does not record individual key presses, mouse events, typed content or screenshots. It does not use a camera or infer gaze. Idle-based pausing can be turned off in reminder settings; these presence signals are used locally and are not uploaded.

Launch at login is optional and starts off until you enable it. Restling registers its own login item with macOS only after that control is changed. The system manages its registration and any approval; the app reads that status to show whether startup is enabled or needs attention. This setting applies immediately and is separate from saving or cancelling the other reminder preferences.

Restoring a saved timer does not reconstruct offline activity or award forest growth for time while the app was not running. Completed rest counts describe completed timers, not verified gaze or health outcomes.

## Update requests

Official builds use this public update feed:

<https://github.com/yuki-uix/restling/releases/latest/download/update.json>

Automatic requests are limited to once every 24 hours and can be disabled in the update window. Manual checks remain available. Requests use an ephemeral network session, do not attach account credentials or cookies, and contain no forest or timer data. A request has a 10-second timeout and the feed is limited to 128 KiB.

As with any HTTPS request, GitHub and its delivery providers receive connection information such as your IP address. Their handling is covered by [GitHub’s privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement). Opening a release page or installing with Homebrew also contacts the respective services separately from the app.

Restling only displays release information and copies an upgrade command when requested. It does not run terminal commands or install updates in the background.

## Keeping or removing your data

The stable bundle identifier is `local.yuki.breaktime`; changing the display name to Restling preserves existing local forests from 小憩. The app’s preferences are normally stored at:

```text
~/Library/Preferences/local.yuki.breaktime.plist
```

A normal Homebrew uninstall preserves local progress. If you intentionally want to remove both the app and the preferences listed in its cask, quit Restling and use:

```sh
brew uninstall --cask --zap yuki-uix/restling/restling
```

This deletes local forests and preferences. There is no cloud copy to restore.

## Questions

Report privacy questions through the [Restling issue tracker](https://github.com/yuki-uix/restling/issues). Issues are public; avoid posting personal forest exports or other private information.
