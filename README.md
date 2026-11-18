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

- Start with bare earth. A new forest's first three completed breaks bring a sprout, a sapling and its first lasting tree. Each subsequent tree takes **24 completed breaks**, with a little progress after every completion.
- A new piece of land belongs to each **Monday–Sunday week**, using the Mac's local Gregorian calendar. Entering a new week displays an empty forest; only a real completed rest creates its dated record. Unused weeks are not filled in. An unfinished plant keeps its growth across weeks, and a mature tree belongs to the week in which it finishes growing.
- Unlock pine and blossom trees after 3 and 6 cumulative completed breaks, then birch at 12, willow at 36 and ginkgo at 72. Tree-species unlock requirements remain unchanged; selecting another species preserves current cultivation progress and every tree already planted.
- Browse all six species in the tree catalogue, including locked trees and their sprout, sapling and mature previews. Changing the species preserves the current growth stage and every tree already planted.
- Enjoy sunlight, moving clouds, breeze and rain. Weather changes the atmosphere, not your progress; Reduce Motion freezes animation.
- Rest behind a native frosted-glass overlay. The whole rest screen gently dims by up to 12% and returns to its original brightness in a 10-second cycle; Reduce Motion keeps the original brightness. This is a local visual effect and does not change your Mac's display brightness. There is nothing to feed or collect during the break. Press Esc to leave early; your existing forest stays safe.
- Keep separate local forest profiles. Previewing or skipping a break does not earn growth.

The default rhythm is adjustable. This is a rest companion, with no streak penalty or withering trees.

## This week's forest and the yearbook

Open **“森林年鉴”** from the main forest card or menu bar. Recorded weeks are grouped by year and month, with a locally drawn thumbnail, their date range, completed-rest count, completed-timer duration and mature-tree count. A week with one or two completed rests is retained even if it has no mature tree. Open a card to inspect the full forest and its records, or visit it in the main window. Opening, browsing or revisiting a forest never creates a completion or awards growth.

**“布置本周林地”** lets you select an already mature tree and move it to another position or swap it with a tree already there. Trees are planted automatically when they mature; arranging them is optional and needs no claiming step. Layout changes save immediately. Historical forests are read-only. A high-volume week with more than 16 mature trees has additional pages within that same week; trees are not discarded and capacity does not trigger a new week.

Existing forests are kept as **“最初的森林”**, including their tree IDs, species, seed, original grove order and layout, cumulative progress and already earned footprints. Existing ecological discoveries remain in their original groves. Old trees or events are not used to invent weekly history. An unfinished old three-rest cycle can finish at its original target; after that, cultivation uses the new 24-rest cycle. Weekly records start with real completions after this change.

The yearbook retains each week's original timezone and date range. If the clock or timezone moves back to an earlier civil week, cultivation stays with the latest recorded week instead of reopening an archived forest. There is no attendance requirement and no need to use the app every week.

## Forest footprints

Open **“森林足迹”** from the main window's forest card or menu bar to browse **22 achievements** for the current forest. Each has a small story, a clear condition and its own progress. Earned footprints appear automatically; there is nothing to claim during a break.

| Group | What leaves a footprint |
| --- | --- |
| First growth | The first completed rest and actual first mature tree; flowers at 6 completed rests and the stream at 12 within one week |
| Exploration | Mushrooms at 24 completed rests in one week; 4 actual mature trees in one week; forests in 2 and 3 different recorded weeks; 100 cumulative completed rests; and 4, 12 and 26 recorded weeks |
| Tree variety | Actually growing mature trees of 2, 4 and all 6 species; growing 3 different mature species within the same week |
| Ecological discoveries | A pond, stone bridge and visitors after 3, 6 and 10 different weeks with completed rests |
| Time for yourself | A cumulative 10 minutes, 1 hour and 3 hours of completed rest timers |

The four new footprints celebrate 4, 12 and 26 recorded weeks, and three mature species in the same weekly forest. Different weeks do **not** need to be consecutive. The original 18 footprint identities remain, and previously earned progress is recognized from the preserved old baseline. Land-related conditions now follow actual trees or recorded weeks rather than filling new land after 48 rests.

Footprints reflect forest progress; they do not add trees, rewards or event records. Unlocking a species or selecting it does not count as growing it. Time footprints count completed timers, not verified gaze or health outcomes.

Each local forest has its own footprints. Existing progress is recognized after upgrading without inventing unlock dates. Taking days away does not reset achievements, and there are no streaks or attendance requirements. Restoring a backup shows the footprints supported by that restored forest snapshot, rather than retaining progress from the replaced data.

## Scenery that stays with your forest

Open **“林地手记”** from the main window's forest card or menu bar to see the next ecological discovery, its condition and the forest it belongs to.

