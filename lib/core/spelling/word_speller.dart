import 'package:characters/characters.dart';

/// Pure Dart utility to detect difficult/technical words and generate pedagogical,
/// human-friendly syllable-by-syllable spelling sequences for dictation TTS and UI.
///
/// Follows human teaching methodology:
/// E.g. "Mitochondria" -> "M, I, T, O. mito. C, H, O, N, D, R, I, A. mitochondria."
class WordSpeller {
  const WordSpeller({
    this.minLetterThreshold = 10,
  });

  /// Minimum number of letters in a word to qualify as difficult/long (default: 10).
  final int minLetterThreshold;

  static const List<String> commonPrefixes = [
    'mito', 'photo', 'chloro', 'bio', 'micro', 'macro', 'multi', 'inter',
    'intra', 'trans', 'super', 'hyper', 'organ', 'electro', 'hydro', 'thermo',
    'psycho', 'neuro', 'cardio', 'tele', 'auto', 'hemi', 'semi', 'poly',
    'mono', 'infra', 'ultra', 'extra', 'under', 'anti', 'counter'
  ];

  /// Detects difficult or technical words in [text] meeting the length threshold (>=10 by default).
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

  /// Splits an English/Latin word into natural pedagogical syllable/morpheme chunks.
  /// E.g. "Mitochondria" -> ["Mito", "chondria"]
  List<String> chunkWord(String word) {
    final clean = word.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (clean.length < 6) return [clean];

    final lower = clean.toLowerCase();

    // 1. Check for common scientific/academic prefixes
    for (final prefix in commonPrefixes) {
      if (lower.startsWith(prefix) && (clean.length - prefix.length) >= 3) {
        final chunk1 = clean.substring(0, prefix.length);
        final chunk2 = clean.substring(prefix.length);
        return [chunk1, chunk2];
      }
    }

    // 2. Syllable-based vowel boundary split near midpoint
    final mid = clean.length ~/ 2;
    int bestSplit = mid;
    int minDistance = clean.length;

    const vowels = 'aeiouyAEIOUY';
    for (int i = 3; i <= clean.length - 3; i++) {
      if (vowels.contains(clean[i - 1])) {
        final dist = (i - mid).abs();
        if (dist < minDistance) {
          minDistance = dist;
          bestSplit = i;
        }
      }
    }

    return [
      clean.substring(0, bestSplit),
      clean.substring(bestSplit),
    ];
  }

  /// Formats a single word into a pedagogical spelling string for TTS pronunciation.
  ///
  /// For English:
  /// "Mitochondria" -> "M, I, T, O. mito. C, H, O, N, D, R, I, A. mitochondria."
  ///
  /// For Indic (Kannada, Hindi):
  /// Chunks aksharas (syllabic graphemes) into two halves for human teaching pace:
  /// First half spelled -> spoken -> second half spelled -> full word.
  String formatSpellingForSpeech(String word) {
    final clean = word.replaceAll(RegExp(r"[^a-zA-Z\u0900-\u097F\u0C80-\u0CFF]"), '');
    if (clean.isEmpty) return '';

    // English / Latin
    if (RegExp(r'^[a-zA-Z]+$').hasMatch(clean)) {
      final chunks = chunkWord(clean);
      if (chunks.length <= 1) {
        final letters = clean.toUpperCase().split('').join(', ');
        return '$letters. ${clean.toLowerCase()}.';
      }

      final buffer = StringBuffer();
      for (int i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        final letters = chunk.toUpperCase().split('').join(', ');
        final isLast = (i == chunks.length - 1);
        final spoken = isLast ? clean.toLowerCase() : chunk.toLowerCase();
        buffer.write('$letters. $spoken.');
        if (!isLast) buffer.write(' ');
      }
      return buffer.toString();
    }

    // Indic scripts (Kannada, Hindi): grapheme cluster aksharas
    final graphemes = clean.characters.where((c) => c.trim().isNotEmpty).toList();
    if (graphemes.length < 6) {
      return '${graphemes.join(', ')}. $clean.';
    }

    final mid = graphemes.length ~/ 2;
    final half1 = graphemes.sublist(0, mid);
    final half2 = graphemes.sublist(mid);

    return '${half1.join(', ')}. ${half1.join('')}. ${half2.join(', ')}. $clean.';
  }

  /// Formats a single word into a clean, human-readable chunked display string for UI chips.
  /// E.g. "M · I · T · O (mito)   ·   C · H · O · N · D · R · I · A (mitochondria)"
  String formatSpellingForDisplay(String word) {
    final clean = word.replaceAll(RegExp(r"[^a-zA-Z\u0900-\u097F\u0C80-\u0CFF]"), '');
    if (clean.isEmpty) return word;

    if (RegExp(r'^[a-zA-Z]+$').hasMatch(clean)) {
      final chunks = chunkWord(clean);
      if (chunks.length <= 1) {
        return clean.toUpperCase().split('').join(' · ');
      }
      return chunks.map((c) {
        final dots = c.toUpperCase().split('').join(' · ');
        final isLast = (c == chunks.last);
        final label = isLast ? word.toLowerCase() : c.toLowerCase();
        return '$dots ($label)';
      }).join('   ·   ');
    }

    final graphemes = clean.characters.where((c) => c.trim().isNotEmpty).toList();
    if (graphemes.length < 6) {
      return graphemes.join(' · ');
    }

    final mid = graphemes.length ~/ 2;
    final half1 = graphemes.sublist(0, mid).join(' · ');
    final half2 = graphemes.sublist(mid).join(' · ');
    return '$half1   ·   $half2 ($clean)';
  }

  /// Enriches the spoken text of a chunk with pedagogical spelled-out difficult words.
  ///
  /// E.g.: "Mitochondria are membrane-bound cell organelles"
  /// -> "Mitochondria are membrane-bound cell organelles. Spelled: M, I, T, O. mito. C, H, O, N, D, R, I, A. mitochondria."
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
