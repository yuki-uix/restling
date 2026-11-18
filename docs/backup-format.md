# Restling backup format

Restling keeps forest progress and terminal timer records in a local, versioned JSON archive. Version 0.14.0 adds weekly forests, their layouts and cross-week cultivation state. The yearbook is local; it does not add an account or cloud sync.

## File envelope

The supported backup envelope has `format: "restling-backup"` and `version: 1`. It contains:

| Field | Meaning |
| --- | --- |
| `format` | The Restling backup marker. |
| `version` | Backup format version, currently `1`. |
| `createdAt` | When this backup snapshot was captured. |
| `forest` | The version `3` forest archive described below. Valid earlier backups containing forest archive version `2` remain readable. |
| `settings` | Portable application preferences. |

Files are UTF-8 JSON, formatted with sorted keys and indentation. Every encoded date uses Swift `JSONEncoder`'s default numeric representation: seconds since **2001-01-01 00:00:00 UTC**, not Unix seconds or an ISO 8601 string. Fractional seconds are retained.

Portable backup files have a maximum encoded or imported size of **20 MiB (20 × 1,024 × 1,024 bytes)**. A raw export of an unreadable original archive is a separate recovery artifact, not a validated backup envelope.

## Forest archive and migration

The current `forest` object contains `version: 3`, `profiles`, `activeProfileID`, `events` and `recordingStartedAt`. Profiles preserve IDs, names, growth totals, tree IDs/species/maturity dates, selected species, visual seed and credited rest IDs, and add a `weeklyJourney` record. Forest, weekly history and events are encoded together in the local `forestProfiles.v1` UserDefaults value; the key name is retained for continuity even though the contained archive is version 3.

Valid local version 1 and version 2 archives remain readable. Before converting an old local archive, the app retains its original bytes in local preferences. Migration preserves every profile, old tree ID/species/date and order, seed, old grove layout, cumulative total and existing event. A version 1 local archive has no detailed events; its old cumulative progress stays undated and a detailed-recording start time is recorded. Missing historical dates are not reconstructed from trees or aggregate totals.

Version 3 freezes old progress as the “最初的森林” baseline. Even when old individual events exist, they are not used to backfill new weekly forests. New real completions alone create week records. When an old backup is restored, the old forest is preserved and weekly cultivation begins from that restored baseline; a version 3 backup retains its own complete weekly history and cultivation state.

The backup envelope remains version 1. A forest archive with weekly data must be version 3, and every profile in that archive must have a valid `weeklyJourney`. Version 2 archives must not contain weekly data. New weekly archives and backups require **Restling 0.14.0 or later**; earlier app versions cannot read them. An older backup containing `birch`, `willow` or `ginkgo` still requires at least version 0.11.0 in readers without weekly support. Upgrade compatibility does not imply that an old app can read a new archive.

### Weekly cultivation and baseline

Each `weeklyJourney` has its own version `1` and stores:

| Field | Meaning |
| --- | --- |
| `startedAt` | When the profile began using weekly cultivation. |
| `startingWeek` | The empty Monday–Sunday boundary at that time, not a yearbook attendance entry. |
| `legacyCompletedRests` | The immutable cumulative completed-rest count before weekly cultivation. |
| `legacyRestSeconds` | The cumulative completed-timer duration in that old baseline. |
| `legacyTreeCount` | The number of old trees at the beginning of the profile's ordered `trees` array. |
| `weeks` | Ordered, nonempty week records created by real completed rests. |

The first tree of a new profile takes three completed rests; subsequent trees take 24. If migration preserves an unfinished old three-rest cycle, it completes at its old target before switching to the 24-rest cycle. Cultivation count and target are derived from the baseline and ordered completion IDs, rather than reset at midnight or at a week boundary. The profile's cumulative rests and duration still include both the old baseline and new weeks.

### Week records and layouts

Weeks use the local Gregorian Monday–Sunday calendar. A week has a civil Monday key such as `2026-11-16`; it is not an ISO week-year number. Its end is exclusive. The stored timezone and original boundaries preserve historical date labels, including daylight-saving transitions.

| Field | Meaning |
| --- | --- |
| `id` | The civil date of the week's Monday, in `yyyy-MM-dd` form. |
| `startDate`, `endDate` | Original start and exclusive end instants for that local week. |
| `timeZoneIdentifier` | The timezone used when the week was first recorded. |
| `restIDs` | Ordered IDs of this week's real completed timer outcomes. Their count is the completed-rest count. |
| `totalRestSeconds` | Sum of the corresponding completed events' configured durations. |
| `treeIDs` | Ordered IDs of trees that matured in this week. Each is also a completion ID. |
| `placements` | Pairs of `treeID` and zero-based `slot`, with unique trees and positions. |
| `lastGrowthCount`, `lastGrowthTarget`, `lastSpecies` | The cultivation snapshot after this week's latest recorded completion. |

Opening a week's empty forest does not create a stored week or award growth. A week with one or two completed rests but no mature tree is a valid nonempty record. Entirely unused weeks are not inserted. Unfinished cultivation continues into the next week; a tree belongs to the week of its maturity completion. Historical scenes use the stored week snapshot rather than the current selected species or current plant stage.

Current-week arrangement moves a mature tree or swaps two positions. It changes placements only: ordered tree IDs, species, rest records and rewards remain intact. A page has 16 slots; a high-volume week can have additional pages within the same week. Historical layouts cannot be edited through the app. Layouts are included in backup and restore.

A backward clock or timezone change does not reopen an earlier civil week for new growth. The latest recorded week remains the active boundary until the calendar catches up or advances. This protects existing historical scenes; it is not a claim that the app can determine the user's actual timezone or correct a system clock.

### Existing and future discoveries

Tree-species unlock requirements remain based on cumulative completed rests. Previously earned footprint identities and ecological discoveries are recognized from the frozen old baseline. Existing pond/bridge/visitor scenery stays in its original old grove; new discoveries follow 3/6/10 different recorded weeks and stay in the week that earns them. These weeks need not be consecutive.

The four new footprint conditions use 4, 12 and 26 distinct recorded weeks, and three actual mature species in the same weekly forest. Merely opening an empty week, changing the tree selection, viewing an entry or moving trees does not increase these counters. Footprints are derived from the restored snapshot, not separately claimed rewards or a ledger retained from replaced data.

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

The app validates the complete candidate before offering a review. It rejects an unsupported marker/version, malformed or oversized JSON, missing or invalid settings, inconsistent profile selection, duplicate event IDs, events whose profile is missing, and incompatible event/reward totals. Weekly validation also checks calendar boundaries and timezone, increasing and nonempty week records, unique and correctly owned completion/tree IDs, durations, tree order, cultivation snapshots and layout slots. Each version 3 weekly completion must have a corresponding completed terminal event. Backup validation is strict: it does not silently clamp invalid preferences or substitute a locked species.

The review shows the file name and snapshot time, plus current and incoming forest-profile, tree, completed-rest and event counts. A forest-profile count still means independent profiles, not weekly entries. Confirmation replaces the entire forest archive, including weekly history/layouts/cultivation state, and portable settings. Records and totals are installed directly, not merged or replayed through reward methods. Old version 2 data is normalized to weekly cultivation without inventing history. The active timer identity and temporary deadlines are discarded. Reminders remain paused at a fresh use interval until the user starts them.

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
