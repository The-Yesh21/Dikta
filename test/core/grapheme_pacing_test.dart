import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dictation_app/config/pacing_config.dart';
import 'package:dictation_app/core/chunker/chunk_info.dart';
import 'package:dictation_app/core/pacing/pacing_engine.dart';
import 'package:dictation_app/services/audio/dictation_playback_controller.dart';

void main() {
  group('Grapheme Cluster Counting & Script Detection', () {
    test('English (Latin) grapheme cluster counts', () {
      expect(PacingEngine.countGraphemes('Mitochondria'), 12);
      expect(PacingEngine.countGraphemes('Cell organelles generate chemical energy.'), 37);
      expect(PacingEngine.detectScript('Cell organelles'), ScriptType.latin);
    });

    test('Hindi (Devanagari) grapheme cluster counts', () {
      // "नमस्ते" -> ['न', 'म', 'स्ते'] = 3 grapheme clusters
      expect(PacingEngine.countGraphemes('नमस्ते'), 3);
      expect('नमस्ते'.characters.toList(), ['न', 'म', 'स्ते']);

      // "प्रकाश" -> ['प्र', 'का', 'श'] = 3 grapheme clusters
      expect(PacingEngine.countGraphemes('प्रकाश'), 3);

      // "पौधे सूर्य के प्रकाश से ऊर्जा बनाते हैं।"
      final hindiSample = 'पौधे सूर्य के प्रकाश से ऊर्जा बनाते हैं।';
      expect(PacingEngine.countGraphemes(hindiSample), greaterThan(15));
      expect(PacingEngine.detectScript(hindiSample), ScriptType.devanagari);
    });

    test('Kannada grapheme cluster counts', () {
      // Dart's characters package evaluates "ದ್ಯುತಿಸಂಶ್ಲೇಷಣೆ" into 8 Unicode grapheme clusters
      const kannadaWord = 'ದ್ಯುತಿಸಂಶ್ಲೇಷಣೆ';
      expect(PacingEngine.countGraphemes(kannadaWord), 8);

      // "ಸಸ್ಯಗಳು ಸೂರ್ಯನ ಬೆಳಕಿನಿಂದ ಆಹಾರ ತಯಾರಿಸುತ್ತವೆ."
      const kannadaSample = 'ಸಸ್ಯಗಳು ಸೂರ್ಯನ ಬೆಳಕಿನಿಂದ ಆಹಾರ ತಯಾರಿಸುತ್ತವೆ.';
      expect(PacingEngine.countGraphemes(kannadaSample), greaterThan(15));
      expect(PacingEngine.detectScript(kannadaSample), ScriptType.kannada);
    });
  });

  group('Pacing Engine Gap Formula & Guarantees', () {
    late PacingEngine engine;

    setUp(() {
      engine = PacingEngine(
        config: const PacingConfig(
          overlapFactor: 0.5,
          scriptFactorLatin: 1.0,
          scriptFactorDevanagari: 1.0,
          scriptFactorKannada: 1.0,
          defaultUserLpm: 48.0,
          syntaxPauseCommaSeconds: 0.4,
          syntaxPauseSentenceSeconds: 1.2,
          syntaxPauseParagraphSeconds: 2.5,
          minGapSeconds: 0.3,
          jitterSigma: 0.0, // turn off jitter for deterministic formula verification
          fatigueStrength: 0.0,
        ),
      );
    });

    test('GAP IS NEVER NEGATIVE: strictly >= minGap', () {
      const chunk = ChunkInfo(
        text: 'Short',
        index: 0,
        wordCount: 1,
        boundaryType: BoundaryType.none,
      );

      // Extreme speech durations: 5s, 10s, 60s, 300s
      for (final duration in [5.0, 10.0, 60.0, 300.0]) {
        final gap = engine.calculateGap(chunk, speechDurationSeconds: duration);
        expect(gap, greaterThanOrEqualTo(0.3));
      }
    });

    test('SPEECH LONGER THAN BUDGET GIVES MINGAP (+ boundary pause)', () {
      // Text: "Hello" (5 graphemes @ 48 LPM = 6.25s writeSeconds)
      const chunkNone = ChunkInfo(
        text: 'Hello',
        index: 0,
        wordCount: 1,
        boundaryType: BoundaryType.none,
      );
      const chunkComma = ChunkInfo(
        text: 'Hello,',
        index: 1,
        wordCount: 1,
        boundaryType: BoundaryType.comma,
      );
      const chunkSentence = ChunkInfo(
        text: 'Hello.',
        index: 2,
        wordCount: 1,
        boundaryType: BoundaryType.sentence,
      );
      const chunkParagraph = ChunkInfo(
        text: 'Hello.\n\n',
        index: 3,
        wordCount: 1,
        boundaryType: BoundaryType.paragraph,
      );

      // Speech duration = 20.0s -> overlap = 0.5 * 20.0 = 10.0s.
      // Net writing time = max(0.3, 6.25 - 10.0) = 0.3s (minGap).

      // Boundary none: minGap + 0.0 = 0.30s
      final gapNone = engine.calculateGap(chunkNone, speechDurationSeconds: 20.0, applyJitter: false);
      expect(gapNone, closeTo(0.30, 0.001));

      // Boundary comma: minGap + 0.4s = 0.70s
      final gapComma = engine.calculateGap(chunkComma, speechDurationSeconds: 20.0, applyJitter: false);
      expect(gapComma, closeTo(0.70, 0.001));

      // Boundary sentence: minGap + 1.2s = 1.50s
      final gapSentence = engine.calculateGap(chunkSentence, speechDurationSeconds: 20.0, applyJitter: false);
      expect(gapSentence, closeTo(1.50, 0.001));

      // Boundary paragraph: minGap + 2.5s = 2.80s
      final gapParagraph = engine.calculateGap(chunkParagraph, speechDurationSeconds: 20.0, applyJitter: false);
      expect(gapParagraph, closeTo(2.80, 0.001));
    });

    test('NORMAL PACING: net writing budget is counted from START of speech', () {
      // Text: "Mitochondria generates energy," (28 non-whitespace graphemes @ 48 LPM = 35.0s budget)
      const chunk = ChunkInfo(
        text: 'Mitochondria generates energy,',
        index: 0,
        wordCount: 3,
        boundaryType: BoundaryType.comma,
      );

      // Speech takes 2.0s
      // Overlap = 0.5 * 2.0 = 1.0s
      // Remaining writing time = 35.0s - 1.0s = 34.0s
      // Comma boundary = +0.4s
      // Total gap = 34.0s + 0.4s = 34.4s
      final gap = engine.calculateGap(chunk, speechDurationSeconds: 2.0, applyJitter: false);
      expect(gap, closeTo(34.40, 0.05));

      // Total cycle = speech (2.0s) + gap (34.40s) = 36.40s
      final totalCycle = 2.0 + gap;
      expect(totalCycle, closeTo(36.40, 0.05));
    });

    test('Separate config pacing per script family', () {
      final scriptEngine = PacingEngine(
        config: const PacingConfig(
          overlapFactor: 0.5,
          scriptFactorLatin: 1.0,
          scriptFactorDevanagari: 1.2,
          scriptFactorKannada: 1.5,
          defaultUserLpm: 60.0, // 60 lpm = 1 letter/sec
          jitterSigma: 0.0,
          fatigueStrength: 0.0,
        ),
      );

      const latinChunk = ChunkInfo(text: 'ABCDE', index: 0, wordCount: 1, boundaryType: BoundaryType.none);
      const hindiChunk = ChunkInfo(text: 'नमस्ते', index: 1, wordCount: 1, boundaryType: BoundaryType.none);
      const kannadaChunk = ChunkInfo(text: 'ದ್ಯುತಿಸಂಶ್ಲೇಷಣೆ', index: 2, wordCount: 1, boundaryType: BoundaryType.none);

      final budgetLatin = scriptEngine.calculateWritingBudget(latinChunk);
      final budgetHindi = scriptEngine.calculateWritingBudget(hindiChunk);
      final budgetKannada = scriptEngine.calculateWritingBudget(kannadaChunk);

      // Latin: (5 / 60) * 60 * 1.0 = 5.00s
      expect(budgetLatin, closeTo(5.00, 0.01));

      // Hindi: (3 / 60) * 60 * 1.2 = 3.60s
      expect(budgetHindi, closeTo(3.60, 0.01));

      // Kannada: (8 / 60) * 60 * 1.5 = 12.00s
      expect(budgetKannada, closeTo(12.00, 0.01));
    });
  });

  group('Session Log Table Formatting & Copyability', () {
    test('formats valid Markdown table with all required columns and user actions', () {
      const logs = [
        DictationSessionLog(
          chunkIndex: 0,
          text: 'Mitochondria are membrane-bound',
          graphemes: 28,
          speechDurationSeconds: 1.80,
          writingBudgetSeconds: 7.84,
          gapSeconds: 6.04,
          totalCycleSeconds: 7.84,
          boundaryType: BoundaryType.none,
          userAction: 'none',
          isFromCache: false,
        ),
        DictationSessionLog(
          chunkIndex: 1,
          text: 'cell organelles that generate energy,',
          graphemes: 32,
          speechDurationSeconds: 2.10,
          writingBudgetSeconds: 8.96,
          gapSeconds: 7.26,
          totalCycleSeconds: 9.36,
          boundaryType: BoundaryType.comma,
          userAction: 'next (advance)',
          isFromCache: true,
        ),
      ];

      final markdown = DictationSessionLog.formatSessionTableMarkdown(logs);

      expect(markdown, contains('| # | Graphemes | Speech (s) | Writing Budget (s) | Gap (s) | Total Cycle (s) | Boundary | User Action | Source | Chunk Text |'));
      expect(markdown, contains('| #0 | 28 | 1.80 | 7.84 | 6.04 | 7.84 | none | none | ☁️ API | "Mitochondria are membrane-bound" |'));
      expect(markdown, contains('| #1 | 32 | 2.10 | 8.96 | 7.26 | 9.36 | comma | next (advance) | ⚡ Cache | "cell organelles that generate energy," |'));
    });
  });
}
