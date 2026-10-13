# Mobile audio device QA protocol

Status: ready for the Android audio discovery spike; no device result exists yet.
Owner: QA/release.
Evidence required for listening, timing, routes, and lifecycle: a physical device. An emulator may help exercise a UI flow, but it must never be entered as device evidence in this protocol.

## Purpose and scope

This is the single-person protocol for the Android audio discovery spike (ADR 0002 stages C1, C2, and C-I) and later audio releases. It assumes one older Android phone, a second sound source or recording phone, and no lab equipment. Record one result form for each device, route, fixture, and scenario; keep recordings and diagnostic exports next to the result.

The protocol derives its scenarios A-E, metrics, result classes, and physical-measurement intent from the web laboratory's `docs/quality/MOBILE_AUDIO_QA.md`. It differs deliberately in these ways:

- It targets the mobile spike rather than a four-device web/mobile comparison: the Founder currently has one Android phone, so C1/C2/C-I are the applicable stages. The full four-device matrix is a release-gate concern in ADR 0002.
- It maps evidence explicitly to ADR gates G1-G10, adds the instrument-buffer check (C-I/G10), the scheduler stress toggle (G3), and stop-tail reporting (G7).
- It marks iOS C3 as blocked rather than asking for a run: there is no signed install path yet; see [issue #44](https://github.com/KornelSzyszka/synesterra-mobile/issues/44).
- It keeps foreground-only as the 1.0 expectation. Background and lock tests verify safe stopping and explicit restart, not background playback.

All gate thresholds below are hypotheses from ADR 0002. Record the numbers even when a threshold is missed; the Founder decides whether to retain or amend a hypothesis after the first device run.

## Before you start

### Identify and prepare the Android phone

1. On the phone, open **Settings > About phone** and record manufacturer, model, Android version, and build number. In **Settings > About phone > Android version**, record the API level if it is shown. Otherwise, after USB debugging is enabled, run `adb shell getprop ro.build.version.sdk` and record its output.
2. Enable Developer options: open **About phone**, tap **Build number** seven times, enter the phone lock credential if asked, then return to **System > Developer options**. Paths vary by manufacturer; use Settings search for “build number” or “USB debugging” if needed.
3. Enable **USB debugging**, connect a data-capable USB cable, accept the computer fingerprint prompt on the phone, and run `adb devices`. Record the device serial and confirm that its state is `device` (not `unauthorized` or `offline`).
4. Install the matching debug APK with `adb install -r <path-to-apk>` (or use the documented `flutter run -d <device-id>` workflow). Open the app once and record build/commit identifier, install method, battery percentage, free storage if known, and whether other audio apps were closed.
5. Note the available routes: built-in speaker, wired/USB audio if available, and Bluetooth device model if available. Bluetooth is not a substitute for wired audio; mark unavailable routes as `not run` with the reason.

### If the phone is older than API 27

Do not exclude it. Record the exact API level and execute the applicable Android stages: ADR 0002 delegates `minSdk` to this device's API, never below 24. API 24-26 uses the OpenSL ES fallback, where presentation timestamps are unavailable and output position is approximate; record any missing timestamp/latency estimate as an expected limitation, not as fabricated data. If the API level is below 24, stop and record `not run — below the supported minimum`; a Founder/coordinator decision is required before changing the supported range.

### Common fixture and run conditions

For every run, record the app build and commit, fixture (`3:2` and/or `5:4`), seed or precomputed-event-list ID, BPM (20, 90, 300), layer count (2, 4), drone on/off, route, and test time. Close competing audio apps, disable any optional audio enhancement that can be disabled without changing the normal route, and keep volume fixed for a route series.

The spike harness is expected to provide Start, Pause, Stop, tempo/scene changes, diagnostics export, and a UI stress toggle. If a named control or diagnostic is not present in the build under test, record that fact and mark the affected gate `not run`; do not infer a result from silence or from a Flutter/emulator test.

## Evidence and gate map

`device` is the highest evidence level for physical timing, routes, lifecycle, and listening. Adapter, scheduler, and engine logs can support a physical run but do not replace its recording/listening evidence. `G1` is applicable only to the later own-engine (A) phase; in option C its physical counterpart is G4.

| Stage / scenario | Main purpose | Gates fed | Required evidence |
|---|---|---|---|
| C1 / A | Stable foreground playback across fixtures, density, controls, routes, and UI stress | G2, G3, G4, G6, G9; G1 only when an A diagnostic build exists | device + logs where available |
| C1 / E | Find long-run loss, drift, xruns, heat, and listening degradation | G2, G3, G5, G9 | device + logs/listening |
| C2 / B | Confirm foreground-only background/lock behaviour and explicit restart | G7, G8 | device + recording/log |
| C2 / C | Confirm interruption safety twice | G7, G8 | device + recording/log |
| C2 / D | Check route changes, Bluetooth, and per-route stop tail | G6, G7, G8 | device + recording/log |
| C-I / instrument buffer | Confirm generated PCM buffers and voice replacement semantics | G10; G2 and G9 when diagnostics expose losses/xruns | device + logs/listening |
| C3 / iOS | C1+C2 plus media-services reset when a signed path exists | applicable G2-G10 | **blocked / not run** until [#44](https://github.com/KornelSzyszka/synesterra-mobile/issues/44) |

## Measurement without lab equipment

Use the same measurement method within a route comparison. The result form records the method and accuracy limit; a value without a method is not valid gate evidence.

### Method 1: second-phone recording with an audible reference

Use a second phone (or any recorder with a microphone) placed at a fixed distance from the test phone's speaker. Play or record a regular metronome/reference click alongside the test audio, then retain the original recording. Mark the planned event or pause time in the app's diagnostic export and align it to the captured reference before measuring onsets.

This is a practical listening and relative-stability check, not a calibrated latency instrument: recorder clock error, microphone automatic gain control, room reflections, placement, and manual onset picking can add several milliseconds or more. Report the method as `second-phone acoustic`, state the approximate sample rate and distance if known, and label absolute output latency as `approximate`. It may support an initial comparison only when its uncertainty is written down.

### Method 2: electrical loopback, only if already available

If compatible hardware and a loopback cable are already at hand, send a reference click and the phone audio to the same recorder/interface, retain the raw file, and document every adapter in the signal path. This avoids room acoustics and normally gives more repeatable onset alignment, but device/adapter latency and clock alignment still remain; it is not automatically sample-accurate. Report it as `electrical loopback` and describe the routing.

### When a measurement cannot be made

Do not substitute a visual animation, an emulator, or an unrecorded impression. Enter `not measured`, `n: 0`, the reason (for example, “no second recorder” or “diagnostics unavailable”), and `not run` or `conditional pass` as appropriate. A gate whose required measurement is absent cannot be claimed as `pass`.

For measured onsets, report `n`, p50, p95, and max. Treat a fixed Bluetooth delay as route output latency, not scheduler jitter. For a 30-minute run, compare one-minute windows to the first window for drift; report clock-rate ppm separately if the analysis can derive it.

## Scenarios

### A. Foreground baseline (C1)

**Purpose:** establish stable playback before lifecycle or route changes.

**Preconditions:** device identified; debug build installed; a selected route; fixtures and diagnostics/stress toggle available if implemented.

1. On the speaker, run `3:2`, then `5:4`, at 20, 90, and 300 BPM.
2. For each fixture, run 2 and then 4 layers, maximum density, and a drone. Perform Pause → Start, Stop → Start, and a tempo change while playing.
3. Repeat with the UI stress toggle off and on. Repeat for wired/USB and Bluetooth when available.
4. Listen for drop-outs, clicks, bursts, double triggers, uneven pulse, or drift. Export diagnostics after each run when available.

**Record:** all fixture/control settings, route, stress state, planned coverage and wake-up lateness if exported, loss/double/voice-limit/xrun counters, listening score, and onset measurements.
**Gates:** G2, G3, G4, G6, G9; G1 only for a phase-A diagnostic build.
**Evidence:** `device` for recording/listening; logs supplement it.

### B. Background and lock (C2)

**Purpose:** verify the foreground-only policy safely.

**Preconditions:** a stable foreground baseline on the route; screen lock available.

1. Start each fixture, switch to another app for 60 seconds, return, and observe the transport state.
2. Start again, lock for 60 seconds, unlock, and observe the transport state.
3. Repeat on speaker and Bluetooth when available.
4. Before pressing Start, verify that no old hit bursts and that playback did not resume on its own. Then use explicit Start and listen for a clean restart.

**Record:** whether sound stopped, transport state on return, explicit action required, any old-generation onset/burst, and measured or logged stop tail.
**Gates:** G7, G8.
**Evidence:** `device` plus recording/log where available.

### C. Interruption (C2)

**Purpose:** verify that an interruption cannot crash, burst, or resume audio automatically.

**Preconditions:** foreground baseline; a safe way to trigger a call, alarm, assistant, or another system audio interruption.

1. Start a fixture and trigger one interruption. End it and observe without pressing Start.
2. Confirm no crash, no late-event burst, no doubled voice, and no automatic resume. Use Start explicitly if the app offers it.
3. Repeat once more using the same or another available interruption source.

**Record:** interruption type, both attempts, app/transport state, generated diagnostics, audible outcome, and any required recovery action.
**Gates:** G7, G8.
**Evidence:** `device` plus recording/log where available.

### D. Route change and Bluetooth (C2)

**Purpose:** isolate route behaviour from scheduler timing.

**Preconditions:** speaker baseline; paired Bluetooth device and/or wired route when available.

1. Start on the speaker, connect Bluetooth, wait for a stable route, disconnect it, and confirm speaker recovery.
2. Repeat with wired/USB audio when available.
3. During each route change, perform Pause or Stop once and measure/record the end of audible older-generation sound where possible.
4. Classify a constant Bluetooth offset as output latency. Record instability, drop-outs, route recovery, automatic resume, and bursts separately.

**Record:** source and destination route, route device model, stabilization observation, output-latency method/result, stop-tail method/result, and lifecycle outcome.
**Gates:** G6, G7, G8.
**Evidence:** `device` plus recording/log where available.

### E. Thirty-minute session (C1)

**Purpose:** expose losses, drift, headroom, and audible degradation over time.

**Preconditions:** maximum density, four layers, drone, selected route, enough battery/storage, and baseline completed.

1. Run for 30 minutes without changing the fixture. Keep the stress toggle state recorded; repeat with stress if practical.
2. At 0, 5, 15, and 30 minutes, record battery, perceived temperature, xrun/underrun or loss counters, and listening notes.
3. Retain recording and diagnostics. Stop early only for crash, unsafe heat, or loss of control; record the exact time and reason.

**Record:** one-minute drift windows when measurable, `n`/p50/p95/max, counters, heat/battery, and two listening scores when two listeners are available (otherwise state one-listener limitation).
**Gates:** G2, G3, G5, G9.
**Evidence:** `device` plus logs/listening.

### Instrument buffer check (C-I)

**Purpose:** prove the ADR B10 contract rather than merely auditioning a static sample.

**Preconditions:** the C-I build can render a recipe to PCM in an isolate, load it from memory, schedule overlapping one-shots, replace a buffer, and expose the required controls/diagnostics.

1. Render a recipe to PCM in an isolate and load the generated buffer from memory; schedule overlapping one-shots at their planned times.
2. While old voices are still audible, replace that buffer. Verify that the old voices finish naturally and newly scheduled voices use the replacement.
3. Keep eight distinct generated buffers loaded at the maximum voice count within the scheduling horizon.
4. Change an instrument parameter, time the change to audible audition with the available measurement method, and retain diagnostics/recording.

**Record:** recipe/parameter IDs, buffer count, voice count, loading path, scheduled vs observed one-shots, replacement result, audition delay, rejected/lost voices, xrun data, and listening notes.
**Gates:** G10; G2/G9 when the build exposes relevant counters.
**Evidence:** `device` plus logs/listening.

## Result classes and gate thresholds

- **Pass:** every applicable required gate has its required evidence and meets its threshold; no crash, lost/double onset, uncontrolled burst, or automatic resume.
- **Conditional pass:** foreground works but a declared, accepted limitation remains (for example foreground-only or a route limitation). Missing mandatory measurement is not hidden as a pass.
- **Fail:** a critical threshold, lifecycle safety rule, or required scenario fails, or the result is not reproducible.
- **Not run:** the scenario or gate could not be performed. State why; this is not a pass or a fail.

| Gate | Record and hypothesis |
|---|---|
| G1 | Phase A only: all non-dropped events start at planned frame ±1 frame; engine log. In C, mark not applicable and use G4. |
| G2 | 30-minute stable foreground: zero late/overflow/voice-limit rejects/lost/double events and no growth in active voices. |
| G3 | With UI stress: minimum planned coverage at least `minLead + 20 ms`; wake-up lateness p99 ≤20 ms, max ≤100 ms. |
| G4 | Speaker/wired jitter: p50 ≤2 ms, p95 ≤5 ms, max ≤20 ms. |
| G5 | 30-minute drift by one-minute window: p50 ≤2 ms, p95 ≤5 ms, max ≤10 ms; report clock ppm separately. |
| G6 | Speaker/wired output latency: p50 ≤50 ms, p95 ≤80 ms, max ≤120 ms. Report Bluetooth, with no universal limit. |
| G7 | No old-generation start after cutoff; no audible drone retrigger on tempo change; report software and route parts of stop tail. B/C software hypothesis: ≤30 ms. |
| G8 | Lifecycle scenarios have no crash, burst, automatic resume, or ambiguous transport state. |
| G9 | B/C: no xruns in 30 minutes and listening score ≥4/5 from two listeners when available. |
| G10 | Generated memory buffers load; overlapping one-shots are scheduled; replacing a buffer preserves sounding voices; audition delay ≤200 ms hypothesis. |

## Result form

Copy this form once per device × route × fixture × scenario. `Evidence level` must be `device` only after a physical-phone run; never enter `emulator` as device evidence.

```markdown
# Audio device QA result

Run ID / date:
Tester:
Build / commit / install method:
Evidence level: device | static | unit | widget | emulator
Evidence restriction: emulator results are not device evidence.

Device manufacturer / model:
Android or iOS version / API level:
Build number / adb serial (if Android):
Battery / available storage / other audio apps closed:
Route: speaker | wired/USB | Bluetooth
Route device / adapters:
Fixture / seed or event-list ID:
BPM / layers / drone / UI stress state:

Stage / scenario: C1-A | C1-E | C2-B | C2-C | C2-D | C-I | C3
Measurement method: second-phone acoustic | electrical loopback | not measured
Method detail, approximate accuracy limit, raw recording/log location:

Gate results (one row per applicable gate):
| Gate | pass | conditional pass | fail | not run | reason / observation | n | p50 | p95 | max | unit / source |
|---|---|---|---|---|---|---:|---:|---:|---:|---|
| G1 | | | | | | | | | | |
| G2 | | | | | | | | | | |
| G3 | | | | | | | | | | |
| G4 | | | | | | | | | | |
| G5 | | | | | | | | | | |
| G6 | | | | | | | | | | |
| G7 | | | | | | | | | | |
| G8 | | | | | | | | | | |
| G9 | | | | | | | | | | |
| G10 | | | | | | | | | | |

Losses / doubles / late / overflow / voice-limit rejects / xruns:
Planned coverage and wake-up latency (if exported):
Output latency / jitter / drift / clock ppm:
Stop tail: command-to-cutoff / audible route tail / method:
Instrument-buffer replacement and audition delay (C-I only):
Listening scores (listener 1, listener 2; or one-listener limitation):
Background / lock / interruption / route transport state:
Heat / battery observations and stop time if ended early:

Overall result: pass | conditional pass | fail | not run
Conditional limitation or not-run reason:
Next action / owner:
Tester sign-off:
```

## iOS status

C3 and later iOS device stages are blocked. The Founder has an iPhone, but there is currently no Mac, Apple Developer account, or signed install path. Record C3 as `not run — blocked pending signed iOS build path; see #44`; do not treat an unsigned CI build, simulator, or static review as iOS device evidence.

## AUD-043 phone run form — pending device

The APK is prepared before the phone is available. Fill in a separate copy of the [result form](#result-form) for every device, route, fixture, and scenario. Until then, every physical gate below is **not run: no device yet**; empty number cells are intentional. An adapter log proves enqueue and buffer actions, not audible timing, xruns, or quality.

**Install and open:** run `adb devices`, confirm the Founder's serial is `device`, check `adb shell getprop ro.build.version.sdk`, then `adb install -r build/app/outputs/flutter-apk/app-debug.apk` or sideload `build/app/outputs/flutter-apk/app-release.apk`. The local release APK uses the project's debug signing configuration for this test only. Open **Synesterra → Audio spike**; no playback starts until **Start**. Leave the unrelated `Medium_Phone_API_36.1` AVD and `com.example.app_1` package untouched.

**Harness controls:** select `3:2` or `5:4`, 20/90/300 BPM, 2/4 layers and Drone on/off; use Start, Pause, Stop and the UI stress switch per scenarios A–E. While playing, tap **Run C-I instrument buffers**: it loads eight generated WAV buffers from isolate-rendered PCM, schedules the configured concurrent-voice bound across them (the first four voices are one four-note chord of distinct buffers; the log records the planned simultaneous count against SoLoud active/total counts and the verified voice cap, to compare with the recording), replaces one buffer while old voices sound and queues a new audition. Export diagnostics after each run; the screen shows a selectable JSON path. Use `adb pull <path-from-screen> <local-results-directory>` to retain it beside the recording. Record the device audio path, build/commit, raw recording, listening score and every applicable gate below.

**Open question for the device run:** is the Founder's phone API level at least 27? The APK uses `minSdk 27`. If the phone is API 24–26, record the level and ask the Founder/coordinator to adjust the test build to that phone's API as ADR 0002 allows; do not label a failed install as an audio gate failure.

```markdown
# AUD-043 Android physical result — not run: no device yet

Run ID / date:
Tester:
Build / commit / install method:
Evidence level: not run: no device yet
Device manufacturer / model:
Android version / API level:
ADB serial:
Route / route hardware:
Fixture / BPM / layers / drone / UI stress:
Scenario: C1-A | C1-E | C2-B | C2-C | C2-D | C-I
Recording method, accuracy limit, raw recording path:
Diagnostics JSON path:

| Gate | Class | Reason | n | p50 | p95 | max | unit / source |
|---|---|---|---:|---:|---:|---:|---|
| G1 | not applicable | Option C uses physical G4 | | | | | |
| G2 | not run | no device yet | | | | | |
| G3 | not run | no device yet | | | | | |
| G4 | not run | no device yet | | | | | |
| G5 | not run | no device yet | | | | | |
| G6 | not run | no device yet | | | | | |
| G7 | not run | no device yet | | | | | |
| G8 | not run | no device yet | | | | | |
| G9 | not run | no device yet | | | | | |
| G10 | not run | no device yet | | | | | |

Loss / double / late / rejected / xrun observations:
Minimum planned coverage / wake-up lateness p99 and max:
Output latency / jitter / drift / clock ppm:
Stop tail (software / route) and method:
C-I buffer count / peak voices / old-source retirement / audition delay:
Listening scores and number of listeners:
Lifecycle state / background / lock / interruption / route observations:
Thirty-minute battery / heat / active-voice trend:
Overall class: not run: no device yet
Engine A or B recommendation: pending device numbers and Founder architecture decision
Next action / owner: Founder identifies and brings phone; audio-platform and QA run this protocol
```

C3 iOS: **not run — no signed install path; see #44**. No Android result decides the iOS engine.

## Prototype v0 on a phone (QA-096)

Scope: the Founder reviews [prototype v0](product/prototype-v0.md) on the physical Android phone. This section is a hand-off. The audio path is the ADR 0002 phase-1 engine and its timing is **not measured** (issue #43), so nothing below claims latency, jitter or sound quality. Three things are kept apart on purpose: [what ran](#what-ran-and-what-it-proves), [what to do on the phone](#flows-on-the-phone), and [what the Founder must listen and look for](#listening-and-looking-checklist-founder).

### Build and install

Debug APK, from the repository root:

```powershell
flutter pub get --enforce-lockfile
flutter build apk --debug
adb devices                                  # the phone must show as `device`
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Or build, install and start in one step: `flutter devices`, then `flutter run -d <device-id>`.

Notes for this Windows host:

- If `adb` is not on `PATH`, call it from the SDK's `platform-tools` folder; take the SDK path from `flutter doctor -v` or `android/local.properties`, not from an assumption about where the SDK lives.
- JDK 17 or 21 only (see [testing](testing.md)).
- `D:\SynesterraBuilds\synesterra-pad-debug.apk` may exist, but it is the older pad-only build from before the loop, arrangement and Learn work. Do not install it for this review; build a fresh APK from the commit under review and write that commit hash in the result.
- Use the phone, not the agent emulator `emulator-5560`, for anything about sound or feel. Never touch the Founder's emulator `emulator-5554`.
- The app opens on the start screen and never plays by itself. The first sound comes from the first Play, a lift on the instrument radar, a preset chip or a test sound.

### What ran and what it proves

These checks ran on the host. They prove the UI flows and the wiring, nothing about sound or feel.

| Check | Level | What it shows |
|---|---|---|
| `test/flows/prototype_flows_test.dart` (4 flows, below) | `widget` | The real app shell, view models, planner, scheduler and `EnginePlaybackRepository` work together; only the audio engine is a fake with a test-owned clock. |
| `flutter test` (narrow and scratch runs) | `unit` / `widget` | The full suite does **not** run in the worktree on this host: `flutter_soloud` needs the MSVC C++ toolchain. It ran only in a scratch copy without that plugin (619 passed; the 2 architecture tests that scan for the plugin failed there because the copy removed their fixture). CI on Linux is the full-suite evidence. |
| `dart format`, `flutter analyze` | `static` | Types and lint. |
| `flutter build apk --debug` | build | The APK builds; no agent installed or ran it. |

Why not `integration_test/`: it needs a device or an emulator, and a flow that checks the engine needs a clock the test controls. A widget-level flow gives the same UI coverage without a device and is repeatable. The real `flutter_soloud` engine is not part of these flows.

The flows, as tests:

1. Create a loop (the Editor's Loop panel starts from a copy of the factory 3:2 loop), switch a step off, Play (the engine starts only then; the first cycle holds exactly the edited number of hits), Stop (engine stopped, nothing pending, silent), Save, go to Library > Loops, tap the loop (it opens in place with the saved step state and name).
2. Arrangement: add 3:2 and 5:4 from the picker, Save, Play. The section index is 0, moves to 1 after the first section's repeats (timed on the fake clock), both layers of the second loop sound, the sequence ends by itself and the engine stops. The saved arrangement opens from Library > Arrangements.
3. Learn: open "Four against five (5:4)", press Try it. The Loop panel shows that lesson's 5:4 loop as an unsaved copy (the library is still empty), and it plays 5 + 4 hits in the first cycle.
4. Instrument: shape a sound on the radar (drag a vertex, or pick a preset chip), name it, Save (the lift sounds once, the saved sound is the shape on screen), choose it as layer 1's sound in a loop, Play. The engine renders a buffer for exactly that sound and nothing is reported as a missing sound.

Mutation check of the flow tests: with the loop save made a no-op, with the sequence reporting section 0 forever, and with Try it ignoring the lesson's loop, the matching flow failed each time (one mutation per run, then reverted).

Not run by any agent: a device, an emulator, the real `flutter_soloud` engine under `flutter test` (its build hook needs MSVC, which this host lacks; the tests ran in a scratch copy without the plugin, see the PR), iOS.

### Flows on the phone

Each flow: steps, then the expected result. Anything else is a finding; write it in the result form.

**Flow 1. Loop: create, play, save, reopen**

1. Start screen > Editor > Loop tab. Expected: a loop "Three against two copy" with two layers, a picture, the text "Not in your library yet", Play at the bottom.
2. Tap a middle step of the 3-step layer twice (on, strong, off). Expected: the picture and the step marks change.
3. Tap Play. Expected: after a short moment the loop sounds, the playhead moves, the button reads Stop.
4. Tap Stop. Expected: the sound ends, the playhead returns to the start, the button reads Play.
5. Change the name, tap Save. Expected: "Saved".
6. Back, Library > Loops tab. Expected: your loop is listed above the factory loops. Tap it. Expected: the Loop panel opens with the same name and the step you switched off.
7. Close the app from the task switcher and open it again. Expected: the loop is still in Library > Loops.

**Flow 2. Arrangement of two loops**

1. Editor > Arrangement tab. Expected: "Add a loop to play." and Play disabled.
2. Add a section and pick "Three against two", add another and pick "Five against four". Expected: two sections in the strip.
3. Save, then Play. Expected: the first section is highlighted; after its repeats the highlight moves to the second; the sequence stops by itself at the end (with "Repeat all" on it starts over).
4. Back, Library > Arrangements, tap the arrangement. Expected: it opens on the Arrangement tab with both sections.

**Flow 3. Learn and Try it**

1. Start screen > Learn > "Four against five (5:4)". Expected: 2-4 plain sentences and a moving picture, no sound.
2. Tap Try it. Expected: the Loop panel opens with "Five against four copy" and the text "Not in your library yet"; Play works. Leaving after edits asks whether to save.

**Flow 4. Shape an instrument and use it**

1. Editor > Instrument tab. Drag a vertex of the radar along its axis, then lift the finger. Expected: only that point moves, the mist changes under the finger and the sound plays once on lift. Tap a preset chip: the shape glides there and the sound plays once.
2. Type a name, Save. Expected: "Saved".
3. Loop tab, tap a layer's sound, pick your instrument, Play. Expected: that layer uses your sound (not silence, not "missing sound").
4. Library > Instruments lists it.

### Listening and looking checklist (Founder)

Nothing here has been checked by an agent. Write each answer as heard or seen on the phone, with the phone model and the route (speaker, wired, Bluetooth). If a line fails, say when it happens, not only that it does.

Listening:

- Play starts on the beat: the first hit comes right after a short fixed gap, not late and not early. Repeat 10 times, also with a layer whose first step is off.
- Stop: the sound ends at once. Does it click or pop? Does anything ring after Stop? Stop while a loud, long hit is sounding, a few times.
- 3:2 feels like three against two: the two layers stay together and steady for 2 minutes, without drifting or stumbling. Same for 5:4 and for the 4:3:2 factory loop.
- Tempo changes while playing (tap tempo + / - repeatedly): the rhythm continues, with no burst of hits and no hole.
- Editing while playing (steps, instrument, note): is the restart at the cycle start audible as a glitch, or clean?
- Volume slider while playing: does the change arrive quickly or only after a moment? (Known: only new hits follow it.)
- Arrangement: the change from one section to the next is on the beat, with no gap and no double hit. Which tempo does the second section play at? (See known issues.)
- Radar: does each axis change what its name says (Brightness, Fullness, Warmth, Air, Softness, Length), from the centre to the edge, in a useful range; is any end too harsh or too quiet? Does every lift sound exactly once, and does an interrupted drag (a call, a system swipe) stay silent? Do the presets ("neutral", "warm drone", "airy pad", "bass", "guitar", "click") sound like their names, and does the glide to them feel calm?
- The three factory instruments (wood, bell, sine) at the default pitches: balanced against each other? Any clipping or distortion with 3-4 layers?
- Interruptions: an incoming call or notification, the screen lock, switching apps. Does sound stop safely, and does Play start cleanly afterwards?

Looking:

- Visualization smoothness: Circle, Timeline and Polygons stay smooth while playing, without stutter, jumps or lag behind the sound; the pulse on a hit matches what you hear.
- Does the playhead restart cleanly at the cycle boundary (no jump back)?
- Polygons: 3:2 shows a triangle and a line, 5:4 a pentagon and a square.
- Lesson text: clear and short enough? Any word you had to guess? Does each picture show what the sentence says? Does Try it do what you expect?
- Touch targets: can you hit the steps, the tempo and the transport buttons with a thumb without mistakes? Is the radar large enough, and are its points easy to grab?
- The "Saved" message after saving an instrument: does it cover the Play button for a moment? (Seen in a widget test layout; unconfirmed on a real screen.)
- Leaving the Editor with unsaved work asks first, and Save, Discard and Cancel behave.
- Colours and text legible in the chosen palette, also in bright light.

### Known issues (from the reviews of #97-#103)

Known and accepted for the prototype, unless the Founder decides otherwise.

Playback and audio ([playback](modules/playback.md), #100):

- The whole sequence plays at the first section's tempo. The other sections' own tempos are not used, so "Five against four" (80 BPM) after "Three against two" (90 BPM) runs at 90.
- A volume change affects only events planned after it; events already queued (up to the 200 ms horizon) keep the old gain.
- A hard cancel (Stop, structure change, tempo change) cuts voices that are already sounding. That can click, and it deviates from ADR 0002 rule 4 in the playback path (the spike keeps the rule). Not measured on a device.
- Timing of everything is unmeasured (issue #43, gates G2-G10).
- Tests that use `flutter_soloud` need the plugin's native build hook, which needs MSVC. This Windows host has none, so `flutter test` fails here as is and agents run the suite in a scratch copy without the plugin. CI (Linux) runs them.

Editor, Library and Learn (#98, #101-#103):

- The Learn tab calls `stop()` without an owner, so it can stop playback that an Editor panel started, if both are active at once (coordinator note on #101).
- "Repeat all" is not persisted: arrangement JSON v1 has no field for it, so it resets when the arrangement is reopened.
- Trait values are not saved: opening a saved instrument shows its shape read back approximately, with a plain note when it is only an approximation.
- The trait mapping, the radar presets and the factory instruments are untuned (Founder `musical` gate, out of scope for v0).
- File saves are atomic against a failed write, but there is no directory fsync after the rename, so a power loss right after Save could lose that save (the previous file stays intact; #98).
- Tags, the test note and the presets were removed from the instrument panel when the pad arrived (#86). Issue #87 tracks it. [instrument pad](product/instrument-pad.md) and [instrument](modules/instrument.md) still say the pad UI is out of scope, which is outdated; #87 corrects them (this task did not change them).
- Out of v0 by decision: true sustain and the drone, noise and pitch-drop instruments, export and import, sharing, free/pro, iOS, localization (#25), background playback.

### Result form for a prototype v0 run

```markdown
# Prototype v0 phone run

Date / tester:
Commit / APK build time:
Phone model / Android version:
Audio route:
Evidence level: device (listening and looking only; no timing numbers)

| Flow | Done | As expected | Notes (what, when, how often) |
|---|---|---|---|
| 1 Loop: create, play, save, reopen | | | |
| 2 Arrangement of two loops | | | |
| 3 Learn and Try it | | | |
| 4 Radar instrument in a loop | | | |

Listening answers (one line per bullet above):
Looking answers (one line per bullet above):
New issues to file:
```
