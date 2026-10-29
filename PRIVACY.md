# Restling privacy

Applies to the Restling 0.8.0 community preview, published on 29 October 2026.

## What stays on your Mac

Restling stores forest profiles, tree species and growth, reminder settings, onboarding preferences, weather choices and update-check preferences in macOS UserDefaults. Cached update metadata may include the last check time, release notes and an ignored version.

There is no account system or cloud sync. Restling has no advertising, analytics, tracking SDKs or developer-operated data collection endpoint. It does not upload forest names, growth, timer activity or settings.

The native frosted-glass break overlay does not capture or save screenshots. It needs no Screen Recording permission. Weather is generated locally and does not use your location.

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
