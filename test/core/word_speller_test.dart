import 'package:flutter_test/flutter_test.dart';
import 'package:dictation_app/core/spelling/word_speller.dart';

void main() {
  const speller = WordSpeller(minLetterThreshold: 7);

  group('WordSpeller Difficult Word Detection', () {
    test('detects words meeting length threshold and strips punctuation', () {
      const text = 'Mitochondria are membrane-bound cell organelles producing ATP.';
      final difficult = speller.findDifficultWords(text);

      expect(difficult, contains('Mitochondria'));
      expect(difficult, contains('membrane'));
      expect(difficult, contains('organelles'));
      expect(difficult, contains('producing'));
      // Short words should not be detected
      expect(difficult, isNot(contains('cell')));
      expect(difficult, isNot(contains('are')));
      expect(difficult, isNot(contains('ATP')));
    });

    test('deduplicates case-insensitive duplicate words in the same phrase', () {
      const text = 'Respiration and respiration are chemical processes.';
      final difficult = speller.findDifficultWords(text);
      expect(difficult.where((w) => w.toLowerCase() == 'respiration').length, 1);
    });

    test('handles empty or short text safely', () {
      expect(speller.findDifficultWords(''), isEmpty);
      expect(speller.findDifficultWords('a an the is'), isEmpty);
    });
  });

  group('WordSpeller Spelling Formatting', () {
    test('formats English spelling with comma separated letters for clear TTS', () {
      final speech = speller.formatSpellingForSpeech('Mitochondria');
      expect(speech, 'M, I, T, O, C, H, O, N, D, R, I, A.');
    });

    test('formats English spelling with dots for catchy UI display', () {
      final display = speller.formatSpellingForDisplay('ATP');
      expect(display, 'A · T · P');

      final displayLong = speller.formatSpellingForDisplay('Cell');
      expect(displayLong, 'C · E · L · L');
    });

    test('builds enriched spoken text with difficult word spelling', () {
      const phrase = 'Mitochondria produce cellular energy';
      final enriched = speller.buildSpokenTextWithSpelling(phrase);

      expect(enriched, contains('Mitochondria'));
      expect(enriched, contains('Spelled: M, I, T, O, C, H, O, N, D, R, I, A.'));
    });
  });
}
