# Replay file store verification

`ReplayFileStore` keeps one heavy replay payload per completed match, outside the
key/value preferences store. Three properties of it cannot be proved by a unit
test, so this document is the reproduction script for the parts that need a real
device or browser:

1. Android really writes under the **no-backup** files directory, and nowhere else.
2. The **native** handler rejects an unsafe key on its own, not only because the
   Dart store refused to send it.
3. A payload survives **process death**.

Everything else is covered by `test/data/persistence/replay_file_store_test.dart`
(VM) and `test/data/persistence/replay_file_store_web_test.dart` (browser).

## What the automated gates cover

| Command | Covers |
| --- | --- |
| `dart analyze` | static analysis |
| `flutter test test/data/persistence/` | the store's behaviour on the VM bindings |
| `flutter test` | the full suite; the browser file is skipped by `@TestOn('browser')` |
| `flutter test --platform chrome test/data/persistence/replay_file_store_web_test.dart` | the web adapter against **real** `window.localStorage`, plus injected storage failures |
| `flutter build web --no-pub` | the web adapter compiles under the conditional import |
| `flutter build apk --debug --no-pub` | the Android handler compiles |

`flutter analyze` needs Windows Developer Mode for plugin symlink creation. On a
host without it, use `dart analyze` locally; CI runs `flutter analyze` on Linux.

## The probe

`tools/replay_file_store_probe.dart` is an alternate entrypoint, not part of the
shipped app. It presents five phase buttons and runs nothing on launch, so the
files a phase leaves behind are still on disk when you inspect them.

| Phase | Does | Leaves behind |
| --- | --- | --- |
| A setup | clears probe keys, asserts absence, writes `probe-alpha` and `probe-beta`, reads back, overwrites shorter, restores the long payload, round-trips a key/value entry on the same channel | both replay files |
| B list guard | `listKeys` through the store **and** a raw `listFiles` through the channel | unchanged |
| C native guard | raw channel calls with unsafe keys, bypassing Dart validation | unchanged |
| D resume | reads `probe-alpha` only | unchanged |
| E cleanup | deletes both probe keys | nothing of its own |

Phase B asks the raw channel as well as the store on purpose. The Dart store
filters the listing too, so a store-only check could pass while the native
handler was returning junk.

## Android sequence

`adb` is not on `PATH` on the development host; it lives at
`C:\Users\maged\AppData\Local\Android\Sdk\platform-tools\adb.exe`. Set a shell
alias or use the full path. The package is `com.maiz27.hareegtable`, and
`run-as` works because the debug build is debuggable.

```powershell
flutter emulators --launch Pixel_8a
flutter devices                     # note the emulator id, e.g. emulator-5554
flutter run -d emulator-5554 --target=tools/replay_file_store_probe.dart --no-pub
```

### 1. Tap **A setup**, then pause

Every step must report `PASS` or `INFO`. Leave the app running.

```powershell
adb shell run-as com.maiz27.hareegtable ls no_backup/replays
# expected: probe-alpha.json  probe-beta.json

adb shell run-as com.maiz27.hareegtable cat no_backup/replays/probe-alpha.json
# expected: the Arabic + emoji payload the probe read back in A5

adb shell run-as com.maiz27.hareegtable ls files
# expected: no replay file and no `replays` directory
adb shell run-as com.maiz27.hareegtable ls files/replays
# expected: "No such file or directory"
```

### 2. Inject all four foreign-entry classes, then tap **B list guard**

The redirection must be quoted so it reaches the device's `sh` rather than being
performed by `adb shell`'s own shell — unquoted, the write happens as the `shell`
user in the wrong directory and fails with `No such file or directory` or
`Permission denied`.

```powershell
adb shell run-as com.maiz27.hareegtable mkdir -p no_backup/replays/looks-like-replay.json
adb shell run-as com.maiz27.hareegtable mkdir -p no_backup/replays/probe-delta.json
adb shell "run-as com.maiz27.hareegtable sh -c 'echo staging > no_backup/replays/probe-gamma.json.tmp'"
adb shell "run-as com.maiz27.hareegtable sh -c 'echo notes > no_backup/replays/notes.txt'"
adb shell "run-as com.maiz27.hareegtable sh -c 'echo invalid > \"no_backup/replays/bad key.json\"'"
adb shell run-as com.maiz27.hareegtable ls no_backup/replays
# expected: all seven entries present
```

`probe-delta.json` is a directory sitting on a **valid** key's file name. Steps B3
and B4 read and delete `probe-delta` through the store: the read must report
absent and the delete must report "did not exist" and leave the directory
standing. Confirm afterwards that it is still there — deleting it would mean the
handler recursively removed something that was never a replay payload.