| Different weeks with completed rests | New scenery | Where it stays |
| --- | --- | --- |
| 3 | A reed-lined pond | The third recorded week's forest |
| 6 | A stone bridge over the stream | The sixth recorded week's forest |
| 10 | Rabbit visitors in the grass | The tenth recorded week's forest |

These weeks do not need to be consecutive. Once a discovery appears, the journal takes you back to its forest; it does not move to every new week. A pond, bridge or visitors already earned under the old 36/72/120-rest rules remain in groves 1/2/3 of “最初的森林”. Upgrading, browsing and visiting do not add rests, trees or event records.

The scenery and visitors are for the normal forest window after a break. They do not appear in the 20-second rest overlay, and there is nothing to claim or attend to during the break. Within each new week, flowers, a stream and mushrooms appear at 6, 12 and 24 completed rests; new tree growth follows the slower cultivation cycle.

## Little forest encounters

Version 0.15.0 adds **“林间偶遇”**: a little red bird, a little blue bird, or a cluster of golden mushrooms can appear after a completed rest. They stay with that week's forest. Open a week in **“森林年鉴”** to see their dates and short notes. These are occasional scenery, separate from the fixed pond, bridge and rabbit milestones.

Each forest gets at most one chance per local day with a completed rest: a 25% chance, at most two encounters per week, with no repeated kind in that week. If the first two eligible days find nothing, the third eligible day guarantees one encounter; the days do not need to be consecutive. Extra rests in the same day do not add chances. Results, including days with no encounter, are saved locally. Relaunching or browsing does not roll again, and old records are not retroactively given encounters.

Encounters appear only in the ordinary forest after the break, with a quiet line in the existing completion message and a yearbook note. There are no encounter alerts, sounds, claims, time limits or extra growth rewards. The 20-second rest screen stays free of these additions; Reduce Motion freezes their animation.

## Reminders that fit your day

Open **“提醒设置…”** from the menu bar or the settings button in the main window. Rhythm and reminder choices stay as a draft until you save; cancelling leaves them unchanged.

- **A gentle heads-up:** by default, a small non-activating panel appears 10 seconds before a break. Choose 10, 20 or 30 seconds, or turn it off. During the heads-up or a full-screen break, choose **3 or 5 minutes later**; a later choice replaces the pending deadline and earns no forest growth.
- **Optional working days and hours:** **“启用工作日与时段限制”** is off by default. When off, the day and time controls are hidden and reminders are not restricted by the calendar; other choices such as do-not-disturb, away detection and manual pause still apply. Turn it on to select weekdays and local start/end times. Turning it off keeps those selections for later; Save applies the draft and Cancel leaves the saved preference unchanged. Upgrading preserves whether you already enabled the restriction. A Friday 22:00–06:00 window belongs to Friday and continues into Saturday morning. Equal start/end times mean the whole selected day. Outside an enabled window there is no break overlay or reminder sound; the next eligible window starts a fresh use interval.
- **Temporary do-not-disturb:** choose **30 minutes or 1 hour** from the menu bar, or end it early. The menu shows the reason and recovery time. Reminders resume only when the other restrictions also allow them; a manual pause stays paused.
- **Away and return:** no-input detection is enabled by default after 5 minutes and can be disabled or adjusted. Locking the Mac or meeting the idle threshold cancels the pending break and restarts the use interval. Returning adds a configurable grace period, 30 seconds by default. Keeping still during an active break does not itself interrupt that break.
- **Separate sound controls:** start and end cues can be turned off independently. Previews are silent; blocked reminders do not play either cue. The end cue lets you finish a break without watching its countdown.

System sleep and display sleep freeze the current timer rather than count time away. On return, the grace period applies before a previously running timer continues; a simultaneous lock or idle condition follows the fresh-interval rule above. A snooze that expires during sleep or a long app stall is discarded and a fresh use interval begins; a future snooze deadline survives sleep. Relaunching restores the saved running/paused intention and remaining time, then applies current schedule and presence restrictions. Offline time is not replayed or converted into extra rests or trees.

**Launch at login is off until you enable it.** Its control applies immediately through macOS; it is separate from the sheet's Save/Cancel buttons. If approval is required, use the button to open the system's Login Items settings. Closing the sheet does not undo a login-item change already made.

Changing the 20/20 rhythm restarts the current timer and preserves your existing forest. Reminder preferences, temporary pause deadlines and the saved timer stay on this Mac. No camera or gaze verification is involved; a completed rest means the app's rest timer finished.

## Local records and backups

Open **“数据与备份”** from the main window's footer or the menu bar. It shows totals across all local forest profiles and the date detailed recording began.

