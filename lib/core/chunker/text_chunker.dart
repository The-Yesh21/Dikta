import '../../config/pacing_config.dart';
import 'chunk_info.dart';
import 'rules/language_rules.dart';
import 'rules/language_rules_registry.dart';

/// Pure Dart phrase chunker designed for handwriting dictation.
///
/// Divides text into human-sized writing phrases (~3–8 words) using candidate
/// breakpoint scoring based on grammatical, punctuation, and linguistic boundaries.
class TextChunker {
  const TextChunker({
    this.config = PacingConfig.defaultConfig,
    this.customRules,
  });

  final PacingConfig config;
  final LanguageRules? customRules;

  /// Splits [rawText] into an ordered list of [ChunkInfo] phrases ready for playback.
  List<ChunkInfo> chunk(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return const [];

    final chunks = <ChunkInfo>[];

    // Split paragraphs by 2 or more newlines.
    final paragraphRegex = RegExp(r'\r?\n\s*\r?\n+');
    final paragraphs = trimmed.split(paragraphRegex);

    var globalIndex = 0;

    for (var pIdx = 0; pIdx < paragraphs.length; pIdx++) {
      final paraText = paragraphs[pIdx].trim();
      if (paraText.isEmpty) continue;

      final isLastParagraph = pIdx == paragraphs.length - 1;
      final paraChunks = _chunkParagraph(paraText, globalIndex);

      if (paraChunks.isEmpty) continue;

      // Mark the final chunk of the paragraph with a paragraph boundary
      final lastIdx = paraChunks.length - 1;
      final lastChunk = paraChunks[lastIdx];
      paraChunks[lastIdx] = ChunkInfo(
        index: lastChunk.index,
        text: lastChunk.text,
        wordCount: lastChunk.wordCount,
        boundaryType: isLastParagraph
            ? (lastChunk.boundaryType == BoundaryType.none
                ? BoundaryType.sentence
                : lastChunk.boundaryType)
            : BoundaryType.paragraph,
        charStartIndex: lastChunk.charStartIndex,
        charEndIndex: lastChunk.charEndIndex,
      );

      chunks.addAll(paraChunks);
      globalIndex += paraChunks.length;
    }

    return chunks;
  }

  /// Breaks a single paragraph into chunks respecting sentences and sub-clause punctuation.
  List<ChunkInfo> _chunkParagraph(String paragraph, int startingIndex) {
    final sentences = _splitSentences(paragraph);
    final chunks = <ChunkInfo>[];
    var currentIndex = startingIndex;

    for (var sIdx = 0; sIdx < sentences.length; sIdx++) {
      final sentence = sentences[sIdx].trim();
      if (sentence.isEmpty) continue;

      final sentenceChunks = _chunkSentence(sentence, currentIndex);
      if (sentenceChunks.isEmpty) continue;

      // Ensure the trailing chunk of a sentence is marked as a sentence boundary
      final lastIdx = sentenceChunks.length - 1;
      final lastChunk = sentenceChunks[lastIdx];
      if (lastChunk.boundaryType != BoundaryType.paragraph) {
        sentenceChunks[lastIdx] = ChunkInfo(
          index: lastChunk.index,
          text: lastChunk.text,
          wordCount: lastChunk.wordCount,
          boundaryType: BoundaryType.sentence,
          charStartIndex: lastChunk.charStartIndex,
          charEndIndex: lastChunk.charEndIndex,
        );
      }

      chunks.addAll(sentenceChunks);
      currentIndex += sentenceChunks.length;
    }

    return chunks;
  }

  /// Splits text into sentences, avoiding false splits on abbreviations or decimals.
  List<String> _splitSentences(String text) {
    // Regex for sentence endings: period, question mark, exclamation, or Indic danda (।, ॥).
    final pattern = RegExp(
      r'(?<=[.!?\u0964\u0965])\s+(?=[A-Z\u0900-\u097F\u0C80-\u0CFF0-9"\(\[])',
    );

    final rawSentences = text.split(pattern);
    final results = <String>[];
    var buffer = '';

    for (final raw in rawSentences) {
      if (buffer.isEmpty) {
        buffer = raw;
      } else {
        if (_isAbbreviation(buffer)) {
          buffer = '$buffer $raw';
        } else {
          results.add(buffer);
          buffer = raw;
        }
      }
    }

    if (buffer.isNotEmpty) {
      results.add(buffer);
    }

    return results;
  }

  bool _isAbbreviation(String text) {
    final trimmed = text.trim();
    final lower = trimmed.toLowerCase();
    const abbrevs = [
      'mr.', 'mrs.', 'ms.', 'dr.', 'prof.', 'sr.', 'jr.', 'vs.', 'etc.',
      'e.g.', 'i.e.', 'a.m.', 'p.m.', 'no.', 'vol.', 'dept.', 'est.',
    ];
    for (final ab in abbrevs) {
      if (lower.endsWith(ab)) return true;
    }
    if (RegExp(r'\b[A-Za-z]\.$').hasMatch(trimmed)) return true;
    return false;
  }

