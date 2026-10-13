import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/loop.dart';
import 'package:synesterra/features/learn/learn_lessons.dart';
import 'package:synesterra/shared/loop_view/loop_view_state.dart';

void main() {
  test('there are the seven v0 lessons, in order, with unique ids', () {
    expect(learnLessons.map((lesson) => lesson.title), [
      'Pulse and cycle',
      'Two against three (3:2)',
      'Four against five (5:4)',
      'Layers and instruments',
      'Shaping a sound',
      'Building and saving a loop',
      'Chaining loops',
    ]);
    expect(learnLessons.map((l) => l.id).toSet(), hasLength(7));
  });

  test('each lesson has 2-4 one-line sentences and a one-line teaser', () {
    for (final lesson in learnLessons) {
      expect(
        lesson.sentences.length,
        inInclusiveRange(2, 4),
        reason: lesson.id,
      );
      for (final sentence in lesson.sentences) {
        expect(sentence, endsWith('.'), reason: lesson.id);
        expect(
          sentence.substring(0, sentence.length - 1),
          isNot(contains('. ')),
          reason: lesson.id,
        );
      }
      expect(lesson.teaser, isNot(contains('\n')));
    }
  });

  test('jargon in a lesson comes with a one-line explanation', () {
    const jargon = [
      'polyrhythm',
      'polygon',
      'pitch',
      'tempo',
      'arrangement',
      'layer',
      'envelope',
      'bpm',
    ];
    for (final lesson in learnLessons) {
      final text = lesson.text.toLowerCase();
      final defined = lesson.terms.map((t) => t.term.toLowerCase()).toSet();
      for (final word in jargon) {
        if (RegExp('\\b$word').hasMatch(text)) {
          expect(defined, contains(word), reason: '${lesson.id}: $word');
        }
      }
      for (final term in lesson.terms) {
        expect(term.meaning, isNot(contains('\n')));
        expect(term.meaning.length, lessThan(100));
      }
    }
  });

  test('every lesson loop is a valid loop that survives the real parser', () {
    final withLoop = learnLessons.where((l) => l.loop != null).toList();
    expect(withLoop, hasLength(6));
    for (final lesson in withLoop) {
      final loop = lesson.loop!;
      final parsed = Loop.fromJson(jsonDecode(jsonEncode(loop.toJson())));
      expect(parsed, loop, reason: lesson.id);
      expect(
        LoopViewState.fromDocument(loop.document).layers.length,
        inInclusiveRange(2, 4),
      );
    }
  });

  test('the lessons show the loops they name', () {
    List<int> hits(String id) =>
        learnLessons.firstWhere((l) => l.id == id).loop!.hitsPerLayer;
    expect(hits('two-against-three'), [3, 2]);
    expect(hits('four-against-five'), [5, 4]);
    expect(hits('layers-and-instruments'), hasLength(3));
  });

  test('every lesson has a picture: a loop or arrangement sections', () {
    for (final lesson in learnLessons) {
      expect(
        lesson.loop != null || lesson.sections.isNotEmpty,
        isTrue,
        reason: lesson.id,
      );
    }
    final chaining = learnLessons.firstWhere((l) => l.id == 'chaining-loops');
    expect(chaining.loop, isNull);
    expect(chaining.sections.length, inInclusiveRange(2, 3));
  });

  test('the shaping lesson explains the radar in plain words, not the old '
      'pad', () {
    final lesson = learnLessons.firstWhere((l) => l.id == 'shaping-a-sound');
    final text = [lesson.teaser, ...lesson.sentences].join(' ');
    final words = RegExp(r'[a-z]+')
        .allMatches(text.toLowerCase())
        .map((m) => m.group(0));
    expect(words, isNot(contains('pad')));
    expect(words, isNot(contains('dot')));
    expect(text, contains('shape'));
    expect(text, contains('out for more'));
    expect(text, contains('in for less'));
    for (final trait in const ['bright', 'full', 'soft', 'long']) {
      expect(text.toLowerCase(), contains(trait), reason: trait);
    }
    for (final technical in const ['harmonic', 'attack', 'decay', 'eq']) {
      expect(words, isNot(contains(technical)), reason: technical);
    }
  });

  test(
    'the shaping lesson loop uses three different instruments and pitches',
    () {
      final loop = learnLessons
          .firstWhere((l) => l.id == 'shaping-a-sound')
          .loop!;
      final layers = loop.document.scenes.first.layers;
      expect(layers.map((l) => l.instrumentId).toSet(), hasLength(3));
      expect(layers.map((l) => l.pitch).toSet(), hasLength(3));
    },
  );
}
