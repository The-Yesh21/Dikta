import 'package:characters/characters.dart';

/// Pure Dart utility to detect difficult/technical words and generate clear,
/// human-friendly letter-by-letter spelling sequences for dictation TTS and UI.
class WordSpeller {
  const WordSpeller({
    this.minLetterThreshold = 7,
  });

  /// Minimum number of letters in a word to qualify as difficult/long.
  final int minLetterThreshold;

  /// Detects difficult or technical words in [text] meeting the length threshold.
  List<String> findDifficultWords(String text) {
    if (text.trim().isEmpty) return const [];

    final rawTokens = text.split(RegExp(r'[\s\-]+'));
    final results = <String>[];
    final seen = <String>{};

    for (final token in rawTokens) {
      // Strip outer punctuation: commas, periods, quotes, brackets
      final clean = token.replaceAll(RegExp(r"^[^a-zA-Z0-9\u0900-\u097F\u0C80-\u0CFF]+|[^a-zA-Z0-9\u0900-\u097F\u0C80-\u0CFF]+$"), '');
      if (clean.length >= minLetterThreshold) {
        final lower = clean.toLowerCase();
        if (!seen.contains(lower)) {
          seen.add(lower);
          results.add(clean);
        }
      }
    }

    return results;
  }

  /// Formats a single word into distinct, spaced letter names for TTS pronunciation.
  ///
  /// For English (Latin): "Mitochondria" -> "M, I, T, O, C, H, O, N, D, R, I, A."
  /// For Indic scripts: uses extended grapheme clusters (aksharas) with comma pauses.
  String formatSpellingForSpeech(String word) {
    final clean = word.replaceAll(RegExp(r"[^a-zA-Z\u0900-\u097F\u0C80-\u0CFF]"), '');
    if (clean.isEmpty) return '';

    // Check if Latin script
    if (RegExp(r'^[a-zA-Z]+$').hasMatch(clean)) {
      final letters = clean.toUpperCase().split('');
      return '${letters.join(', ')}.';
    }

    // Indic scripts: break by grapheme clusters (aksharas)
    final graphemes = clean.characters.where((c) => c.trim().isNotEmpty).toList();
    return '${graphemes.join(', ')}.';
  }

  /// Formats a single word into a clean, hyphenated display string for the UI.
  /// E.g. "M · I · T · O · C · H · O · N · D · R · I · A"
  String formatSpellingForDisplay(String word) {
    final clean = word.replaceAll(RegExp(r"[^a-zA-Z\u0900-\u097F\u0C80-\u0CFF]"), '');
    if (clean.isEmpty) return word;

    if (RegExp(r'^[a-zA-Z]+$').hasMatch(clean)) {
      return clean.toUpperCase().split('').join(' · ');
    }

    return clean.characters.where((c) => c.trim().isNotEmpty).join(' · ');
  }

  /// Enriches the spoken text of a chunk with clear spelled-out difficult words.
  ///
  /// E.g.: "Mitochondria are membrane-bound"
  /// -> "Mitochondria are membrane-bound. Spelled: M, I, T, O, C, H, O, N, D, R, I, A."
  String buildSpokenTextWithSpelling(String phrase) {
    final difficultWords = findDifficultWords(phrase);
    if (difficultWords.isEmpty) return phrase;

    final buffer = StringBuffer(phrase);
    if (!phrase.trim().endsWith('.') && !phrase.trim().endsWith(',')) {
      buffer.write('.');
    }

    for (final word in difficultWords) {
      final spelling = formatSpellingForSpeech(word);
      if (spelling.isNotEmpty) {
        buffer.write(' $word. Spelled: $spelling');
      }
    }

    return buffer.toString();
  }
}