Tap **B**. No restart is needed: the native handler lists the directory on every
call. Both B1 and B2 must report exactly `probe-alpha, probe-beta` — a directory,
a staging sibling, a foreign extension, and a file whose name is not a valid key
are all skipped, and the two real replays still list. B2 is the one that matters:
it is the raw channel answer, so it proves the *native* handler did the skipping
rather than the Dart store filtering afterwards.

### 3. Tap **C native guard**

Sixteen steps, all `PASS`. Fifteen unsafe raw calls answer `invalid_key` from the
native handler with Dart validation bypassed; the last one confirms a valid but
unknown key reads back as `null` rather than as an error.

### 4. Force-stop, relaunch, tap **D resume**

```powershell
adb shell am force-stop com.maiz27.hareegtable
adb shell monkey -p com.maiz27.hareegtable -c android.intent.category.LAUNCHER 1
```

Tap **D**. `probe-alpha` must read back byte-identical. Phase D writes nothing
and asserts nothing about the store being clean, so it is safe to run repeatedly.

### 5. Tap **E cleanup**, then remove the injected entries

Phase E deletes the two replay payloads. The injected entries are not replay keys,
so the store cannot remove them — take them out with `adb`:

```powershell
adb shell "run-as com.maiz27.hareegtable rm \"no_backup/replays/bad key.json\""
adb shell run-as com.maiz27.hareegtable rm no_backup/replays/notes.txt
adb shell run-as com.maiz27.hareegtable rm no_backup/replays/probe-gamma.json.tmp
adb shell run-as com.maiz27.hareegtable rmdir no_backup/replays/looks-like-replay.json
adb shell run-as com.maiz27.hareegtable rmdir no_backup/replays/probe-delta.json
adb shell run-as com.maiz27.hareegtable ls -la no_backup/replays
# expected: only . and ..
```

Installing the probe replaces the normal app on that device, because it shares the
application id. Use an emulator, not a device holding a real match.

### What this does and does not prove

It proves the on-device **location**: payloads live under `no_backup/` and never
under `files/`. It does not exercise a cloud backup or restore, and no claim
about restore behaviour should be drawn from it. `noBackupFilesDir` is excluded
from Android auto backup by definition, which is why no manifest opt-out is
needed.

## Web sequence

```powershell
flutter run -d web-server --web-port 7357 --target=tools/replay_file_store_probe.dart --no-pub
```

Open `http://localhost:7357`. Run phases **A**, **B**, **D**, **E**. Phase C
reports itself as not applicable — a browser has no method channel — rather than
silently passing.

After phase A, open DevTools → Application → Local Storage → `localhost:7357`.
Exactly two new entries must be present, `hareeg_table.replay/probe-alpha` and
`hareeg_table.replay/probe-beta`, and no other key may have appeared.

To reproduce the listing guard in the browser, add
`hareeg_table.replay/bad key` by hand in DevTools and re-run phase B: `listKeys`
must still report only the two valid keys.

## Match history archiving (Sprint 02)

`tools/match_history_probe.dart` is the second alternate entrypoint. It covers
what the storage probe cannot: that a completed match really produces a summary
**and** a replay file through the platform channel, that abandoning writes
nothing, that republishing leaves one pair, and that a transcript survives a
force-stop.

Every match it archives is played through the controller's own legal-action
surface. That matters: publication only writes a replay after replaying the
transcript against the completed state, so a hand-written action would be
rejected and the match would publish non-replayable — proving nothing.

```powershell
flutter build apk --debug --no-pub --target=tools/match_history_probe.dart
adb install -r -d build/app/outputs/flutter-apk/app-debug.apk
adb shell monkey -p com.maiz27.hareegtable -c android.intent.category.LAUNCHER 1
```

### 1. Tap **A setup**

Clears history, then plays and archives a sentinel match. A2 requires
`MatchArchivePublished` — not the non-replayable variant — so a run that fails to
produce a replay fails here rather than passing quietly.

```powershell
adb shell run-as com.maiz27.hareegtable ls no_backup/replays
# expected: exactly one m-sentinel-aaaaaaaa.json
```

### 2. Tap **B abandon**

Saves an active match, abandons it, and asserts no history entry appeared, the
count is unchanged, the sentinel survived, and no active match remains. Confirm
the sentinel replay file is still on disk afterwards.

### 3. Tap **C double publish**

Publishes the same completed match twice. Exactly one summary must result, and
the directory must hold exactly one `m-probe-bbbbbbbb.json`:

```powershell
adb shell run-as com.maiz27.hareegtable ls no_backup/replays
```

### 4. Tap **D recovery**

Saves a terminal checkpoint with no pending record — what a death between steps 1
and 2 leaves — and recovers. No resumable match may remain, and there must still
be exactly one summary.

### 5. Tap **F resume setup**, then force-stop and relaunch, then tap **G resume finish**

```powershell
# after F reports its last pre-stop action
adb shell am force-stop com.maiz27.hareegtable
adb shell monkey -p com.maiz27.hareegtable -c android.intent.category.LAUNCHER 1
# then tap G
```

G is the sprint's headline check on device. It restores the recorder from the
saved checkpoint, plays on, archives, and requires:

- G3: the transcript spans the kill — pre-stop actions **plus** post-resume ones
- G4: the pre-stop actions are unchanged, in order, at the front
- G5: publication is `MatchArchivePublished`, which it can only be if the resumed
  transcript actually replays to the completed state
- G6: the replay read back out of storage holds the whole span

### 6. Tap **E cleanup**

Deletes every history entry. Confirm the directory is empty:

```powershell
adb shell run-as com.maiz27.hareegtable ls -la no_backup/replays
# expected: only . and ..
```

## Browsing history and statistics on device (Sprint 03)

The two screens render summaries only, so their runtime evidence is visual: what
a player actually sees when the data is awkward. The probe seeds that awkward
data; the normal build renders it.

### 1. Seed

```powershell
flutter run -d <emulator-id> --target=tools/match_history_probe.dart --no-pub
```

Tap **H seed browse data**. It clears history and publishes four matches through
the production repository:

| Match | Difficulty | Strictness | Coach | Fifty counters | Replay |
| --- | --- | --- | --- | --- | --- |
| `m-browse1-aaaaaaaa` | Casual | Coaching | on | measured | kept |
| `m-browse2-bbbbbbbb` | Casual | Standard | off | **unmeasured** | kept |
| `m-browse3-cccccccc` | Expert | Strict | off | measured | **deleted** |
| `m-browse4-dddddddd` | Expert | Table | on | measured | kept |

Two difficulties, both coach states, one entry whose replay file is removed
behind the repository's back, and one whose counters were never measured. Those
last two are the cases worth looking at: the first must still be listed as
non-replayable, and the second must make the statistics screen disclose a
smaller Fifty denominator.

### 2. Install the normal build over it

```powershell
flutter build apk --debug --no-pub
adb install -r -d build/app/outputs/flutter-apk/app-debug.apk
```

`-r -d` keeps the seeded data. Uninstalling first would throw it away.

### 3. Capture, scrolling through each section

Four sections plus several full history cards do not fit one portrait screen, so
capture a sequence rather than a single frame:

```powershell
adb exec-out screencap -p > history-top.png
adb shell input swipe 540 1600 540 700
adb exec-out screencap -p > history-scrolled.png
```

Repeat for the statistics screen, capturing **overall**, then each of the three
groupings. Read every capture; one that was taken but not looked at is not
evidence.

Look for:

- history newest-first, with setup and outcome legible on each card
- `m-browse3` present and marked replay unavailable, not hidden
- the coach indicator differing between entries
- statistics showing overall plus all three groupings
- the Fifty denominator disclosure appearing on the slices that contain
  `m-browse2`, and **not** on the fully measured ones

### 4. Prove a delete is durable

Delete one entry from the history screen, then leave the screen and come back —
or relaunch the app — before believing it:

```powershell
adb shell am force-stop com.maiz27.hareegtable
adb shell monkey -p com.maiz27.hareegtable -c android.intent.category.LAUNCHER 1
adb shell run-as com.maiz27.hareegtable ls -la no_backup/replays
```

The entry must be absent from a **fresh** listing, and its replay file gone from
the directory while the others remain. Checking the still-open list instead
proves only that a row disappeared from a widget, which is not the same thing as
both records being gone.

## iOS

There is no iOS runtime path from a Windows host. What can be checked here is the
Swift source: the handler resolves Application Support rather than Caches or
Documents, sets `isExcludedFromBackup` on the replay directory and re-asserts it
on every resolve, writes with `Data.write(options: .atomic)` so a failed write
cannot destroy the committed payload, validates keys independently of Dart, and
answers exactly once on every path.

**Real iOS backup-exclusion acceptance still needs a macOS host or an iOS
device.** It is outstanding, not passed. The equivalent of the Android sequence
is: run the probe on a device, confirm the payload lands in
`Library/Application Support/replays/`, and confirm the directory carries the
`NSURLIsExcludedFromBackupKey` resource value.
