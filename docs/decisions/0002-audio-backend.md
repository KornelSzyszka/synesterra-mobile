# 0002 — Native audio backend and scheduling hand-off

- **Status:** proposed (`architecture` gate, issue #16). Waits for the Founder.
- **Date:** 2026-10-02
- **Revision 2 (2026-10-02):** fixes the Codex review on PR #24 (cancel before the transport guard, render cutoff vs. audible tail, OpenSL ES output time, G3/G5 definitions, signed iOS path). Answers the Founder's C++ question and adds option C.
- **Builds on:** [0001](0001-architecture-style.md) (real-time hand-off, ports `AudioClock` and `VoiceSink`, generation rule).
- **Evidence level:** `static`. Nothing in this record was measured on a device. Every platform behaviour comes from the official documentation listed under [Sources](#sources). Every number marked *hypothesis* waits for the spike.

## Context

Decision 0001 fixed who owns what on the audio path: the native engine is the time source, `TempoMap` is the only beat ↔ audio-time conversion, `PlaybackScheduler` in `lib/data/audio/` wakes up and hands events over, and `VoiceSink` plays events at audio timestamps and drops stale generations. It deliberately left open the engine, the thread model, the lookahead, the `cancelFrom` semantics and how latency is measured. This record closes those questions before any audio code is written.

Inputs:

- Web PLR-004 §4–5 (behaviour reference): a platform adapter owns the monotonic audio time source, lookahead and scheduler wake-up, a `VoiceSink` that executes `RhythmTrigger`s, audio focus and interruptions, background policy, route changes and Bluetooth, and the measurement of real latency. The web lab wakes every 25 ms and plans 100 ms ahead.
- Web PLR-005: Android lists synthesizers, drum machines and music-learning apps as high-performance audio and recommends Oboe/AAudio with low-latency mode and a callback. It recommends a conditional decision, because no physical device was measured. It also proposes a jitter gate (a hypothesis).
- Web PLR-012 and its deliverable `docs/quality/MOBILE_AUDIO_QA.md` in `synesterra-web`: a physical-device QA protocol with a device matrix, scenarios A–E, metrics, threshold hypotheses and a `pass` / `conditional pass` / `fail` form. The spike below reuses it.
- This repository: Flutter 3.35.7 (Dart 3.9), Android `minSdk` 24 (the Flutter default, `flutter.minSdkVersion`), iOS deployment target 13.0. The host is Windows, so iOS builds only in the on-demand macOS CI job ([docs/testing.md](../testing.md)).

### Requirements for the backend

Options below are scored against these.

| ID | Requirement | Source |
|---|---|---|
| B1 | Events start at an exact audio-clock position (sample-accurate), not "as soon as possible" | 0001 hand-off; `change-safety` invariant "the time source is the platform audio clock" |
| B2 | The engine exposes a readable, monotonic audio clock | 0001 `AudioClock` |
| B3 | Pending events can be discarded by generation; an older generation never starts after cancel | 0001 generation rule |
| B4 | Late events are skipped, never replayed as a burst | `change-safety` invariant |
| B5 | Polyphony: several layers plus a drone, overlapping one-shots | PLR-004 §4.2, Resonara |
| B6 | Low, stable output latency; separate reporting of route latency (Bluetooth) | PLR-012 §5 |
| B7 | We control the audio session, focus, interruptions and route changes, and nothing resumes without an explicit Start | PLR-005 invariants; PLR-012 safety rule |
| B8 | Real-time code can be tested without a device | 0001 forces ("deterministic and testable without a device") |
| B9 | No new dependency without a concrete need; any native library is justified in the PR | `change-safety` |

## Decision (summary)

This record decides two things separately:

- **Engine-agnostic, decided now:** the ports and their semantics, the scheduler, the lifecycle policy, the background policy and the measurement. They hold for any engine behind `AudioClock`/`VoiceSink`.
- **The engine:** the target design is **A**, our own thin engine (rows marked *A* below). The recommended *next step* is **option C**: a discovery spike that puts `flutter_soloud` behind the same ports to get device numbers first, then choose between A and B (`flutter_soloud` as the engine). See [Why native code, and why C++](#why-native-code-and-why-c) and [Founder decisions](#founder-decisions).

| Question | Decision |
|---|---|
| Sequencing | **Option C first**: a discovery spike with `flutter_soloud` behind the ports, then A or B depending on the gates |
| Android engine (*A*) | **Oboe** (C++), output stream with `PerformanceMode::LowLatency`, a data callback, `Usage::Game`, the device's native sample rate, exclusive sharing requested (shared accepted) |
| iOS engine (*A*) | **AVAudioEngine with one `AVAudioSourceNode`** whose render block calls the shared C++ core. `AVAudioSession` category `.playback` |
| Shared code (*A*) | One **C++ audio core** used by both platforms: command ring, event queue, generation filter, voice mixer, engine timeline. No platform headers. |
| Packaging (*A*) | A local Flutter FFI plugin package `packages/synesterra_audio_engine/` (legacy `plugin_ffi` template, which works on Flutter 3.35 and gives access to the Flutter plugin API) |
| Hot path (clock, schedule, cancel) | **`dart:ffi`**, synchronous calls into the engine (our C++ core in A; `flutter_soloud`'s FFI API in B and C) |
| Lifecycle (session, focus, interruptions, routes, engine start/stop) | **Platform channels** (a method channel and an event channel), handled in Kotlin and Swift |
| `AudioClock` time | `AudioTime` in microseconds on an **engine timeline** that is monotonic for the life of the process |
| Scheduler wake-up | `Timer.periodic` every **25 ms** plus an immediate replan on every state change; horizon **200 ms** ahead of the render position (both tunable, *hypothesis*) |
| Scheduler thread | The root isolate first. A dedicated background isolate is the planned fallback if the spike's wake-up gate fails. |
| Interruptions | The native side silences first and reports afterwards (in A; in B and C silencing goes through Dart, and the spike measures how long that takes). The transport pauses with `generation++`. **No automatic resume, ever.** |
| Background | **Foreground-only for 1.0** (recommendation, Founder decision). The screen stays awake while the transport plays. |
| Measurement | Physical onset measurement with the PLR-012 protocol for every engine; frame-exact engine-internal logs in A |

The rest of this record explains each row.

## Options

### Android

| Option | B1 | B2 | B3/B4 | B6 | Notes | Verdict |
|---|---|---|---|---|---|---|
| **Oboe** (C++ wrapper over AAudio/OpenSL ES) | own mixer: yes | `getTimestamp` (AAudio only) | own queue: yes | low-latency mode, MMAP exclusive when granted | Android's recommended native audio library [A1]. It calls AAudio on API 27+ and OpenSL ES below [A4] [A5], which covers our `minSdk` 24. It is added as a prefab Maven dependency [A7]. | **chosen** |
| AAudio directly | own mixer: yes | `AAudioStream_getTimestamp`, API 26+ [A3] | yes | same as Oboe on 27+ | No fallback below API 26, so `minSdk` 24–25 would need our own OpenSL ES path. Same API shape as Oboe [A1]. | rejected: Oboe adds the fallback and disconnect handling for little cost |
| OpenSL ES directly | yes | weaker | yes | higher | "Not recommended for new designs" [A1] | rejected |
| Kotlin `AudioTrack` in a write loop, with our own mixer in Kotlin | possible (we write the PCM) | `getTimestamp(AudioTimestamp)` | own queue: yes | `PERFORMANCE_MODE_LOW_LATENCY` since API 26, but it "requires careful buffer management", with small writes and buffer tuning against underruns [A12] | A blocking-write model on a JVM thread, not a callback. It is the Android path without C++ (see [Why native code, and why C++](#why-native-code-and-why-c)). | rejected: Android's guidance for this class of app is Oboe/AAudio [A1], and every real-time rule would exist twice (here and in Swift) |
| `SoundPool` | no scheduled start | no | no | — | Plays short samples on demand | rejected |

Facts that shape the Android design:

- The lowest latency needs `PerformanceMode::LowLatency` with a high-priority data callback [A2] [A4]. The native sample rate avoids a higher-latency resampling path [A4]. Exclusive streams may get MMAP access for the lowest latency but are "more likely to get disconnected" [A2] [A4]. `Usage::Game` helps latency, "especially when connected to Bluetooth headsets" [A4].
- The callback must not allocate, take locks, do file or network I/O, sleep, or stop or close the stream [A6]. The core is designed for this (see [Threads](#threads)).
- A stream is disconnected when headphones are unplugged, when a device stops being the primary device, or on an internal error. A disconnected stream must be stopped and closed, and that must not happen on the error-callback thread [A2]. Oboe's `onErrorAfterClose` is the place to open a new stream [A6].
- `getTimestamp` returns the presentation time of a frame on `CLOCK_MONOTONIC` [A3]. On OpenSL ES streams it returns `ErrorUnimplemented` [A6]. On API 24–26 the clock's output-latency estimate is therefore degraded (see [Risks](#risks)).
- Underruns are counted by `getXRunCount` [A2]. Buffer size is tuned in multiples of the burst size; double buffering is the documented starting point [A2] [A4].

### iOS

| Option | B1 | B3 | B5 | Notes | Verdict |
|---|---|---|---|---|---|
| **AVAudioEngine + `AVAudioSourceNode`** with the shared C++ core in its render block | own mixer: yes | own queue: yes | own mixer | iOS 13+ [I2], which matches our deployment target. The render block receives the HAL timestamp and the frame count [I3]. | **chosen** |
| AVAudioEngine + `AVAudioPlayerNode.scheduleBuffer(at:)` per hit | sample time: yes [I4] | **no per-event cancel**: `stop()` clears *all* scheduled events, including ones playing, and resets the player timeline to sample time 0 [I4] [I5] | needs a pool of player nodes | Cancelling one generation means stopping and rescheduling every pending buffer and re-anchoring the player timeline. Each platform would also need different real-time logic. | rejected |
| Core Audio RemoteIO audio unit directly | yes | yes | yes | Lowest level, more glue code. The same C++ render function plugs in. | fallback if AVAudioEngine misses the latency gate |

Facts that shape the iOS design:

- `.playback` keeps audio playing with the Silent switch on and when the screen locks. Playing in the background additionally needs `audio` in `UIBackgroundModes`. By default the category is non-mixable and interrupts other non-mixable sessions [I8] [I16]. `.ambient` is silenced by the Silent switch and by screen lock [I9], which a metronome cannot accept.
- The I/O buffer duration is requested with `setPreferredIOBufferDuration`. The documented minimum is at least 5 ms (256 frames), and lower on some hardware [I10]. `outputLatency` reports output latency, and AirPlay can add about 2 s [I11].
- When the hardware's channel count or sample rate changes, the engine stops, uninitializes and posts `AVAudioEngineConfigurationChange`. The engine must not be torn down inside that handler [I6].
- Interruptions: on iOS 27 and later the session posts life-cycle notifications (`didBecomeInactive`, `resumptionRecommendation`), and new code should adopt them. On iOS 26 and earlier, observe `interruptionNotification` [I13] [I12]. Since iOS 10 the system deactivates the session of a suspended app and reports it only when the app runs again [I12].
- Route changes: when headphones are disconnected, apps "should … automatically pause playback". When headphones are connected, playback continues [I14].
- After a media-services reset, rebuild the audio objects and the session configuration, and do not restart playback until the user initiates it [I15].

### Existing Flutter audio plugins

| Plugin | What it offers | Against the requirements | Verdict |
|---|---|---|---|
| `just_audio` | Gapless file/stream playlists; background through `just_audio_background` [P1] | No documented API for starting at an audio-clock time (B1) or reading the clock (B2) | rejected |
| `audioplayers` | Several simultaneous players; a low-latency mode [P2] | No documented scheduled start or clock (B1, B2) | rejected |
| `flutter_soloud` 5.1.x (SoLoud + miniaudio over FFI, MIT) | `playScheduled` at an absolute engine time "with sample accuracy", `getEngineTime`, `getPlayheadTime` [P3] [P4]. `init(lowLatency: true)` is the default; on Android it uses AAudio's MMAP path. The mix buffer defaults to 2048 frames, and a render-ahead ring is optional [P6]. The iOS backend leaves `AVAudioSession` to the app: it sets no category and does not activate or deactivate the session [P7]. | Meets B1/B2. Can satisfy B6 and B7 if we configure it (latency still to measure). A cancelled generation means tracking voice handles in Dart and stopping them (B3). By default only 16 voices play at once; above that the oldest instance of the same sound is stopped or the new one is not played, so the limit must be raised to cover every voice scheduled within the horizon [P8]. Native-first silencing is harder, because our Kotlin/Swift code would have to reach the plugin's engine. A large third-party engine sits on the riskiest path (B8, B9). | **target engine B**; measured first in the discovery spike (option C, [Founder decisions](#founder-decisions)) |
| `audio_session` | Configures `AVAudioSession` and Android audio attributes and focus; streams for interruption and becoming-noisy events; no playback [P5] | Reactions would go through Dart, but B7 needs native-first silencing. Kotlin/Swift code to own this is small. | rejected for A; acceptable in the option C discovery spike, where it shortens setup |

### Dart ↔ native transport

| Option | Hot-path cost | Jank exposure | Threading | Verdict |
|---|---|---|---|---|
| **`dart:ffi` synchronous calls** | No serialization; "considerably faster than platform channels" [F2] | A call costs microseconds and is bounded by batch size | Runs on the calling isolate's thread; FFI works in any isolate | **chosen for clock, schedule, cancel** |
| Method channel for `schedule`, event channel for the clock | Async messages with `StandardMessageCodec` serialization [F1] | Clock readings arrive through the event loop and are stale by the time they are used | Platform handlers run on the platform main thread unless the Task Queue API is used [F1] | rejected for the hot path |
| **Platform channels for lifecycle** | Low-rate messages | Acceptable | Kotlin/Swift code receives focus, session and route callbacks natively | **chosen for lifecycle** |
| `NativeCallable.listener` (native → Dart) | Async, callable from any thread, `void` only [F6] | — | Messages land in the isolate's event loop | kept for later (for example, an engine-fault signal from a C++ control thread). Never called on the audio thread. |

Two Flutter facts set the threading model:

- Since Flutter 3.29, on Android and iOS, "the UI and platform threads are merged … the Dart code runs on the native platform thread" [F2]. The root isolate, its timers and the platform-channel handlers therefore share the main thread with UI work, so a long frame delays the scheduler's wake-up. The horizon absorbs this (see [PlaybackScheduler](#playbackscheduler-wake-up-and-lookahead)), and the background-isolate fallback exists for when it does not.
- Background isolates can call FFI and, through `BackgroundIsolateBinaryMessenger`, send platform-channel messages. They cannot receive unsolicited messages from the platform [F5] [F1]. A background scheduler isolate would therefore get lifecycle events relayed from the root isolate.

Packaging: on Android, FFI binds only to dynamic `.so` libraries. On iOS, static linking is loaded with `DynamicLibrary.process()` [F3] [F4]. Since Flutter 3.38 the docs recommend `package_ffi` with build hooks. The legacy `plugin_ffi` template remains the option that gives access to the Flutter plugin API and static linking on iOS [F3] [F4]. We need both, for the Kotlin/Swift lifecycle code, and we are on 3.35. A local plugin package also avoids hand-editing `Runner.xcodeproj` on a host without Xcode: a podspec with source globs is plain text.

## Why native code, and why C++

The Founder asked whether a C++ core is overkill. Short answer: **native real-time code is required in every option. Writing it ourselves in C++ is justified only if an existing engine cannot pass the gates, and we do not know that yet.** That is why the recommended next step is the cheaper option C (see [Founder decisions](#founder-decisions)).

### Native code is required in every option

- **Dart cannot fill audio buffers.** The audio callback runs on a thread the OS owns (Oboe's high-priority data callback [A4], the AVAudioEngine render block with its HAL timestamp [I3]). A synchronous Dart callback (`NativeCallable.isolateLocal`) may be invoked only on its isolate's own thread and "will abort the process if invoked on any other thread" [F8]. `NativeCallable.listener` can be called from any thread but is asynchronous and returns nothing [F6], so it cannot return samples. Whatever engine we pick, the code that renders audio is native: ours in A, SoLoud's C++ in B.
- **Android's low-latency path is a C/C++ API.** AAudio is part of the NDK [A2] [A3], and Oboe, the recommended library, is C++ [A1]. Lowest latency needs the low-latency performance mode with a high-priority callback [A2] [A4]. The only managed alternative is Kotlin `AudioTrack` in its low-latency mode (API 26+). It uses blocking writes, and the docs warn that it "requires careful buffer management" [A12].
- **The callback rules suit C/C++.** The callback must not allocate memory, use mutexes, do file or network I/O, sleep, or stop the stream [A6]. In C/C++ every allocation and lock is visible in the source, and sanitizers detect memory bugs in native code [A13]. In Kotlin or Swift the runtime may allocate or synchronise without the code showing it. This is our engineering judgement, not a documented rule.

### C++, or Kotlin plus Swift?

| | A: shared C++ core | Kotlin + Swift engines, no C++ | B: `flutter_soloud` |
|---|---|---|---|
| Real-time rules we write (cutoff, skip-late, adoption, timeline) | once | twice, kept identical by review | none in the engine; generation tracking in the Dart adapter |
| Android output path | Oboe callback; AAudio MMAP when granted [A4] | `AudioTrack` low-latency writes [A12] | miniaudio over AAudio, MMAP with `lowLatency: true` [P6] |
| Tests without a device | Linux CI with a fake device | Kotlin on the JVM; Swift only in macOS CI | the plugin's own tests; ours at the adapter only |
| Who owns real-time bugs | us | us, twice | the plugin maintainers |

The Kotlin + Swift path is viable. We reject it because the same rules would be written twice and the Swift half could be tested only in macOS CI.

### Expected size and shape of A

These are estimates from the design above, not measurements, and they will be re-estimated in the implementation task.

| Part | Content | Estimate |
|---|---|---|
| C++ core (`src/`) | SPSC command ring; event pool with generation cutoff and late drop; voice mixer (PCM one-shots with gain/pan, sustained voices with ramps and adoption); engine timeline and seqlock clock; diagnostics ring; C API for FFI | 1,200–1,800 lines |
| C++ core tests | fake device rendering N frames; every rule in [Ports](#ports) | 800–1,200 lines |
| Android host | Oboe stream builder, disconnect and reopen on a control thread (C++); focus, becoming-noisy receiver, channels (Kotlin) | 300–500 C++ + 200–400 Kotlin |
| iOS host | AVAudioEngine + `AVAudioSourceNode` calling the core; `AVAudioSession` observers, channels (Swift, with a small C shim) | 300–500 |
| Dart | hand-written FFI bindings; `FfiAudioClock`, `FfiVoiceSink`, `AudioEngineBridge` | 400–700 |
| Build files | CMake, Gradle, podspec | about 150 |

In total, roughly 2,500–3,500 lines of native code and 1,000 lines of tests. The Kotlin/Swift lifecycle code and the Dart adapters (about 40 % of the total) are needed in B as well.

### Build and debug cost

- **Local Android:** the SDK on the host has NDK 27.0.12077973, which is Flutter 3.35.7's default `ndkVersion`, plus NDK 28 and 29, and CMake 3.22.1 (checked 2026-10-02). Gradle builds C++ through `externalNativeBuild` with CMake [A14]. Android Studio debugs Kotlin and C++ in one session ("Dual (Java + Native)", LLDB) [A15].
- **CI:** the Linux job already runs `flutter build apk --debug`, so it compiles the Android C++. A new host job builds the core with the runner's compiler and runs the core tests under AddressSanitizer and ThreadSanitizer. That adds a few minutes per run (estimate).
- **iOS:** builds only in the on-demand macOS job, with `--no-codesign`. There is no local compiler or debugger. Each iOS change costs one CI run, and debugging on a device needs Xcode on a Mac and a signed build (see S3 in [Spike plan](#spike-plan)).
- **Review:** every PR touching the core needs green S0 tests and the sanitizer job, plus a reviewer who checks the callback rules.

### Risks of our own C++ core

| Risk | Effect | Mitigation |
|---|---|---|
| Memory errors | A native crash takes down the app; Dart cannot catch it | Small core, fixed pools, sanitizers in CI [A13], fuzzing of the command ring |
| Data races between the control and audio threads | Rare, device-dependent glitches | One SPSC ring, atomics only, ThreadSanitizer, single-producer rule |
| Device-specific behaviour (OEM audio paths, Bluetooth) | Found only on devices | Spike gates; this risk exists for B too |
| Slow iOS loop | Every iOS change costs a CI run; device debugging needs a Mac | Keep the iOS host thin; the logic lives in the core tested on Linux |
| Maintenance by one Founder and agents | Real-time C++ is unforgiving | Narrow API; tests document each rule; B stays available behind the same ports |

The corresponding risks of B: a large third-party engine on the riskiest path, breaking changes on upgrades (its changelog lists several in 5.x [P9]), the voice limit [P8], and less control over native-first silencing.

## Engine design

```mermaid
flowchart LR
    subgraph dart["Dart (lib/data/audio/)"]
        sched["PlaybackScheduler"]
        clockA["FfiAudioClock<br/>implements AudioClock"]
        sinkA["FfiVoiceSink<br/>implements VoiceSink"]
        bridge["AudioEngineBridge<br/>lifecycle channels"]
    end
    subgraph pkg["packages/synesterra_audio_engine"]
        bind["lib/: FFI bindings,<br/>channel names (no logic)"]
        subgraph cpp["src/: C++ audio core (no platform headers)"]
            ring["command ring (SPSC, lock-free)"]
            queue["event queue +<br/>generation cutoff"]
            mixer["voice mixer"]
            tl["engine timeline"]
        end
        droid["android/: Oboe stream,<br/>Kotlin focus + noisy receiver"]
        ios["ios/: AVAudioEngine + AVAudioSourceNode,<br/>Swift AVAudioSession observers"]
    end
    sched --> clockA
    sched --> sinkA
    clockA --> bind
    sinkA --> bind
    bridge <--> bind
    bind -- "dart:ffi" --> ring
    bind -- "dart:ffi" --> tl
    ring --> queue --> mixer
    droid -- "data callback" --> mixer
    ios -- "render block" --> mixer
    droid -- "event channel" --> bridge
    ios -- "event channel" --> bridge
```

- The C++ core owns everything that runs on the audio thread. It has no Android or Apple headers, so CI can build and test it on Linux against a fake device that renders N frames (B8).
- The Android and iOS hosts own only the device stream and the platform lifecycle. Each calls the same `render(frames, deviceTimestamp)` entry point.
- The package does not depend on `synesterra_core`. The Dart adapters in `lib/data/audio/` map core types to the engine's C structs, so the engine stays generic and the core stays pure (R1).
- The sound bank (preloaded PCM or simple synthesis for clicks and drone) is loaded at engine start, never on the audio thread. The implementation task chooses the sounds.

### Engine timeline

`AudioTime` is an integer number of microseconds on one engine timeline.

- While a device stream runs, the timeline advances by **rendered frames** ÷ sample rate. It is the audio clock, so it has no drift against the output. The core counts the frames itself, in its own data callback. It does not use Oboe's `getFramesWritten`/`getFramesRead`, which return `ErrorUnimplemented` on OpenSL ES streams [A6]. `renderTime` is therefore available on every Android version we support.
- While no stream runs (stopped, or during a stream restart after a route change), it advances by the host monotonic clock (`CLOCK_MONOTONIC` on Android, host time on iOS).
- It never goes backwards and never restarts for the life of the process. A stream restart or a sample-rate change does not invalidate already-computed `AudioTime`s. The native side converts `AudioTime` → frame with the current stream's anchor and rate. Rounding stays below one frame (about 21 µs at 48 kHz).

This is simpler than exposing raw frame counters, which restart with every stream (Oboe reopen, AVAudioEngine restart after a configuration change [I6]).

### Threads

| Thread | Work | Rules |
|---|---|---|
| Audio callback (Oboe high-priority data callback / AVAudioEngine render block) | Drain the command ring; drop events older than the generation cutoff or already late; start voices at their exact frame offset; mix; publish `(renderFrame, timelineTime)` through a seqlock | No allocation, locks, I/O, sleep or stream control [A6]. Fixed-capacity pools allocated at engine start. |
| Dart scheduler isolate (the root isolate first, which is the platform main thread since Flutter 3.29 [F2]) | `AudioClock.now()`, planning, `VoiceSink.schedule` / `cancelFrom` over FFI | Single producer: every FFI write comes from one isolate. A call never blocks and is O(batch size). |
| Platform main thread | Method/event channel handlers, focus listener, `AVAudioSession` notifications (posted on the main thread [I12] [I15]) | Low rate. Silences the core directly (native-first), then reports to Dart. |
| Native control thread | Reopening a disconnected Oboe stream (not on the error-callback thread [A2]); periodic `getTimestamp` for the latency estimate | Never touches the mixer except through the core's control API |

## Ports

These are the signatures the core's `ports/` will declare. Under R2, `ports` may use `playback` types. `AudioTime` and `Generation` live in `playback/`, because `TempoMap` produces `AudioTime`.

```dart
// packages/synesterra_core/lib/src/playback/audio_time.dart
/// A point on the engine timeline, in microseconds. Monotonic for the life of
/// the process. Validated non-negative on construction.
final class AudioTime implements Comparable<AudioTime> {
  AudioTime(this.microseconds);
  final int microseconds;
  AudioTime operator +(Duration offset);
  Duration operator -(AudioTime other);
}

// packages/synesterra_core/lib/src/ports/audio_clock.dart
enum EngineState { stopped, starting, running, interrupted }

final class AudioClockReading {
  /// Timeline time of the first frame the engine has not rendered yet.
  final AudioTime renderTime;

  /// Estimated timeline time of the frame leaving the output now, from the
  /// platform's presentation timestamp. For position display and visuals
  /// only. Null when the platform provides no presentation timestamp (Oboe on
  /// OpenSL ES, Android 24–26); callers then use renderTime minus
  /// [fallbackOutputLatency] and show the position as approximate.
  final AudioTime? outputTime;

  /// The engine's static estimate (buffer size ÷ sample rate) used when
  /// [outputTime] is null. Never used for scheduling.
  final Duration fallbackOutputLatency;

  /// Smallest safe distance between renderTime and an event handed to
  /// VoiceSink (about one callback period plus margin, reported by the engine).
  final Duration minLead;

  final EngineState state;
}

abstract interface class AudioClock {
  /// Synchronous and cheap: an atomic read of state the audio thread
  /// published. Never waits for the audio thread.
  AudioClockReading now();
}

// packages/synesterra_core/lib/src/ports/voice_sink.dart
sealed class VoiceEvent {
  /// When the event starts, on the engine timeline. Never a beat.
  AudioTime get at;

  /// Correlates the planned event with the engine's execution log (QA).
  int get eventId;
}

/// A one-shot voice (a rhythm hit). Gain and pan already include the mix.
final class Trigger implements VoiceEvent { /* at, eventId, sound, gain, pan */ }

/// Starts, or retunes, a sustained voice identified by key (the drone).
final class SustainOn implements VoiceEvent { /* at, eventId, key, sound, gain, pan */ }

/// Releases a sustained voice with a short ramp.
final class SustainOff implements VoiceEvent { /* at, eventId, key */ }

abstract interface class VoiceSink {
  /// Queues events planned under [generation]. Never blocks. Returns
  /// normally even when it drops events; drops are counted in diagnostics.
  void schedule(Generation generation, List<VoiceEvent> events);

  /// From now on, only events of [generation] or newer may start.
  void cancelFrom(Generation generation);
}
```

The parameters of a drone voice (pitch set, timbre) are fixed by the first harmony audio task. This record fixes only timing and generation semantics.

### `schedule` semantics

1. Events are copied into a staging buffer that the engine allocates once, then committed into the command ring. There is no per-call allocation on either side, and `package:ffi` is not needed.
2. A batch whose generation is older than the current cutoff is dropped as a whole and counted as `stale`.
3. When the audio thread dequeues an event whose frame has already been rendered, it **drops** the event and counts it as `late`. It never plays an event late, so a stall produces a gap, never a burst (B4).
4. If the ring or the event pool is full, the overflowing events are dropped, counted as `overflow` and reported as an engine fault. Capacities come from the session validation limits (maximum density × horizon), with a 2× margin.

### `cancelFrom(generation)` semantics

1. `cancelFrom` stores the cutoff in an atomic that the audio thread reads **before starting each voice**, and enqueues a purge command into the ring. Ordering is preserved: a `cancelFrom` followed by `schedule` of the new generation is applied in that order.
2. **What is guaranteed is the render cutoff.** Once the audio thread observes the cutoff, no older-generation event starts in any frame it renders afterwards. A callback already running when the cutoff is stored may still start an older event in frames it has not finished, so the bound is one callback period of *rendered* audio.
3. **What is not bounded by software is the audible output tail.** Audio already rendered keeps playing from every buffer downstream: the device buffer, the Bluetooth codec path, or AirPlay, which can add about 2 s [I11]. That tail equals the route's output latency and is *not* bounded by `minLead`, because `minLead` is the scheduler's insertion slack, not the depth of the output path. The tail is therefore **measured and reported per route** (the `stop tail` metric in [Latency and jitter measurement](#latency-and-jitter-measurement)). Over Bluetooth it may be long; that is a property of the route, not a scheduler fault.
4. One-shot voices already sounding finish their natural envelope. Clicks are short, and cutting them on every tempo-drag step would itself be audible.
5. Sustained voices of an older generation are **orphaned**, not cut. A `SustainOn` of a newer generation with the same key whose `at` falls within the adoption window (default 2 × `minLead`, *hypothesis*) **adopts** the voice: no retrigger, parameters ramp to the new values. An orphan that nobody adopts is released with a short ramp when the window ends. This keeps the drone continuous across a tempo or scene change and still silences it on pause and stop, where nothing new is scheduled.
6. Cutoffs are monotonic. A `cancelFrom` with a generation that is not newer than the current cutoff does nothing.
7. `cancelFrom` works in every engine and transport state. When the stream is stopped or interrupted, the cutoff and the purge are still applied, so nothing older can start when the stream runs again.

## PlaybackScheduler: wake-up and lookahead

```text
plannedToBeat: Beat?   // end of the last planned window (exclusive)

replan(reason):        // on every tick and immediately on every state change
  // 1. The generation cutoff comes first, in every transport and engine state.
  //    Pause and Stop increment the generation, so this is what silences them.
  if runtime.generation != lastGeneration:
    sink.cancelFrom(runtime.generation)         // purge pending, orphan sustained voices
    lastGeneration = runtime.generation
    plannedToBeat = null                        // plan again from the current time
  // 2. Only then decide whether to plan anything new.
  r = clock.now()
  if runtime.transport != playing or r.state != running: return
  earliest = r.renderTime + r.minLead
  fromBeat = max(plannedToBeat ?? anchorBeat, TempoMap.beatAt(earliest))   // skip-late, never plan the past
  toBeat   = TempoMap.beatAt(r.renderTime + horizon)
  if toBeat <= fromBeat: return
  events = EventPlanner(project, runtime, [fromBeat, toBeat))              // half-open window
  sink.schedule(runtime.generation, events.map(TempoMap.audioTimeOf))
  plannedToBeat = toBeat
```

- **Pause and Stop:** both increment the generation, and `PlaybackRepository` calls `replan` synchronously. `cancelFrom` therefore runs before the "not playing" guard: queued hits are purged, and the drone is orphaned and released when its adoption window ends, because nothing new adopts it. An interruption takes the same path after the native side has already silenced the output. S0 tests this (pause and stop with pending hits and a drone).
- **Wake-up:** `Timer.periodic(25 ms)`. Timers only wake the scheduler; they never measure time (`change-safety`). A state change from `PlaybackRepository` calls `replan` synchronously, so pause, tempo and scene changes take effect after `minLead`, not after a tick.
- **Horizon:** 200 ms ahead of `renderTime` (*hypothesis*, tuned in the spike). A larger horizon does not delay user changes, because a generation change re-plans from `renderTime + minLead` at once. It costs only discarded planning work and queue capacity. In exchange it hides a Dart stall of up to about `horizon − minLead` without any audible effect.
- **Window continuity:** the next window starts exactly at the previous `toBeat`, kept in beats rather than recomputed from time, so rounding can never double or drop a hit at a boundary. The only forward jump is the skip-late `max(...)`. After a stall, the beats between `plannedToBeat` and `beatAt(earliest)` are skipped on purpose.
- **Start:** `PlaybackRepository` asks `AudioEngineBridge` to start (focus or session activation, then stream start). When the engine reports `running`, the transport anchors its start beat at `renderTime + minLead + startPad` (default 30 ms, *hypothesis*) and calls `replan`.
- **Position for the UI:** `TempoMap.beatAt(outputTime)`, read-only. It is what the listener hears, apart from the display's own latency, which is measured separately. When `outputTime` is null (OpenSL ES), the UI uses `renderTime − fallbackOutputLatency` and treats the position as approximate.
- **Fallback:** if the spike's wake-up gate fails on the root isolate, `PlaybackScheduler` moves into a long-lived background isolate [F5]. That isolate receives immutable `SessionProject`/`RuntimePerformanceState` snapshots over a `SendPort` and calls FFI itself. The ports and the single-producer rule do not change. The extra state copy is the cost, which is why this is not the first choice.

```mermaid
sequenceDiagram
    participant PR as PlaybackRepository
    participant PS as PlaybackScheduler
    participant C as AudioClock (FFI)
    participant S as VoiceSink (FFI)
    participant A as Audio thread (C++ core)
    PR->>PS: tempo change (generation 7 to 8)
    PS->>S: cancelFrom(8)
    S->>A: store cutoff 8 (atomic), enqueue purge
    PS->>C: now()
    C-->>PS: renderTime, minLead
    PS->>S: schedule(8, events from renderTime + minLead)
    loop every audio callback
        A->>A: drain ring, drop gen < 8, drop late events
        A->>A: start voices at exact frames, mix
        A->>A: publish renderTime
    end
    loop every 25 ms
        PS->>C: now()
        PS->>S: schedule(8, next window)
    end
```

## Interruptions, audio focus, routes, Bluetooth and background

Policy: **the native side silences first, then reports.** Kotlin and Swift react inside the platform callback: a short gain ramp to silence in the core, then the stream stops if the event requires it. They then send an event over the event channel. `PlaybackRepository` moves the transport to `paused` and increments `generation` (an interruption is one of the generation triggers in 0001). The engine never resumes by itself. Playback continues only after the user presses Start. This deliberately ignores the platform hints that would allow automatic resume (`AUDIOFOCUS_GAIN` after a transient loss [A8], `shouldResume` on iOS [I13]), following the PLR-005 and PLR-012 rule.

| Event | Android signal | iOS signal | Native reaction | Transport |
|---|---|---|---|---|
| Phone call, assistant, alarm, another app takes audio | `AUDIOFOCUS_LOSS` or `AUDIOFOCUS_LOSS_TRANSIENT` [A8] | `didBecomeInactive` (iOS 27+) or `interruptionNotification` `.began` [I13] [I12] | Ramp to silence, stop the stream | `paused`, `generation++`; Start required |
| Another app ducks us (navigation prompt) | `AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK`; Android 8+ ducks automatically [A8] | (session-dependent) | Keep playing, ducked by the system | unchanged |
| Headphones or Bluetooth disconnected | `ACTION_AUDIO_BECOMING_NOISY` [A9]; the stream is disconnected [A2] | `routeChangeNotification`, reason `oldDeviceUnavailable` [I14] | Ramp to silence; reopen the stream on the new default device but stay silent | `paused`, `generation++` (Apple: "automatically pause" [I14]; Android: users expect apps with playback controls to pause [A9]) |
| Headphones or Bluetooth connected | The stream is disconnected because the device is no longer primary [A2] | `newDeviceAvailable` [I14]; `AVAudioEngineConfigurationChange` if the rate or channels change [I6] | Reopen or restart on the new route; the timeline continues; events that fell into the gap are dropped as late | keeps playing (Apple: connecting headphones continues playback [I14]); a route event goes to the UI and diagnostics |
| Media services reset (iOS) | — | `mediaServicesWereResetNotification` [I15] | Rebuild the engine and session configuration | `paused`, `generation++`; Start required [I15] |
| App leaves the foreground | `AppLifecycleState.hidden`/`paused` [F7] | same [F7] | Ramp to silence, stop the stream, abandon focus or deactivate the session [I12] | `paused`, `generation++` (foreground-only) |
| App `inactive` (control centre, app switcher, call banner) | [F7] | [F7] | none | unchanged; a real interruption arrives through the rows above |

Notes:

- **Focus and session:** Android requests `AUDIOFOCUS_GAIN` with an `AudioFocusRequest`, usage game and content type music, and delayed gain accepted [A8]. From Android 12 the system enforces focus, fades out the losing app and mutes it [A8]. iOS uses `.playback`, non-mixable for 1.0 [I8].
- **Background (proposal: foreground-only for 1.0).** Playing in the background would need, on Android, a foreground service of type `mediaPlayback` with `FOREGROUND_SERVICE_MEDIA_PLAYBACK` (types required since Android 14) [A10]; apps targeting Android 15 cannot request focus unless they are the top app or run a foreground service [A8]. On iOS it would need `audio` in `UIBackgroundModes` [I8] [I16]. Without these, iOS deactivates the session of a suspended app [I12], so locking the screen stops sound. Instead, 1.0 keeps the screen awake while the transport plays (`FLAG_KEEP_SCREEN_ON` / `isIdleTimerDisabled`, native one-liners, no plugin). Background or locked-screen playback is a Founder decision (see [Founder decisions](#founder-decisions)). If it is accepted, PLR-012 scenario B becomes a pass criterion instead of a documented limitation.
- **Bluetooth:** Bluetooth adds a large, stable output latency, which is reported separately and never counted as scheduler jitter (PLR-012 §4D). `outputTime` uses the platform latency estimate (`getTimestamp` [A3], `outputLatency` [I11]) so that visuals follow what is heard. The estimate is checked physically in the spike.
- **Stream lifetime:** the stream opens on Start. While the app is in the foreground and paused, it stays open rendering silence for an idle timeout (default 10 s, *hypothesis*), so Start stays fast. It closes on Stop, on background or when the timeout expires. Exclusive streams should be closed when not needed [A2], and a stopped engine saves power [I5].

```mermaid
stateDiagram-v2
    [*] --> Stopped
    Stopped --> Starting: user Start
    Starting --> Playing: engine running, anchor set
    Starting --> Stopped: focus or session denied
    Playing --> Paused: user Pause
    Playing --> Paused: interruption, focus loss, device lost, background, media reset
    Playing --> Playing: device connected (stream restart, timeline continues)
    Paused --> Starting: user Start (never automatic)
    Playing --> Stopped: user Stop
    Paused --> Stopped: user Stop
```

## Latency and jitter measurement

Independent sources, never mixed:

| Layer | What | How | Proves |
|---|---|---|---|
| Engine-internal (A only, diagnostic builds) | For each `eventId`: planned frame, rendered frame, or `late`/`stale`/`overflow`; xruns (`getXRunCount` [A2]; on iOS, discontinuities in the render timestamp's sample time); callback duration against the buffer period | A ring buffer of fixed records in the core, exported to a file after the run | That the software is exact: rendered frame = planned frame, no losses, real-time headroom |
| Adapter (B and C) | For each `eventId`: planned `AudioTime`, the SoLoud handle, `getEngineTime` at enqueue, cancels per generation, voices rejected by the voice limit | A Dart-side log; SoLoud's internal render position is not observable | That every planned event reached the engine and every cancel was issued |
| Scheduler | Wake-up lateness (actual minus intended wake-up); planning time; **planned coverage** = `audioTimeOf(plannedToBeat) − renderTime`, sampled at each wake-up before planning, which is how much audio is already queued | Counters in `PlaybackScheduler`, exported with the engine log | That the Dart side stays ahead of the audio thread under UI load |
| Physical | Output latency; jitter; drift; lost and double onsets; **stop tail**; listening (PLR-012 §5) | Electrical loopback or a measurement microphone, onset detection, two listeners (PLR-012 §5) | What a musician hears. Only this is `device` evidence. |
| Platform estimates | `getTimestamp` / `outputLatency` / `getPlayheadTime` compared with the physical output latency | Both recorded in the same run | Whether `outputTime` can drive visuals |

Definitions used by the gates:

- **Onset error.** For each onset, `e = recorded onset − planned time`, after aligning the recording to the plan with one linear fit (offset plus rate). The fitted **rate** is the clock difference between the phone and the recorder. It is reported in ppm and is not counted as drift, because the music deliberately follows the phone's output clock. The fitted **offset** is the route's output latency.
- **Jitter.** The residuals `e` after the fit: p50, p95 and max of `|e|`, over a segment with no lifecycle events.
- **Drift.** For each 1-minute window of the 30-minute run, the median residual minus the median residual of the first window. Drift is reported as p50, p95 and max of the absolute value over the 30 windows. It catches slips that a linear fit cannot absorb, such as lost buffers, rounding that accumulates, or scheduler steps.
- **Stop tail.** The time from the Pause command (host time, logged) to the end of audible older-generation sound at the output, split into the software part (command → cutoff applied, from the log) and the route part (the measured output latency). Reported per route, with no universal limit for Bluetooth or AirPlay, like output latency.

Context for the hypotheses: Android's `android.hardware.audio.low_latency` feature means continuous output latency of 45 ms or less, and `android.hardware.audio.pro` means round-trip latency of 20 ms or less [A11]. The spike records both flags per device. `docs/QA.md` in this repository does not exist yet. The spike task copies the PLR-012 protocol into it (the `QA` area), so it can be read from any worktree.

## Spike plan

One `AUD` task per phase (with the `QA` protocol), after this decision is accepted. Both phases share one harness: the `PlaybackScheduler`, the 3:2 and 5:4 fixtures, diagnostics export, and a minimal screen with Start/Pause/Stop/tempo/scene and a stress toggle that animates a heavy widget. If the `DOM` planner is not ready, the fixture is a precomputed event list in JSON. Its order is compared with the planner later (PLR-012 §8).

**Phase 1, option C (discovery).** Prerequisite: a `MOB` task upgrades Flutter, because every `flutter_soloud` release with `playScheduled` (4.1.0 and later) requires Flutter ≥ 3.41 and Dart ≥ 3.11 [P10] [P9], and the repository is on Flutter 3.35.7 / Dart 3.9. The phase adds `flutter_soloud` as a dependency, justified in its PR. `SoloudAudioClock` maps `getEngineTime` to `renderTime` and `getPlayheadTime` to `outputTime` [P3] (C0 and C1 verify the mapping). `SoloudVoiceSink` calls `playScheduled` per event, keeps the handles by generation, and stops the older handles on `cancelFrom`. The voice limit is raised above the maximum number of voices within the horizon [P8]. Lifecycle code is minimal Kotlin/Swift or `audio_session` [P5].

| Stage | Where | Content | Evidence |
|---|---|---|---|
| C0 | Linux CI | `PlaybackScheduler` tests with fake `AudioClock`/`VoiceSink` (PLR-004 §9 adapter list: large time jump, generation cancel, start with a future anchor, pause/resume/stop, **pause and stop with pending hits and a drone**); adapter unit tests for handle tracking | `unit` |
| C1 | Android reference device (Pixel or Android One, API 27+) | PLR-012 scenario A (3:2, 5:4; 20/90/300 BPM; 2 and 4 layers; maximum density; drone; Pause → Start, Stop → Start; tempo change while playing), plus E (30 min). Speaker, wired, Bluetooth. With and without the UI stress toggle. | `device` |
| C2 | same | PLR-012 B (background/lock, foreground-only expected), C (interruption ×2), D (route changes and Bluetooth); stop tail per route | `device` |
| C3 | Current iPhone, through the signed install path (below) | C1 + C2 on iOS, plus media-services reset (Developer settings [I15]) | `device` |

Decision after phase 1:

- **B passes** every applicable gate (G2–G9) → engine B. A follow-up amends this record: the engine is `flutter_soloud`, and the A sections become the documented fallback. No C++ of our own is written.
- **B fails for engine reasons** that configuration cannot fix (latency, voice limit, cancel semantics, lifecycle control, maturity) → engine A, phase 2. The harness, fixtures, scheduler, adapters' lifecycle code and results are reused, and the C results become A's baseline.
- **Only G3 fails** → move the scheduler to the background isolate. That applies to any engine, and phase 1 re-runs C1.

**Phase 2, option A (only if chosen).**

| Stage | Where | Content | Evidence |
|---|---|---|---|
| S0 | Linux CI | C++ core tests with a fake device: exact onset frames, half-open windows, `cancelFrom` cutoff and purge in every engine state, sustain adoption and orphan release, late drop with no burst, ring overflow, the OpenSL ES path with no presentation timestamp (`outputTime` null); sanitizer job. Plus the C0 scheduler tests. | `unit` |
| S1–S2 | as C1–C2 | same scenarios with our engine; additionally, an Android 24–26 device if one is available, otherwise that path is reported as untested | `device` |
| S3 | as C3 | same | `device` |

**Signed iOS install path (C3/S3).** Today CI runs `flutter build ios --debug --no-codesign` ([ci.yml](../../.github/workflows/ci.yml)), which produces nothing installable. Before C3, a separate `REL` task sets up signed development builds:

- an Apple Developer account;
- the test iPhone registered in it, for development or ad hoc distribution [I17];
- either a Mac with Xcode, with automatic signing [I17] [F9], or a macOS CI job that imports the certificate and provisioning profile from GitHub secrets, never committed.

TestFlight [I18] is an alternative, but it distributes the app to testers, so it goes through the `release` gate. Until this path exists, the iOS stages are blocked and are reported as not run.

The full 4-device matrix (PLR-012 §3) belongs to the release gate, not to the spike.

### Go/no-go thresholds

All values are *hypotheses* for the Founder to accept or change (PLR-012 §5 for the physical ones). Report n, p50, p95 and max, as PLR-012 requires, never only "pass". The definitions are in [Latency and jitter measurement](#latency-and-jitter-measurement).

| # | Criterion | Go | Source |
|---|---|---|---|
| G1 | Engine exactness (A only; in B/C, G4 covers it physically) | 100 % of non-dropped events start at the planned frame (±1 frame) | engine log |
| G2 | Losses and doubles in stable foreground, 30 min | 0 `late`, 0 `overflow`, 0 rejected by a voice limit, 0 lost, 0 double; no growth in active voices | engine or adapter log + recording |
| G3 | Scheduler headroom, root isolate, with UI stress | minimum planned coverage ≥ `minLead` + 20 ms safety margin over the whole run; wake-up lateness p99 ≤ 20 ms, max ≤ 100 ms | scheduler log |
| G4 | Jitter, speaker/wired | p50 ≤ 2 ms, p95 ≤ 5 ms, max ≤ 20 ms | physical (PLR-012) |
| G5 | Drift over 30 min (1-minute windows) | p50 ≤ 2 ms, p95 ≤ 5 ms, max ≤ 10 ms; the clock rate is reported in ppm, separately | physical (PLR-012) |
| G6 | Output latency, speaker/wired | p50 ≤ 50 ms, p95 ≤ 80 ms, max ≤ 120 ms; Bluetooth reported, no limit | physical (PLR-012) |
| G7 | Generation | After a tempo or scene change, a pause or a stop: no older-generation start after the cutoff is applied (log). The software part of the stop tail is ≤ 1 callback period + 5 ms (A) or ≤ 30 ms (B/C). No audible retrigger of the drone on a tempo change (listening). The route part of the stop tail is reported per route. | log + recording + listening |
| G8 | Lifecycle | every row of the lifecycle table behaves as specified; no crash, no burst, no automatic resume, unambiguous transport state | PLR-012 B–D |
| G9 | Real-time headroom | audio callback duration p99 ≤ 50 % of the buffer period (A); for B/C, no xruns reported in 30 min; listening ≥ 4/5 from two listeners | log + listening |

What a failure leads to:

| Failed | Meaning | Next step |
|---|---|---|
| G1, G2, G7 in A | A bug in our engine, not in the architecture | Fix and re-run S0–S1 |
| G2, G7, G9 in C | `flutter_soloud`'s behaviour or our adapter | Fix the adapter or configuration; if the engine itself is the cause, choose A |
| G3 only | The root isolate is too busy | Move `PlaybackScheduler` to the background isolate (planned fallback), re-run |
| G4–G6 on Android | Device or stream configuration | Check that MMAP/exclusive was granted, the buffer size and the low-latency feature flag; if the device class cannot do better, document it as a `conditional pass` |
| G4–G6 on iOS | Buffer or engine overhead | A smaller preferred I/O buffer [I10]; in A, then the RemoteIO fallback |
| G8 | Policy or implementation | Fix; a policy change goes back to the Founder |

The result uses the PLR-012 classes: `pass`, `conditional pass` (for example foreground-only, or one route with a documented limitation) or `fail`. The worst required combination decides.

## Risks

| Risk | Mitigation |
|---|---|
| Root-isolate wake-ups are delayed by UI work, since Dart shares the platform main thread [F2] | 200 ms horizon, skip-late with no burst, G3 with a stress toggle, the background-isolate fallback |
| Android 24–26 runs on OpenSL ES, where Oboe's `getTimestamp`, `getFramesWritten` and `getFramesRead` are unimplemented [A6], and latency is higher | `renderTime` comes from our own callback frame counter. `outputTime` is null on that path, and the UI shows an approximate position from `fallbackOutputLatency`. S0 tests the path. Devices: tested if available, otherwise reported as untested. Raising `minSdk` to 27 is a Founder/`MOB` question. |
| Stale audio keeps sounding after a cancel for the route's output latency (long on Bluetooth and AirPlay [I11]) | Only the render cutoff is guaranteed. The stop tail is measured per route (G7) and never presented as a scheduler bound. |
| Exclusive streams disconnect more often [A2] | Reopen on a control thread [A2] [A6]; exclusive is requested, never required |
| AVAudioEngine stops on configuration changes [I6] | Restart on an internal queue outside the notification handler, with a timeline that continues (late events are dropped) |
| No signed iOS build exists (CI uses `--no-codesign`) | A separate `REL` task for the signed install path; iOS stages blocked and reported as not run until then |
| C++ real-time bugs (data races, allocation in the callback) are invisible to `flutter test` | See [Risks of our own C++ core](#risks-of-our-own-c-core) |
| Option C needs a Flutter upgrade (≥ 3.41) [P10] | A `MOB` task before the spike; the upgrade also brings build hooks for A ([Not now](#not-now-and-when-to-revisit)) |
| `playScheduled` is recent (added in 4.1.0; a fix for starting a voice one buffer early landed in 5.1.x) [P9] | That is exactly what phase 1 measures; pin the version |
| Interruption APIs are changing on iOS 27 [I13] | Observe the life-cycle notifications on 27+ and `interruptionNotification` below |
| Native dependencies: Oboe (Maven prefab [A7]) and the C++ toolchain (A); `flutter_soloud` (B/C) | Justified in the PR that adds them (`change-safety`) |
| The emulator says nothing about latency or Bluetooth | Never reported as evidence (`docs/testing.md`) |

## Alternatives rejected

| Alternative | Why not |
|---|---|
| Per-platform engines with no shared core (Kotlin `AudioTrack` + Swift `AVAudioSourceNode`) | Viable, but the real-time rules (generation cutoff, skip-late, adoption) would be written twice and kept identical, and the Swift half could be tested only in macOS CI ([Why native code, and why C++](#why-native-code-and-why-c)) |
| `AVAudioPlayerNode` scheduled buffers on iOS | Cannot cancel one event: `stop()` clears everything [I5] |
| Building A without phase 1 | Commits to roughly 3,000 lines of native code before any device number exists. It is faster only if phase 1 would certainly fail, which we do not know. |
| Platform channels for the hot path | Asynchronous and serialized [F1]; the clock reading is stale; handlers run on the platform main thread [F1] |
| Native-driven wake-up (the audio thread asks Dart for more events) | A callback from the audio thread into Dart violates the callback rules [A6] [F8]. A control-thread relay adds a moving part without beating a 25 ms timer plus a 200 ms horizon. |
| Frame counters as `AudioTime` | They restart with every stream; route changes would invalidate planned events |
| Host clock (`CLOCK_MONOTONIC`) as `AudioTime` during playback | Drifts against the device clock over a 30-minute session; the music should follow the output |
| Background playback in 1.0 | A foreground service with a notification, a background mode and review implications [A10] [I16] for a promise the product has not made. Kept as a Founder decision. |
| `package_ffi` with build hooks for A on Flutter 3.35 | Recommended from Flutter 3.38 [F3], but it has no Flutter plugin API for the Kotlin/Swift lifecycle code. Revisit after the Flutter upgrade. |

## Consequences

- Positive:
  - The ports, scheduler, lifecycle policy and measurement hold for every engine. Changing the engine does not touch the core or the scheduler.
  - Phase 1 gives device numbers before we write our own real-time C++, and its harness carries over to A.
  - In A, one C++ core carries every real-time rule, is tested on Linux CI and is shared by both platforms. Lifecycle safety does not depend on Dart: the native side silences first.
  - Measurement separates software exactness, the route's latency and tail, and what is heard.
- Negative:
  - Phase 1 needs a Flutter upgrade and a third-party dependency first.
  - If phase 1 fails, A costs C++, Kotlin and Swift code and a C++ CI job on top.
  - iOS device work is blocked until a signed install path exists.
  - Foreground-only means no playback with a locked screen in 1.0, unless the Founder decides otherwise.
- Changes to decision 0001, made in the implementation task after acceptance:
  - A: the layout gains `packages/synesterra_audio_engine/` (a local FFI plugin with the C++ core, the Android and iOS hosts and raw bindings). B: `flutter_soloud` is a plugin dependency of `lib/data/audio/` only. In both cases `android/` and `ios/` stay the generated runners plus app-level settings (manifest, `Info.plist`, keep-awake).
  - The architecture tests treat the engine package like a plugin: only `lib/data/audio/` imports it (R5, R7).
  - `docs/architecture.md` adds the engine box in the same PR that creates it. This record does not edit `0001` or `docs/architecture.md`.

## Not now, and when to revisit

| Deferred | Revisit when |
|---|---|
| Background/locked-screen playback | The Founder makes it a 1.0 promise |
| Mixing with other apps (practising along with a music app: `.mixWithOthers`, no exclusive focus) | Product asks for play-along; a settings option |
| Build hooks (`package_ffi`) for A | After the Flutter upgrade, if A is chosen |
| `NativeCallable.listener` for engine faults | Polling diagnostics on each tick turns out to be too slow to report faults |
| Raising Android `minSdk` to 27 | The spike shows the OpenSL ES path cannot meet the gates |

## Founder decisions

```markdown
Decision: accept the engine-agnostic contract in ADR 0002 (ports, scheduler, lifecycle,
measurement) and choose how to pick the engine.
Options:
  A  Own thin engine now: shared C++ core + Oboe + AVAudioEngine/AVAudioSourceNode,
     dart:ffi for clock/schedule/cancel, platform channels for lifecycle.
     + Full control: frame-exact logs, native-first silencing, our cancel and drone semantics.
     + No third-party engine on the riskiest path; core tested on Linux CI.
     - About 2,500-3,500 lines of native code plus tests before the first device number.
     - C++ real-time bugs are ours; the iOS loop is slow (macOS CI, signing).
  B  flutter_soloud as the engine, without a discovery phase.
     + Least code: sample-accurate playScheduled, engine and playhead clocks, a low-latency
       profile, and an app-owned AVAudioSession.
     - Needs Flutter >= 3.41. playScheduled is recent. The voice limit must be managed;
       cancel works through handles; silencing goes through Dart; no frame-exact logs.
     - Choosing it without measuring trusts it on the riskiest path.
  C  Discovery spike: flutter_soloud behind the same AudioClock/VoiceSink ports, measured
     with the PLR-012 protocol and gates G2-G9; then choose A or B with device numbers.
     + Device numbers in the shortest time; no C++ of ours unless the numbers demand it.
     + Harness, fixtures, scheduler, lifecycle code and QA results carry over to A or B.
     - Needs the Flutter upgrade first and a temporary or permanent dependency.
     - It measures SoLoud, not A. If it fails on latency, A's latency is still unknown,
       although the failure shows which gate A must beat.
     - Risk of keeping a "good enough" engine that fails rarely; the gates guard against it.
Recommendation: C, then A or B by the gates. A remains the target design if C fails
for engine reasons.
Evidence: this record (static; official documentation and the flutter_soloud source cited).
No device measurement yet.
Also to confirm:
  1. Background policy for 1.0: foreground-only plus screen kept awake (recommended), or background playback.
  2. Gate thresholds G1-G9 (hypotheses; physical ones from PLR-012).
  3. Android minSdk: keep 24 (OpenSL ES on 24-26, approximate position) or raise to 27.
  4. A REL task for the signed iOS install path (Apple Developer account, device registration).
  5. A MOB task for the Flutter upgrade to >= 3.41 (needed by C and B).
If undecided: the spike and all native audio code wait; DOM/UX work continues.
```

## Sources

Android (Android Developers and the Oboe project):

[A1]: https://developer.android.com/ndk/guides/audio
[A2]: https://developer.android.com/ndk/guides/audio/aaudio/aaudio
[A3]: https://developer.android.com/ndk/reference/group/audio
[A4]: https://developer.android.com/games/sdk/oboe/low-latency-audio
[A5]: https://github.com/google/oboe
[A6]: https://github.com/google/oboe/blob/main/docs/FullGuide.md
[A7]: https://github.com/google/oboe/blob/main/docs/GettingStarted.md
[A8]: https://developer.android.com/media/optimize/audio-focus
[A9]: https://developer.android.com/media/platform/output
[A10]: https://developer.android.com/develop/background-work/services/fgs/service-types
[A11]: https://developer.android.com/ndk/guides/audio/audio-latency
[A12]: https://developer.android.com/reference/android/media/AudioTrack
[A13]: https://developer.android.com/ndk/guides/asan
[A14]: https://developer.android.com/ndk/guides/cmake
[A15]: https://developer.android.com/studio/debug

- [A1] [High-performance audio](https://developer.android.com/ndk/guides/audio): Oboe recommended; OpenSL ES not for new designs; music-learning apps and drum machines are high-performance use cases.
- [A2] [AAudio](https://developer.android.com/ndk/guides/audio/aaudio/aaudio): performance and sharing modes, disconnection, error callback threading, burst and buffer size, xrun count.
- [A3] [AAudio reference](https://developer.android.com/ndk/reference/group/audio): `AAudioStream_getTimestamp` (API 26), clock id, frame position.
- [A4] [Low-latency audio with Oboe](https://developer.android.com/games/sdk/oboe/low-latency-audio): low-latency mode, exclusive/MMAP, native sample rate, double buffering, usage game and Bluetooth, AAudio on API 27+.
- [A5] [Oboe README](https://github.com/google/oboe): API 16+, OpenSL ES on 16+ or AAudio on 27+.
- [A6] [Oboe full guide](https://github.com/google/oboe/blob/main/docs/FullGuide.md): what the callback must not do, `getTimestamp` unimplemented on OpenSL ES, disconnect callbacks.
- [A7] [Oboe getting started](https://github.com/google/oboe/blob/main/docs/GettingStarted.md): prefab Maven dependency, CMake, shared STL.
- [A8] [Audio focus](https://developer.android.com/media/optimize/audio-focus): `AudioFocusRequest`, loss types, automatic ducking, enforcement from Android 12, the Android 15 restriction.
- [A9] [Audio output](https://developer.android.com/media/platform/output): `ACTION_AUDIO_BECOMING_NOISY`.
- [A10] [Foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types): `mediaPlayback`, the permission, types required since Android 14.
- [A11] [Audio latency](https://developer.android.com/ndk/guides/audio/audio-latency): definitions, loopback measurement, `low_latency` and `pro` feature flags.
- [A12] [AudioTrack](https://developer.android.com/reference/android/media/AudioTrack): `PERFORMANCE_MODE_LOW_LATENCY` (API 26) and its buffer-management note.
- [A13] [AddressSanitizer](https://developer.android.com/ndk/guides/asan): detects memory bugs in native code.
- [A14] [CMake](https://developer.android.com/ndk/guides/cmake): NDK builds through `externalNativeBuild`.
- [A15] [Debug your app](https://developer.android.com/studio/debug): "Dual (Java + Native)" debugging with LLDB.

Apple (Apple Developer Documentation):

[I1]: https://developer.apple.com/documentation/avfaudio/avaudioengine
[I2]: https://developer.apple.com/documentation/avfaudio/avaudiosourcenode
[I3]: https://developer.apple.com/documentation/avfaudio/avaudiosourcenoderenderblock
[I4]: https://developer.apple.com/documentation/avfaudio/avaudioplayernode
[I5]: https://developer.apple.com/documentation/avfaudio/avaudioplayernode/stop()
[I6]: https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/avaudioengineconfigurationchange
[I7]: https://developer.apple.com/documentation/avfaudio/avaudiotime
[I8]: https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playback
[I9]: https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/ambient
[I10]: https://developer.apple.com/documentation/avfaudio/avaudiosession/setpreferrediobufferduration(_:)
[I11]: https://developer.apple.com/documentation/avfaudio/avaudiosession/outputlatency
[I12]: https://developer.apple.com/documentation/avfaudio/avaudiosession/interruptionnotification
[I13]: https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions
[I14]: https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes
[I15]: https://developer.apple.com/documentation/avfaudio/avaudiosession/mediaserviceswereresetnotification
[I16]: https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes
[I17]: https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices
[I18]: https://developer.apple.com/testflight/

- [I1] [AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioengine): the node graph and real-time rendering to the device.
- [I2] [AVAudioSourceNode](https://developer.apple.com/documentation/avfaudio/avaudiosourcenode): supplies audio through a render block; iOS 13.0+.
- [I3] [AVAudioSourceNodeRenderBlock](https://developer.apple.com/documentation/avfaudio/avaudiosourcenoderenderblock): HAL timestamp, frame count.
- [I4] [AVAudioPlayerNode](https://developer.apple.com/documentation/avfaudio/avaudioplayernode): scheduling at sample time or host time; the player timeline.
- [I5] [AVAudioPlayerNode.stop()](https://developer.apple.com/documentation/avfaudio/avaudioplayernode/stop()): clears all scheduled events and resets sample time; stop the engine to save power.
- [I6] [AVAudioEngineConfigurationChange](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/avaudioengineconfigurationchange): the engine stops on a hardware rate or channel change.
- [I7] [AVAudioTime](https://developer.apple.com/documentation/avfaudio/avaudiotime): host time and sample time.
- [I8] [AVAudioSession.Category.playback](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playback): Silent switch, screen lock, the background mode, non-mixable by default.
- [I9] [AVAudioSession.Category.ambient](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/ambient): silenced by the switch and by lock.
- [I10] [setPreferredIOBufferDuration(_:)](https://developer.apple.com/documentation/avfaudio/avaudiosession/setpreferrediobufferduration(_:)): I/O buffer range.
- [I11] [outputLatency](https://developer.apple.com/documentation/avfaudio/avaudiosession/outputlatency): output latency; AirPlay delay.
- [I12] [interruptionNotification](https://developer.apple.com/documentation/avfaudio/avaudiosession/interruptionnotification): began/ended, main thread, deactivation on suspension since iOS 10.
- [I13] [Handling audio interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions): the iOS 27 life-cycle notifications and the legacy notification.
- [I14] [Responding to audio route changes](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes): pause on headphone removal, continue on connection.
- [I15] [mediaServicesWereResetNotification](https://developer.apple.com/documentation/avfaudio/avaudiosession/mediaserviceswereresetnotification): rebuild objects; no restart without user action.
- [I16] [UIBackgroundModes](https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes): background execution modes.
- [I17] [Distributing your app to registered devices](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices): device registration, automatic signing in Xcode, archive and export.
- [I18] [TestFlight](https://developer.apple.com/testflight/): beta builds uploaded to App Store Connect and shared with testers.

Flutter and Dart (official documentation):

[F1]: https://docs.flutter.dev/platform-integration/platform-channels
[F2]: https://docs.flutter.dev/resources/architectural-overview
[F3]: https://docs.flutter.dev/platform-integration/android/c-interop
[F4]: https://docs.flutter.dev/platform-integration/ios/c-interop
[F5]: https://docs.flutter.dev/perf/isolates
[F6]: https://api.dart.dev/dart-ffi/NativeCallable/NativeCallable.listener.html
[F7]: https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html
[F8]: https://api.dart.dev/dart-ffi/NativeCallable/NativeCallable.isolateLocal.html
[F9]: https://docs.flutter.dev/deployment/ios

- [F1] [Platform channels](https://docs.flutter.dev/platform-integration/platform-channels): asynchronous messages, the main thread, the Task Queue API, background isolates, `StandardMessageCodec`.
- [F2] [Architectural overview](https://docs.flutter.dev/resources/architectural-overview): UI and platform threads merged on Android and iOS since 3.29; FFI faster than channels.
- [F3] [Android C interop](https://docs.flutter.dev/platform-integration/android/c-interop): `plugin_ffi`, dynamic `.so` only, `package_ffi` + build hooks recommended since 3.38.
- [F4] [iOS C interop](https://docs.flutter.dev/platform-integration/ios/c-interop): static linking and `DynamicLibrary.process`, `@_cdecl`, when the legacy template is still useful.
- [F5] [Isolates](https://docs.flutter.dev/perf/isolates): long-lived isolates, message copying, background isolate platform channels.
- [F6] [NativeCallable.listener](https://api.dart.dev/dart-ffi/NativeCallable/NativeCallable.listener.html): callable from any thread, asynchronous, `void` only.
- [F7] [AppLifecycleState](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html): `inactive`, `hidden`, `paused` on iOS and Android.
- [F8] [NativeCallable.isolateLocal](https://api.dart.dev/dart-ffi/NativeCallable/NativeCallable.isolateLocal.html): invocable only on the isolate's own thread; aborts the process otherwise.
- [F9] [Build and release an iOS app](https://docs.flutter.dev/deployment/ios): "Automatically manage signing" in Xcode.

Flutter plugins (pub.dev and the plugin's repository, read 2026-10-02):

[P1]: https://pub.dev/packages/just_audio
[P2]: https://pub.dev/packages/audioplayers
[P3]: https://pub.dev/packages/flutter_soloud
[P4]: https://pub.dev/documentation/flutter_soloud/latest/flutter_soloud/SoLoud/playScheduled.html
[P5]: https://pub.dev/packages/audio_session
[P6]: https://pub.dev/documentation/flutter_soloud/latest/flutter_soloud/SoLoud/init.html
[P7]: https://github.com/alnitak/flutter_soloud/blob/13fb0a8/src/soloud/src/backend/miniaudio/soloud_miniaudio.cpp
[P8]: https://pub.dev/documentation/flutter_soloud/latest/flutter_soloud/SoLoud/play.html
[P9]: https://pub.dev/packages/flutter_soloud/changelog
[P10]: https://pub.dev/packages/flutter_soloud/versions

- [P1] [just_audio](https://pub.dev/packages/just_audio) · [P2] [audioplayers](https://pub.dev/packages/audioplayers) · [P3] [flutter_soloud](https://pub.dev/packages/flutter_soloud) · [P4] [SoLoud.playScheduled](https://pub.dev/documentation/flutter_soloud/latest/flutter_soloud/SoLoud/playScheduled.html) · [P5] [audio_session](https://pub.dev/packages/audio_session)
- [P6] [SoLoud.init](https://pub.dev/documentation/flutter_soloud/latest/flutter_soloud/SoLoud/init.html): `lowLatency` (AAudio MMAP on Android), `bufferSize` default 2048, render-ahead ring.
- [P7] [soloud_miniaudio.cpp at 13fb0a8](https://github.com/alnitak/flutter_soloud/blob/13fb0a8/src/soloud/src/backend/miniaudio/soloud_miniaudio.cpp) (source code, not documentation): the iOS context sets no session category and does not activate or deactivate the session.
- [P8] [SoLoud.play](https://pub.dev/documentation/flutter_soloud/latest/flutter_soloud/SoLoud/play.html): the 16-voice default and what happens at the limit.
- [P9] [flutter_soloud changelog](https://pub.dev/packages/flutter_soloud/changelog): `playScheduled` added in 4.1.0; breaking changes in 5.0; a scheduling fix in 5.1.x.
- [P10] [flutter_soloud versions](https://pub.dev/packages/flutter_soloud/versions): SDK constraints (Flutter ≥ 3.41, Dart ≥ 3.11 from 4.0.0).

Web laboratory (read-only, `synesterra-web`, not part of this repository): PLR-004 §4–5, PLR-005, PLR-012 and its deliverable `docs/quality/MOBILE_AUDIO_QA.md`.
