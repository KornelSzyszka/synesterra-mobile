/// Pure Dart building blocks for Synesterra.
library;

export 'src/core_identity.dart';
export 'src/rhythm/rhythm_values.dart'
    show
        Rational,
        PatternStep,
        Pattern,
        Swing,
        LayerMix,
        RhythmLayer,
        minLayerPitch,
        maxLayerPitch;
export 'src/arrangement/arrangement.dart';
export 'src/harmony/drone.dart';
export 'src/sound/instrument.dart';
export 'src/sound/instrument_envelope.dart';
export 'src/sound/instrument_renderer.dart';
export 'src/sound/instrument_response.dart';
export 'src/sound/instrument_traits.dart';
export 'src/session/session_document.dart';
export 'src/session/session_migration.dart';
export 'src/session/session_parser.dart';
export 'src/session/session_project.dart';
export 'src/randomizer/seeded_random.dart'
    show SeededRandom, maxRandomSeed, checkRandomSeed;
export 'src/randomizer/loop_randomizer.dart';
export 'src/training/tap_training.dart';
export 'src/training/ear_training.dart';
export 'src/randomizer/arrangement_randomizer.dart';
export 'src/randomizer/instrument_randomizer.dart';
export 'src/rhythm/tap_tempo.dart';
export 'src/playback/audio_time.dart';
export 'src/playback/tempo_map.dart';
export 'src/playback/event_planner.dart';
export 'src/ports/audio_clock.dart';
export 'src/ports/voice_sink.dart';
