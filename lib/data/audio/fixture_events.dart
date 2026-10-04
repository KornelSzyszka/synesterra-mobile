import 'dart:convert';

import 'playback_scheduler.dart';

/// Repeats the committed C0 event list every four quarter notes.
final class FixtureEvents implements BeatEventSource {
  FixtureEvents(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    _scenes = {
      for (final entry in decoded.entries)
        entry.key: [
          for (final raw in entry.value as List<dynamic>)
            (
              beat: (raw as Map<String, dynamic>)['beat'] as int,
              eventId: raw['eventId'] as int,
              sound: raw['sound'] as String,
            ),
        ],
    };
  }

  static const cycleTicks = 3840;
  late final Map<String, List<({int beat, int eventId, String sound})>> _scenes;
  String scene = '3:2';
  int layers = 2;

  @override
  List<PlannedVoiceEvent> plan(int fromBeat, int toBeat) {
    final planned = <PlannedVoiceEvent>[];
    final firstCycle = fromBeat ~/ cycleTicks;
    final lastCycle = (toBeat - 1) ~/ cycleTicks;
    for (var cycle = firstCycle; cycle <= lastCycle; cycle++) {
      for (var layer = 0; layer < layers; layer++) {
        for (final item in _scenes[scene]!) {
          final beat = cycle * cycleTicks + item.beat;
          if (beat < fromBeat || beat >= toBeat) continue;
          planned.add(
            PlannedVoiceEvent(
              beat: beat,
              eventId: cycle * 1000 + layer * 100 + item.eventId,
              kind: PlannedVoiceKind.trigger,
              sound: item.sound,
              gain: 0.45 / layers,
              pan: layer.isEven ? -0.3 : 0.3,
            ),
          );
        }
      }
    }
    planned.sort((a, b) => a.beat.compareTo(b.beat));
    return planned;
  }
}