  /// Chunks an individual sentence into phrases between [config.minWordsPerChunk]
  /// and [config.maxWordsPerChunk] words using breakpoint scoring.
  List<ChunkInfo> _chunkSentence(String sentence, int startingIndex) {
    final cleanSentence = sentence.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleanSentence.isEmpty) return const [];

    final words = cleanSentence.split(' ');
    if (words.length <= config.maxWordsPerChunk) {
      return [
        ChunkInfo(
          index: startingIndex,
          text: cleanSentence,
          wordCount: words.length,
          boundaryType: BoundaryType.sentence,
        ),
      ];
    }

    final rules = customRules ?? LanguageRulesRegistry.detect(cleanSentence);
    final chunks = <ChunkInfo>[];
    var chunkIndex = startingIndex;
    var startWordIdx = 0;

    while (startWordIdx < words.length) {
      final remainingTotal = words.length - startWordIdx;

      // If the remaining words all fit within maxWordsPerChunk, emit the final chunk.
      if (remainingTotal <= config.maxWordsPerChunk) {
        final phrase = words.sublist(startWordIdx).join(' ');
        chunks.add(
          ChunkInfo(
            index: chunkIndex++,
            text: phrase,
            wordCount: remainingTotal,
            boundaryType: BoundaryType.sentence,
          ),
        );
        break;
      }

      // Score every candidate split index i in [start + minWords - 1, start + maxWords - 1].
      var bestSplitIdx = -1;
      var bestScore = -999999;
      var bestBoundaryType = BoundaryType.none;

      final minSplit = startWordIdx + config.minWordsPerChunk - 1;
      final maxSplit = (startWordIdx + config.maxWordsPerChunk - 1).clamp(0, words.length - 1);

      for (var i = minSplit; i <= maxSplit; i++) {
        final wordCount = i - startWordIdx + 1;
        final remainderAfter = words.length - (i + 1);

        final word = words[i];
        final nextWord = (i + 1 < words.length) ? words[i + 1] : '';

        final currentClean = _stripPunctuation(word).toLowerCase();
        final nextClean = _stripPunctuation(nextWord).toLowerCase();

        var score = 100;

        // Proximity to target words (default 5 words)
        score -= (wordCount - config.targetWordsPerChunk).abs() * 15;

        // 1. Punctuation scoring:
        final hasClausePunct = _hasClausePunctuation(word);
        if (i == words.length - 1) {
          score += 1000;
        } else if (hasClausePunct) {
          score += 400;
        }

        // 2. Linguistic scoring:
        // Penalize ending on function words / prepositions / determiners
        if (rules.neverEndOnWords.contains(currentClean)) {
          score -= 500;
        }

        // Penalize starting next chunk on a postposition / marker
        if (nextWord.isNotEmpty && rules.neverStartWithWords.contains(nextClean)) {
          score -= 500;
        }

        // Reward breaking before conjunctions or relative words
        if (nextWord.isNotEmpty && rules.goodBreakBeforeWords.contains(nextClean)) {
          score += 250;
        }

        // 3. Remainder penalty: avoid leaving an orphan chunk of 1 or 2 words
        if (remainderAfter > 0 && remainderAfter < config.minWordsPerChunk) {
          score -= 600;
        } else if (remainderAfter == 0) {
          score += 200;
        }

        if (score > bestScore) {
          bestScore = score;
          bestSplitIdx = i + 1;
          bestBoundaryType = (i == words.length - 1)
              ? BoundaryType.sentence
              : (hasClausePunct ? BoundaryType.comma : BoundaryType.none);
        }
      }

      // Fallback safety if no candidate beat default
      if (bestSplitIdx == -1) {
        bestSplitIdx = (startWordIdx + config.targetWordsPerChunk)
            .clamp(startWordIdx + config.minWordsPerChunk, startWordIdx + config.maxWordsPerChunk);
        bestBoundaryType = BoundaryType.none;
      }

      final phrase = words.sublist(startWordIdx, bestSplitIdx).join(' ');
      chunks.add(
        ChunkInfo(
          index: chunkIndex++,
          text: phrase,
          wordCount: bestSplitIdx - startWordIdx,
          boundaryType: bestBoundaryType,
        ),
      );

      startWordIdx = bestSplitIdx;
    }

    return chunks;
  }

  bool _hasClausePunctuation(String word) {
    return word.endsWith(',') ||
        word.endsWith(';') ||
        word.endsWith(':') ||
        word.endsWith('—') ||
        word.endsWith('-');
  }

  String _stripPunctuation(String token) {
    return token.replaceAll(RegExp(r'^[^\w\u0900-\u097F\u0C80-\u0CFF]+|[^\w\u0900-\u097F\u0C80-\u0CFF]+$'), '');
  }
}
