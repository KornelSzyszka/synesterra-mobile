# Rhythm feature skeleton

The app composition root creates one in-memory `RhythmSettingsRepository` and injects it into `RhythmViewModel`. The view model reads a snapshot, handles control commands, saves replacements and notifies the view. `RhythmView` renders the immutable snapshot and forwards gestures; it has no repository or platform dependency.

The repository owns four fixed layer slots, each with an enable flag and 1–16 beats per cycle, plus a tempo of 20–300 BPM. Settings reset on app restart. These are temporary app-level types; mapping to `SessionProject` follows the rhythm domain task. There is no transport or audio playback.

Run `flutter run -d <android-emulator-id>`, toggle a layer and move the tempo and beat sliders. The labels should update immediately. Restarting the app restores the initial settings.
