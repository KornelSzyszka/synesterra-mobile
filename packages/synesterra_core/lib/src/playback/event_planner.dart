import '../rhythm/rhythm_values.dart';
import '../session/session_project.dart';
import 'tempo_map.dart';

/// One rhythm trigger, before audio gain staging or timestamp conversion.
final class PlannedRhythmEvent {
  const PlannedRhythmEvent({
    required this.beat,
    required this.eventId,
    required this.layerId,
    required this.layerIndex,
    required this.stepIndex,
    required this.cycleIndex,
    required this.instrumentId,
    required this.pitch,
    required this.velocity,
    required this.accent,
    required this.layerGain,
    required this.masterGain,
    required this.pan,
  });

  final int beat;
  final int eventId;
  final String layerId;
  final int layerIndex;
  final int stepIndex;
  final int cycleIndex;
  final String instrumentId;

  /// MIDI note number of the layer.
  final int pitch;
  final num velocity;
  final bool accent;
  final num layerGain;
  final num masterGain;
  final num pan;
}

/// Expands only the requested absolute tick window of a resolved scene.
final class EventPlanner {
  const EventPlanner(this.project);

  final SessionProject project;

  List<PlannedRhythmEvent> plan(int fromBeat, int toBeat) {
    if (fromBeat < 0 || toBeat < fromBeat) {
      throw RangeError('Expected 0 <= fromBeat <= toBeat');
    }
    if (fromBeat == toBeat) return const [];

    final layers = project.layers;
    final anySolo = layers.any((layer) => layer.mix.solo && !layer.mix.muted);
    final events = <PlannedRhythmEvent>[];
    for (var layerIndex = 0; layerIndex < layers.length; layerIndex++) {
      final layer = layers[layerIndex];
      if (layer.mix.muted || anySolo && !layer.mix.solo) continue;
      final period = _Fraction(
        BigInt.from(layer.pattern.durationBeats.numerator * ticksPerQuarter),
        BigInt.from(layer.pattern.durationBeats.denominator),
      );
      final firstCycle = _max(
        0,
        (_Fraction.integer(fromBeat) / period).floor().toInt() - 1,
      );
      final lastCycle = (_Fraction.integer(toBeat) / period).ceil().toInt();
      final stepCount = layer.pattern.steps.length;
      final phase =
          period *
          _Fraction.integer(layer.phaseSteps) /
          _Fraction.integer(stepCount);
      for (var cycle = firstCycle; cycle <= lastCycle; cycle++) {
        for (var stepIndex = 0; stepIndex < stepCount; stepIndex++) {
          final step = layer.pattern.steps[stepIndex];
          if (!step.enabled || step.probability == 0) continue;
          var local =
              period *
              _Fraction.integer(stepIndex) /
              _Fraction.integer(stepCount);
          local += _swingOffset(layer, local);
          local = (local + phase).mod(period);
          final beat = (_Fraction.integer(cycle) * period + local)
              .roundHalfUp()
              .toInt();
          if (beat < fromBeat || beat >= toBeat) continue;
          if (!_passesProbability(
            project.randomSeed,
            layerIndex,
            stepIndex,
            cycle,
            step.probability,
          )) {
            continue;
          }
          events.add(
            PlannedRhythmEvent(
              beat: beat,
              eventId: ((cycle * 32 + stepIndex) * 4 + layerIndex),
              layerId: layer.id,
              layerIndex: layerIndex,
              stepIndex: stepIndex,
              cycleIndex: cycle,
              instrumentId: layer.instrumentId,
              pitch: layer.pitch,
              velocity: step.velocity,
              accent: step.accent,
              layerGain: layer.mix.gain,
              masterGain: project.masterGain,
              pan: layer.mix.pan,
            ),
          );
        }
      }
    }
    events.sort((a, b) {
      final beatOrder = a.beat.compareTo(b.beat);
      if (beatOrder != 0) return beatOrder;
      final layerOrder = a.layerIndex.compareTo(b.layerIndex);
      return layerOrder != 0 ? layerOrder : a.stepIndex.compareTo(b.stepIndex);
    });
    return List.unmodifiable(events);
  }
}

_Fraction _swingOffset(RhythmLayer layer, _Fraction local) {
  if (layer.swing.grid == 'off' || layer.swing.amount == 0) {
    return _Fraction.integer(0);
  }
  final grid = layer.swing.grid == 'eighth' ? 480 : 240;
  final gridPoint = (local / _Fraction.integer(grid)).floor();
  if (!gridPoint.isOdd) return _Fraction.integer(0);
  return _Fraction.fromDecimal(layer.swing.amount.toString()) *
      _Fraction.integer(grid) /
      _Fraction.integer(2);
}

bool _passesProbability(
  int seed,
  int layerIndex,
  int stepIndex,
  int cycleIndex,
  num probability,
) {
  if (probability == 1) return true;
  var hash = seed & 0xffffffff;
  for (final coordinate in [layerIndex, stepIndex, cycleIndex]) {
    hash = _multiply32(hash ^ (coordinate & 0xffffffff), 0x01000193);
  }
  return hash / 0x100000000 < probability;
}

int _multiply32(int a, int b) {
  final low = (a & 0xffff) * (b & 0xffff);
  final cross = ((a >> 16) * (b & 0xffff) + (a & 0xffff) * (b >> 16)) & 0xffff;
  return (low + (cross << 16)) & 0xffffffff;
}

int _max(int a, int b) => a >= b ? a : b;

/// Exact positive rational arithmetic for positions before the single tick rounding.
final class _Fraction {
  _Fraction(this.numerator, this.denominator)
    : assert(denominator > BigInt.zero);

  factory _Fraction.integer(int value) =>
      _Fraction(BigInt.from(value), BigInt.one);

  factory _Fraction.fromDecimal(String value) {
    final parts = value.toLowerCase().split('e');
    final mantissa = parts[0];
    final exponent = parts.length == 2 ? int.parse(parts[1]) : 0;
    final dot = mantissa.indexOf('.');
    final digits = mantissa.replaceAll('.', '');
    final fractionalDigits = dot < 0 ? 0 : mantissa.length - dot - 1;
    final scale = fractionalDigits - exponent;
    return scale >= 0
        ? _Fraction(BigInt.parse(digits), BigInt.from(10).pow(scale))
        : _Fraction(
            BigInt.parse(digits) * BigInt.from(10).pow(-scale),
            BigInt.one,
          );
  }

  final BigInt numerator;
  final BigInt denominator;

  _Fraction operator +(_Fraction other) => _Fraction(
    numerator * other.denominator + other.numerator * denominator,
    denominator * other.denominator,
  );
  _Fraction operator *(_Fraction other) =>
      _Fraction(numerator * other.numerator, denominator * other.denominator);
  _Fraction operator /(_Fraction other) =>
      _Fraction(numerator * other.denominator, denominator * other.numerator);
  BigInt floor() => numerator ~/ denominator;
  BigInt ceil() => (numerator + denominator - BigInt.one) ~/ denominator;
  BigInt roundHalfUp() =>
      (numerator * BigInt.two + denominator) ~/ (denominator * BigInt.two);
  _Fraction mod(_Fraction period) {
    final quotient = (this / period).floor();
    return _Fraction(
      numerator * period.denominator -
          quotient * period.numerator * denominator,
      denominator * period.denominator,
    );
  }
}
