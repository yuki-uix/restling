# Restling backup format

Restling 0.10.0 introduces event storage and a local, versioned JSON backup. It does not add an account, cloud sync, daily calendar or weekly report.

## File envelope

The supported backup envelope has `format: "restling-backup"` and `version: 1`. It contains:

| Field | Meaning |
| --- | --- |
| `format` | The Restling backup marker. |
| `version` | Backup format version, currently `1`. |
| `createdAt` | When this backup snapshot was captured. |
| `forest` | The version `2` forest archive described below. |
| `settings` | Portable application preferences. |

Files are UTF-8 JSON, formatted with sorted keys and indentation. Every encoded date uses Swift `JSONEncoder`'s default numeric representation: seconds since **2001-01-01 00:00:00 UTC**, not Unix seconds or an ISO 8601 string. Fractional seconds are retained.

Portable backup files have a maximum encoded or imported size of **20 MiB (20 × 1,024 × 1,024 bytes)**. A raw export of an unreadable original archive is a separate recovery artifact, not a validated backup envelope.

## Forest archive and migration

The `forest` object contains `version: 2`, `profiles`, `activeProfileID`, `events` and `recordingStartedAt`. Profiles preserve IDs, names, growth totals, tree IDs/species/planting dates, selected species, visual seed and credited rest IDs. Forest and event data are encoded together in the local `forestProfiles.v1` UserDefaults value; the key name is retained for continuity even though the contained archive is version 2.

When reading a valid version 1 local forest archive, the app preserves its original bytes and migrates the cumulative progress and trees. It starts an empty detailed event collection and records when that collection began. A profile's cumulative completed rests can therefore exceed its number of detailed completed events. Missing historical event dates are not reconstructed from tree dates or aggregate totals.

Restling 0.11.0 retains this archive shape and the existing `oak`, `pine` and `blossom` values, and adds `birch`, `willow` and `ginkgo`. Existing valid backups remain readable in the new app. A backup that contains any new species requires Restling 0.11.0 or later; an older app cannot be assumed to read it. Ecological discoveries are derived from cumulative completed rests and their fixed grove locations, so they add no stored event or reward when an archive is imported or the app is upgraded.

Each new terminal event contains:

| Field | Meaning |
| --- | --- |
| `id` | Stable UUID for the real rest attempt; also used for reward deduplication. |
| `profileID` | The forest that owned the attempt. |
| `occurredAt` | Time the attempt reached its terminal result. |
| `configuredSeconds` | Planned timer duration, not a measurement of offscreen time. |
| `outcome` | `completed` or `skipped`. |

`completed` describes natural completion of a real rest timer. `skipped` describes an unfinished attempt that ended, including explicit skip, snooze during a break, reset or a policy change that cancels the attempt. A preview produces no event. Pausing, sleeping or quitting can preserve the same unfinished attempt rather than immediately produce a skipped result. Snoozing before a real break has started does not invent a break event.

Only completion can award growth. Skipped records never increase rest totals or trees, and a duplicate terminal callback cannot change a previously recorded outcome or award a second reward. None of these fields proves gaze direction, adherence or a medical effect.

## Portable settings

`settings` includes:

- `eyeRest`: use interval and rest duration.
- `reminders`: working days/hours, prewarning, idle threshold, return grace and separate sound preferences.
- `weatherChoice`: automatic or a supported local forest atmosphere.
- `hasSeenOnboarding`: local onboarding preference.
- `automaticUpdateChecksEnabled`: preference for automatic update checks.

It excludes active timer state/session IDs, temporary snooze or do-not-disturb deadlines, current sleep/lock/idle state, macOS login-item registration, update-check timestamps/cached metadata/ignored versions, and system credentials. Recovery does not register a login item or resume an old timer.

## Validation and replacement

The app validates the complete candidate before offering a review. It rejects an unsupported marker/version, malformed or oversized JSON, missing or invalid settings, inconsistent profile selection, duplicate event IDs, events whose profile is missing, and incompatible event/reward totals. Backup validation is strict: it does not silently clamp invalid preferences or substitute a locked species.

The review shows the file name and snapshot time, plus current and incoming forest, tree, completed-rest and event counts. Confirmation replaces the entire forest archive and portable settings; records and totals are installed directly, not merged or replayed through reward methods. The active timer identity and temporary deadlines are discarded. Reminders remain paused at a fresh use interval until the user starts them.

Selecting a file, cancelling the review or failing validation does not apply its data. A safety-file write/read-back failure cancels the restore before the existing dataset is replaced. If the original local archive is unreadable, the app protects its bytes, identifies the fallback forest as temporary and offers raw export. Automatic rest completion or cancellation cannot promote the temporary forest to a complete archive. A valid portable backup can still be selected to repair the data, after the exact unreadable original and current portable settings have been saved in a local safety copy.

In a repair preview, current original counts are marked unavailable rather than being represented by the temporary forest's zero totals. In a preview that returns to a raw original, incoming forest/tree/event counts are omitted because the bytes cannot be parsed. The review explains that the app will return to the previous unreadable state and that a valid backup may be used again to repair it.

An explicit profile change can also start a fresh usable dataset after retaining original bytes in local preferences; normal backups of that new dataset do not include those retained raw bytes. Raw export should therefore be used first when preserving the unreadable original outside this Mac.

## Safety copies and returning to the previous state

At confirmation time, the app snapshots the current dataset, including valid new events recorded while the review was open. It writes that snapshot to a unique `Restling-before-UUID.json` file in:

```text
~/Library/Application Support/Restling/Backups/
```

The file is written atomically, restricted to the current user, read back for comparison and synchronized. A small versioned `latest-recovery.json` pointer selects the latest safety file; previous snapshot files are retained rather than overwritten.

For a readable dataset, the safety file contains a normal `restling-backup` envelope. For an unreadable current archive, it instead uses the internal `restling-original-recovery` format, version `1`, to preserve original bytes and portable settings without decoding or inventing a forest. That format is only consumed by local recovery; the external import picker continues to accept only validated portable backups. Raw export files are also not portable backup envelopes.

“恢复上次恢复前的数据…” loads and validates the latest safety copy and presents the same review. Confirming this restore also saves the current state in a new safety file, so the latest pointer then describes the state before that operation. Repeated restores can therefore alternate between recent states; users should inspect the review rather than assume this is an unlimited undo history. Earlier files can be located using the Finder button.

Returning to an original-recovery snapshot reinstalls its exact raw bytes and portable settings, discards the active timer and leaves reminders paused. The app again identifies the original as unreadable. A later valid portable backup can repair this state, with another safety snapshot taken first.

These files are readable, unencrypted JSON. Restling does not upload them. Atomic file writes, read-back and synchronization improve recovery, but they do not provide a single transaction covering all UserDefaults keys or a guarantee against every power loss, filesystem failure or hardware fault.
