import 'package:flutter_test/flutter_test.dart';
import 'package:dictation_app/core/spelling/word_speller.dart';

void main() {
  const defaultSpeller = WordSpeller(); // default threshold: 10

  group('WordSpeller Difficult Word Detection (Threshold = 10)', () {
    test('detects words meeting default threshold (>=10 letters) and excludes shorter words', () {
      const text = 'Mitochondria are membrane-bound cell organelles producing ATP.';
      final difficult = defaultSpeller.findDifficultWords(text);

      expect(difficult, contains('Mitochondria')); // 12 letters
      expect(difficult, contains('organelles')); // 10 letters
      // Words with < 10 letters should not be detected
      expect(difficult, isNot(contains('membrane'))); // 8 letters
      expect(difficult, isNot(contains('producing'))); // 9 letters
      expect(difficult, isNot(contains('cell'))); // 4 letters
      expect(difficult, isNot(contains('ATP')));
    });

    test('deduplicates case-insensitive duplicate words in the same phrase', () {
      const text = 'Photosynthesis and PHOTOSYNTHESIS are biological concepts.';
      final difficult = defaultSpeller.findDifficultWords(text);
      expect(difficult.where((w) => w.toLowerCase() == 'photosynthesis').length, 1);
    });

    test('handles empty or short text safely', () {
      expect(defaultSpeller.findDifficultWords(''), isEmpty);
      expect(defaultSpeller.findDifficultWords('a an the is producing membrane'), isEmpty);
    });

    test('excludes long numeric tokens like phone numbers from difficult words', () {
      const text = 'Call 9880123456 or 123456789012 for support.';
      final difficult = defaultSpeller.findDifficultWords(text);
      expect(difficult, isEmpty);
    });
  });

  group('WordSpeller Pedagogical Syllable Spelling Formatting', () {
    test('chunks "Mitochondria" into "M I T O mito" and "C H O N D R I A mitochondria"', () {
      final speech = defaultSpeller.formatSpellingForSpeech('Mitochondria');
      expect(speech, 'M, I, T, O. mito. C, H, O, N, D, R, I, A. mitochondria.');
    });

    test('formats English chunked display with syllable dots and phonetic hints for UI', () {
      final display = defaultSpeller.formatSpellingForDisplay('Mitochondria');
      expect(display, contains('M · I · T · O (mito)'));
      expect(display, contains('C · H · O · N · D · R · I · A (mitochondria)'));
    });

    test('builds enriched spoken text with pedagogical spelling right after difficult word', () {
      const phrase = 'Mitochondria are powerful cell organelles.';
      final enriched = defaultSpeller.buildSpokenTextWithSpelling(phrase);

      // Verify spelling follows immediately after Mitochondria
      expect(
        enriched,
        contains('Mitochondria, spelled: M, I, T, O. mito. C, H, O, N, D, R, I, A. mitochondria. are powerful cell'),
      );
      // Verify spelling follows immediately after organelles with pedagogical syllable chunking
      expect(
        enriched,
        contains('cell organelles, spelled: O, R, G, A, N. organ. E, L, L, E, S. organelles.'),
      );
    });

    test('handles difficult words followed by question marks or inside parentheses', () {
      const question = 'What is photosynthesis?';
      final enrichedQuestion = defaultSpeller.buildSpokenTextWithSpelling(question);
      expect(enrichedQuestion, contains('photosynthesis, spelled:'));
      expect(enrichedQuestion, contains('?'));

      const parenthesized = 'The organelle (mitochondria) produces energy!';
      final enrichedParen = defaultSpeller.buildSpokenTextWithSpelling(parenthesized);
      expect(enrichedParen, contains('mitochondria, spelled:'));
      expect(enrichedParen, contains('!'));
    });

    test('formats short words directly if under chunking length', () {
      final display = defaultSpeller.formatSpellingForDisplay('ATP');
      expect(display, 'A · T · P');
    });

    test('formats Indic aksharas in two pedagogical halves', () {
      // ದ್ಯುತಿಸಂಶ್ಲೇಷಣೆ (Photosynthesis in Kannada)
      const kannadaWord = 'ದ್ಯುತಿಸಂಶ್ಲೇಷಣೆಯು';
      final speech = defaultSpeller.formatSpellingForSpeech(kannadaWord);
      expect(speech, contains('.'));
      expect(speech, endsWith('$kannadaWord.'));
    });
  });
}