- **Keep the progress you already earned.** Older forests migrate with their cumulative rests, rest time, trees and existing detailed events intact. Earlier cumulative progress without individual dates remains undated; Restling does not invent past events or split old forests into weekly records.
- **Record timer outcomes.** Each new real rest attempt has a stable ID, forest ID, terminal time, configured duration and a `completed` or `skipped` result. A natural timer completion can grow the forest; an unfinished attempt earns no growth. Pausing, sleeping or quitting can retain the same attempt, while previews are excluded. These are timer outcomes, not verified gaze or medical results.
- **Export a readable JSON backup.** The file includes every local forest, weekly history, layouts, cultivation state, old baseline, trees, event records and portable settings: rhythm, reminder choices, weather, onboarding and automatic update-check preference. It excludes the running timer, temporary snooze/DND deadlines, macOS login-item registration and update caches. Files are limited to **20 MiB**.
- **Review before replacing.** “从备份恢复…” validates the file and shows current versus incoming counts. Confirming replaces all local forests, portable settings and events; it does not merge or add their totals. Cancelling or a failed validation leaves existing data unchanged. After a successful restore, reminders stay paused at a fresh use interval.
- **Return to the previous state.** Before a restore is applied, Restling writes and checks a local safety copy. “恢复上次恢复前的数据…” reviews that copy before replacing current data. This operation also saves the current state, so the latest safety copy always represents the state before the most recent restore. Safety copies remain available after relaunch; earlier copies are retained in `~/Library/Application Support/Restling/Backups/` and can be found with the Finder button.

If the existing archive cannot be read, the data window identifies the temporary forest and offers **“导出原始存档…”** instead of presenting it as a complete backup. The raw export preserves the unreadable bytes; it is not a validated Restling backup. You can select a valid backup to repair the local data. Before applying it, Restling saves the exact unreadable original and the current portable settings in a local safety file. Returning to that safety copy is explicitly reviewed as a return to the unreadable state, and a valid backup can be selected again to repair it. The app does not display unknown original counts as zero.

Version 0.15.0 writes forest archive **version 4** inside the existing backup envelope **version 1**, so encounter results travel with a backup. Valid older local archives and portable backups remain readable. Restoring an older backup preserves its original forest, then starts weekly cultivation without inventing past weeks or encounters. Version 4 archives and backups require **Restling 0.15.0 or later**; the 0.14.0 reader supports weekly archive version 3 and cannot read version 4. See [the backup format and recovery rules](docs/backup-format.md).

The yearbook is a local record of completed timers. Accounts, cloud sync and mobile clients remain separate work.

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

## Roadmap

Feature planning and progress live in [Restling Projects](https://github.com/users/yuki-uix/projects/6/views/4) (sign in as `yuki-uix` to view the private project):

- [Epic overview](https://github.com/users/yuki-uix/projects/6/views/8): five product goals with native sub-issue progress.
- [Features by Epic](https://github.com/users/yuki-uix/projects/6/views/9): reminder experience (#1–#6), records and data protection (#7–#8), long-term forest ecology (#9–#10), cross-device companionship (#11), and trusted distribution (#12).
- [Feature board](https://github.com/users/yuki-uix/projects/6/views/4): backlog → ready → in progress → validation → done.
- [Feature schedule](https://github.com/users/yuki-uix/projects/6/views/5): Now / Next / Later / Parked / Shipped.
- [Iteration board](https://github.com/users/yuki-uix/projects/6/views/6): agreed Now work, with issue state showing whether each item is queued, in progress or complete. Local records and backup are tracked by [Epic #18](https://github.com/yuki-uix/restling/issues/18); long-term ecology and tree variety are tracked by [Epic #19](https://github.com/yuki-uix/restling/issues/19).
- [Version plan](https://github.com/users/yuki-uix/projects/6/views/7) and public [milestones](https://github.com/yuki-uix/restling/milestones): v0.9 delivers everyday reminders, v0.10 the data foundation and local backups, and v0.11 long-term forest ecology.

Each issue includes acceptance criteria and dependencies. Now selects the next work; it does not mean implementation has started. Plan by version and sequence, then agree dates when an iteration starts. Move one item at a time into implementation and validation. Developer ID signing and notarization remain [parked #12](https://github.com/yuki-uix/restling/issues/12) until the developer membership and certificate are ready.

Epics track product outcomes across versions; milestones stay on feature issues. Existing feature views exclude parent Epics so execution cards are not duplicated. Sub-issue progress covers the currently defined tasks; review each Epic's overall acceptance criteria before closing it. Cross-device scope research alone does not mean cross-device features have shipped. The four v0.8.0 baseline cards remain separate historical records.

Version 0.10.0 delivered Epic #18's data foundation and local backups. Version 0.11.0 completed Epic #19's long-term ecology and tree catalogue scope (#9 and #10), originally included in the v0.10 candidate plan. Version 0.14.0 adds slower cultivation, weekly forests, the yearbook and current-week layout editing. Cross-device work and Developer ID signing/notarization remain separate planned work.

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
