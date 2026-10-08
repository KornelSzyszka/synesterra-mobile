import '../../data/repositories/loop.dart';
import '../../shared/loop_view/loop_view.dart';

/// A word a lesson uses that a beginner may not know, with a one-line
/// explanation.
class LearnTerm {
  const LearnTerm(this.term, this.meaning);

  final String term;
  final String meaning;
}

/// One short lesson. The content is data; English only (localization is
/// issue #25).
class LearnLesson {
  const LearnLesson({
    required this.id,
    required this.title,
    required this.teaser,
    required this.sentences,
    this.terms = const [],
    this.loop,
    this.sections = const [],
    this.viewMode = LoopViewMode.circle,
  });

  final String id;
  final String title;

  /// One line for the list.
  final String teaser;

  /// 2-4 plain sentences, shown as one paragraph.
  final List<String> sentences;

  /// Jargon used in [sentences], each with a one-line explanation.
  final List<LearnTerm> terms;

  /// The built-in loop the lesson draws, plays and "Try it" opens. Null for a
  /// lesson that draws [sections] instead, which then has no sound or "Try it".
  final Loop? loop;

  /// The sections of a small arrangement the lesson draws as a strip, when it
  /// has no [loop]. A lesson has a [loop] or [sections], never neither.
  final List<StripSection> sections;

  /// The view the picture opens in; the learner can switch.
  final LoopViewMode viewMode;

  String get text => sentences.join(' ');
}

Loop _lessonLoop(
  String id,
  String name, {
  required num bpm,
  required int cycleBeats,
  required List<LoopLayerSpec> layers,
}) => Loop(
  id: id,
  name: name,
  document: simpleLoopDocument(
    title: name,
    bpm: bpm,
    cycleBeats: cycleBeats,
    layers: layers,
  ),
);

Loop _factory(String id) => factoryLoops.firstWhere((loop) => loop.id == id);

const _layerTerm = LearnTerm(
  'Layer',
  'One row of hits that repeats every cycle.',
);

/// The seven lessons of prototype v0, in order.
final List<LearnLesson> learnLessons = List.unmodifiable([
  LearnLesson(
    id: 'pulse-and-cycle',
    title: 'Pulse and cycle',
    teaser: 'The steady beat and the loop it repeats in.',
    sentences: const [
      'A pulse is one steady beat, like a tick of a clock.',
      'A cycle is a fixed number of pulses that then start again.',
      'In the picture the line sweeps once around the circle in one cycle.',
      'Layer 1 hits on every pulse and layer 2 only on the first.',
    ],
    terms: const [_layerTerm],
    loop: _lessonLoop(
      'lesson-pulse-and-cycle',
      'Pulse and cycle',
      bpm: 60,
      cycleBeats: 4,
      layers: const [
        LoopLayerSpec(instrumentId: 'factory-wood', pitch: 69, hits: 4),
        LoopLayerSpec(instrumentId: 'factory-bell', pitch: 76, hits: 1),
      ],
    ),
  ),
  LearnLesson(
    id: 'two-against-three',
    title: 'Two against three (3:2)',
    teaser: 'Two layers that split one cycle in different ways.',
    sentences: const [
      'Two layers can share one cycle and still divide it differently.',
      'Here one layer hits 3 times and the other hits 2 times in the same cycle.',
      'Musicians write this as 3:2 and call it a polyrhythm.',
      'The hits meet only at the start, so the pattern seems to roll.',
    ],
    terms: const [
      LearnTerm(
        'Polyrhythm',
        'Two or more rhythms that split the same time in different ways.',
      ),
      _layerTerm,
    ],
    loop: _factory('factory-loop-3-2'),
  ),
  LearnLesson(
    id: 'four-against-five',
    title: 'Four against five (5:4)',
    teaser: 'A slower, wider roll than 3:2.',
    sentences: const [
      'In 5:4 one layer hits 5 times and the other hits 4 times in a cycle.',
      'Watch the shapes in the Polygons view: a pentagon and a square.',
      'The two layers line up only at the start of each cycle.',
    ],
    terms: const [
      LearnTerm(
        'Polygon',
        'A flat shape with straight sides, such as a square or a pentagon.',
      ),
      _layerTerm,
    ],
    loop: _factory('factory-loop-5-4'),
    viewMode: LoopViewMode.polygons,
  ),
  LearnLesson(
    id: 'layers-and-instruments',
    title: 'Layers and instruments',
    teaser: 'Up to four layers, each with its own sound.',
    sentences: const [
      'A loop is built from two to four layers.',
      'Each layer has an instrument, a pitch and a pattern of hits.',
      'The pitch is how high or low the sound is.',
      'A number and a colour tell the layers apart in the picture.',
    ],
    terms: const [
      LearnTerm('Pitch', 'How high or low a sound is.'),
      _layerTerm,
    ],
    loop: _factory('factory-loop-4-3-2'),
  ),
  LearnLesson(
    id: 'shaping-a-sound',
    title: 'Shaping a sound',
    teaser: 'One dot on the pad changes how an instrument sounds.',
    sentences: [
      'You shape an instrument by placing one dot on the pad.',
      'Left is dark and right is bright.',
      'Top is soft and airy, and bottom is hard and sharp.',
      'Open the Instrument panel in the Editor and drag the dot to hear it.',
    ],
    terms: const [
      LearnTerm('Instrument', 'A sound you can play, such as wood or bell.'),
    ],
    // The picture shows three different sounds playing together.
    loop: _lessonLoop(
      'lesson-shaping-a-sound',
      'Three sounds',
      bpm: 70,
      cycleBeats: 4,
      layers: const [
        LoopLayerSpec(instrumentId: 'factory-wood', pitch: 57, hits: 4),
        LoopLayerSpec(instrumentId: 'factory-sine', pitch: 69, hits: 3),
        LoopLayerSpec(instrumentId: 'factory-bell', pitch: 81, hits: 2),
      ],
    ),
  ),
  LearnLesson(
    id: 'building-and-saving-a-loop',
    title: 'Building and saving a loop',
    teaser: 'Pick layers, set the hits, then keep it.',
    sentences: const [
      'In the Loop panel you add layers and choose an instrument for each.',
      'Tap the steps to switch hits on and off, and set the tempo.',
      'Press Save to keep the loop in your Library.',
      'Try it opens a copy of this loop that you can change.',
    ],
    terms: const [
      LearnTerm('Tempo', 'How fast the beat goes, in beats per minute (BPM).'),
      _layerTerm,
    ],
    loop: _lessonLoop(
      'lesson-building-a-loop',
      'My first loop',
      bpm: 80,
      cycleBeats: 4,
      layers: const [
        LoopLayerSpec(instrumentId: 'factory-wood', pitch: 69, hits: 4),
        LoopLayerSpec(instrumentId: 'factory-bell', pitch: 76, hits: 2),
      ],
    ),
  ),
  LearnLesson(
    id: 'chaining-loops',
    title: 'Chaining loops',
    teaser: 'Play your loops one after another.',
    sentences: [
      'An arrangement plays saved loops one after another.',
      'Each part says which loop to play and how many cycles to repeat it.',
      'Open the Arrangement panel in the Editor to chain your loops.',
    ],
    terms: [
      LearnTerm(
        'Arrangement',
        'A list of loops played in order, like the parts of a song.',
      ),
    ],
    sections: [
      StripSection(label: 'Loop A', repeats: 2),
      StripSection(label: 'Loop B', repeats: 2),
      StripSection(label: 'Loop C', repeats: 1),
    ],
  ),
]);
