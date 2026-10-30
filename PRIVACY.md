# Restling privacy

Applies to the Restling 0.11.0 community preview.

## What stays on your Mac

Restling stores forest profiles, tree species and growth, rest events, reminder settings, onboarding preferences, weather choices and update-check preferences in macOS UserDefaults. A rest event contains its unique ID, forest ID, terminal time, configured timer duration and completed/skipped result. The archive also contains the date detailed recording began. Older cumulative progress remains intact; upgrading does not fabricate earlier event times. Reminder settings include selected weekdays and local hours, pre-warning, idle and return-grace choices, and sound preferences. The saved timer contains its remaining time, running/paused intention, any active rest's identifier and forest, and temporary do-not-disturb or snooze deadlines. Cached update metadata may include the last check time, release notes and an ignored version.

There is no account system or cloud sync. Restling has no advertising, analytics, tracking SDKs or developer-operated data collection endpoint. It does not upload forest names, growth, timer activity or settings.

The native frosted-glass break overlay does not capture or save screenshots. It needs no Screen Recording permission. Weather is generated locally and does not use your location.

Tree species and ecological discoveries are derived locally from the existing cumulative rest total. The tree catalogue and “林地手记” do not collect browsing analytics or make network requests. The ecology additions introduce no new data collection, system permission or background task.

## Presence and login items

To pause reminders while you are away, Restling reads the system's elapsed time since keyboard or mouse input, together with lock/session, display-sleep and system-sleep state. It does not record individual key presses, mouse events, typed content or screenshots. It does not use a camera or infer gaze. Idle-based pausing can be turned off in reminder settings; these presence signals are used locally and are not uploaded.

Launch at login is optional and starts off until you enable it. Restling registers its own login item with macOS only after that control is changed. The system manages its registration and any approval; the app reads that status to show whether startup is enabled or needs attention. This setting applies immediately and is separate from saving or cancelling the other reminder preferences.

Restoring a saved timer does not reconstruct offline activity or award forest growth for time while the app was not running. Completed rest counts describe completed timers, not verified gaze or health outcomes.

## Backup files and recovery

The “数据与备份” window can export all forests, trees, event records and portable settings to a versioned JSON file you choose. The export includes rhythm, reminder choices, weather, onboarding and the automatic update-check preference. It excludes the running timer, temporary snooze/DND deadlines, macOS login-item registration and update caches.

Exported JSON is readable and unencrypted. It can contain forest names, settings and rest timestamps. Restling does not upload the file. If you choose a folder managed by iCloud Drive or another sync service, that service handles the file according to its own settings.

Import validates the file before offering a replacement preview. Confirming replaces all local forests, portable settings and events; it does not replay rewards or merge totals. The current dataset is first written to a local safety file under:

```text
~/Library/Application Support/Restling/Backups/
```

The latest safety copy can be reviewed and restored from the app after relaunch. Restoring a safety copy also preserves the current dataset in a new safety file; older safety files are retained. If the current archive is unreadable, its safety copy contains the exact original bytes together with portable settings. That local recovery file can return the app to its previous unreadable state, with a review warning and reminders paused. A valid backup can then be used to repair it again. The app writes each safety file atomically, checks its bytes and synchronizes it before applying the restore. This reduces recovery risk but does not promise a transaction spanning every preference key or protection from all power-loss, filesystem or hardware failures.

When an existing forest archive is unreadable, its original bytes are protected and may be exported for recovery. In that state, the temporary forest is identified separately and is not exported as a complete backup. A valid portable backup may still be restored after preserving those bytes in a safety copy. Raw exports and local original-recovery files are not accepted as portable backup imports; the app's return-to-previous-state action handles its own recovery files. Explicit profile changes can create a new usable archive after retaining unreadable bytes in local preferences; those retained raw bytes are not included in the new dataset's normal backup. Export the raw original first if you need a portable copy of it.

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

This removes active forests and preferences listed in the cask. Automatic safety copies in the Application Support folder and manually exported files are retained; remove those separately only if you also want to discard them. Restling has no developer-operated cloud copy to restore.

## Questions

Report privacy questions through the [Restling issue tracker](https://github.com/yuki-uix/restling/issues). Issues are public; avoid posting personal forest exports or other private information.
