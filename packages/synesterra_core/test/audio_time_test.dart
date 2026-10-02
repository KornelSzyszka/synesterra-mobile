import 'package:synesterra_core/src/playback/audio_time.dart';
import 'package:synesterra_core/src/playback/tempo_map.dart';
import 'package:synesterra_core/src/ports/voice_sink.dart';
import 'package:test/test.dart';

void main() {
  test('audio time is a non-negative engine timeline point', () {
    expect(() => AudioTime(-1), throwsArgumentError);
    expect(
      AudioTime(2000) - AudioTime(500),
      const Duration(microseconds: 1500),
    );
    expect(
      AudioTime(500) + const Duration(microseconds: 1500),
      AudioTime(2000),
    );
    expect(AudioTime(500).compareTo(AudioTime(2000)), lessThan(0));
  });

  test('constant tempo converts integer ticks around an anchor', () {
    final map = TempoMap(
      bpm: 120,
      anchorBeat: 960,
      anchorTime: AudioTime(1000000),
    );
    expect(ticksPerQuarter, 960);
    expect(map.audioTimeOf(1920), AudioTime(1500000));
    expect(map.beatAt(AudioTime(1500000)), 1920);
    expect(map.beatAt(AudioTime(999999)), 959);
    expect(map.beatAt(AudioTime(0)), 0);
    expect(() => map.audioTimeOf(-1), throwsArgumentError);
    expect(
      () => TempoMap(bpm: 0, anchorBeat: 0, anchorTime: AudioTime(0)),
      throwsArgumentError,
    );
  });

  test('voice events reject missing sound or sustain key', () {
    expect(
      () => Trigger(at: AudioTime(0), eventId: 1, sound: '', gain: 1, pan: 0),
      throwsArgumentError,
    );
    expect(
      () => SustainOn(
        at: AudioTime(0),
        eventId: 1,
        key: '',
        sound: 'drone',
        gain: 1,
        pan: 0,
      ),
      throwsArgumentError,
    );
  });
}
