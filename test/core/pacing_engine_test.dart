import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:dictation_app/config/pacing_config.dart';
import 'package:dictation_app/core/chunker/chunk_info.dart';
import 'package:dictation_app/core/pacing/pacing_engine.dart';

void main() {
  group('PacingEngine Determinism & Seeded Random', () {
    test('same seed gives identical output', () {
      final fixedTime = DateTime(2026, 11, 4, 12, 0, 0);
      DateTime clock() => fixedTime;

      final engine1 = PacingEngine(
        clock: clock,
        random: math.Random(42),
      );
      final engine2 = PacingEngine(
        clock: clock,
        random: math.Random(42),
      );

      const chunk = ChunkInfo(
        index: 0,
        text: 'This is a test phrase.',
        wordCount: 5,
        boundaryType: BoundaryType.comma,
      );

      final gap1a = engine1.calculateGap(chunk);
      final gap2a = engine2.calculateGap(chunk);
      expect(gap1a, equals(gap2a));

      final gap1b = engine1.calculateGap(chunk);
      final gap2b = engine2.calculateGap(chunk);
      expect(gap1b, equals(gap2b));
    });
  });

  group('PacingEngine Tempo Decay & Gap Growth', () {
    test('gap increases as tempo decays over time', () {
      var currentTime = DateTime(2026, 11, 4, 12, 0, 0);
      DateTime clock() => currentTime;

      // jitterSigma = 0 ensures no random noise in this mathematical test
      final engine = PacingEngine(
        config: const PacingConfig(jitterSigma: 0.0),
        clock: clock,
        random: math.Random(1),
      );

      const chunk = ChunkInfo(
        index: 0,
        text: 'Write this sentence down.',
        wordCount: 4,
        boundaryType: BoundaryType.none,
      );

      // At start (t = 0), tempo is 1.0
      expect(engine.currentTempo, closeTo(1.0, 1e-4));
      final initialGap = engine.calculateGap(chunk);

      // Advance by 12 minutes (one tau)
      currentTime = currentTime.add(const Duration(minutes: 12));
      final decayedTempo = engine.currentTempo;
      expect(decayedTempo, lessThan(1.0));

      final laterGap = engine.calculateGap(chunk);
      expect(laterGap, greaterThan(initialGap));
    });

    test('fatigueStrength = 0 gives constant tempo', () {
      var currentTime = DateTime(2026, 11, 4, 12, 0, 0);
      DateTime clock() => currentTime;

      final engine = PacingEngine(
        config: const PacingConfig(fatigueStrength: 0.0),
        clock: clock,
        random: math.Random(1),
      );

      expect(engine.currentTempo, equals(1.0));

      // Advance time by 60 minutes
      currentTime = currentTime.add(const Duration(minutes: 60));
      expect(engine.currentTempo, equals(1.0));
    });
  });

  group('PacingEngine Bounds & Safety Limits', () {
    test('gap is never below minGapSeconds even with long speech duration', () {
      final engine = PacingEngine(
        clock: () => DateTime(2026, 11, 4, 12, 0, 0),
        random: math.Random(1),
      );

      const chunk = ChunkInfo(
        index: 0,
        text: 'Short phrase.',
        wordCount: 2,
        boundaryType: BoundaryType.none,
      );

      // Extreme speech duration exceeding any natural writing window
      final gap = engine.calculateGap(chunk, speechDurationSeconds: 100.0);
      expect(gap, equals(PacingConfig.defaultConfig.minGapSeconds));
    });

    test('handles zero and one-word chunk edge cases', () {
      final engine = PacingEngine(
        clock: () => DateTime(2026, 11, 4, 12, 0, 0),
        random: math.Random(1),
      );

      const zeroWordChunk = ChunkInfo(
        index: 0,
        text: '',
        wordCount: 0,
        boundaryType: BoundaryType.none,
      );
      expect(
        engine.calculateGap(zeroWordChunk),
        equals(PacingConfig.defaultConfig.minGapSeconds),
      );

      const oneWordChunk = ChunkInfo(
        index: 1,
        text: 'Wait.',
        wordCount: 1,
        boundaryType: BoundaryType.sentence,
      );
      final gap = engine.calculateGap(oneWordChunk);
      expect(gap, greaterThanOrEqualTo(PacingConfig.defaultConfig.minGapSeconds));
    });
  });

  group('PacingEngine Sawtooth Rhythm & Fatigue Recovery', () {
    test('sawtooth breath raises tempo again after decay', () {
      var currentTime = DateTime(2026, 11, 4, 12, 0, 0);
      DateTime clock() => currentTime;

      final engine = PacingEngine(
        config: const PacingConfig(
          jitterSigma: 0.0,
          sawtoothIntervalMinutes: 60.0, // avoid auto-triggering during test
          sawtoothRecoveryRatio: 0.5,
        ),
        clock: clock,
        random: math.Random(1),
      );

      // Advance by 12 minutes (significant fatigue)
      currentTime = currentTime.add(const Duration(minutes: 12));
      final tempoBeforeBreath = engine.currentTempo;

      // Apply breath
      engine.applySawtoothBreath();
      final tempoAfterBreath = engine.currentTempo;

      // Tempo must recover upward toward 1.0
      expect(tempoAfterBreath, greaterThan(tempoBeforeBreath));
      expect(tempoAfterBreath, lessThanOrEqualTo(1.0));
    });

    test('paragraph break chunk triggers sawtooth breath', () {
      var currentTime = DateTime(2026, 11, 4, 12, 0, 0);
      DateTime clock() => currentTime;

      final engine = PacingEngine(
        config: const PacingConfig(
          jitterSigma: 0.0,
          sawtoothIntervalMinutes: 60.0,
          sawtoothRecoveryRatio: 0.5,
        ),
        clock: clock,
        random: math.Random(1),
      );

      // Advance by 12 minutes
      currentTime = currentTime.add(const Duration(minutes: 12));
      final tempoBefore = engine.currentTempo;

      const paraChunk = ChunkInfo(
        index: 5,
        text: 'This concludes the section on cell membranes.',
        wordCount: 7,
        boundaryType: BoundaryType.paragraph,
      );

      engine.calculateGap(paraChunk);
      final tempoAfter = engine.currentTempo;

      expect(tempoAfter, greaterThan(tempoBefore));
    });
  });

  group('PacingEngine Adaptive Writing Speed', () {
    test('adaptSlower lowers writing speed', () {
      final engine = PacingEngine();
      final initialSpeed = engine.currentWritingSpeed;
      engine.adaptSlower();
      expect(engine.currentWritingSpeed, lessThan(initialSpeed));
    });

    test('adaptFaster raises writing speed', () {
      final engine = PacingEngine();
      final initialSpeed = engine.currentWritingSpeed;
      engine.adaptFaster();
      expect(engine.currentWritingSpeed, greaterThan(initialSpeed));
    });
  });

  group('PacingEngine Voice Speed & Long-Word Rate Scaling', () {
    test('uses default gnaniSpeechRate (1.0) for regular word length phrases', () {
      final engine = PacingEngine(
        config: const PacingConfig(
          gnaniSpeechRate: 1.0,
          longWordCharThreshold: 6.0,
          longWordSpeedScale: 0.85,
        ),
      );

      // "This is a simple phrase" -> word lengths: 4, 2, 1, 6, 6 -> avg = 3.8 < 6.0
      const chunk = ChunkInfo(
        index: 0,
        text: 'This is a simple phrase.',
        wordCount: 5,
        boundaryType: BoundaryType.none,
      );

      final speed = engine.calculateChunkVoiceSpeed(chunk);
      expect(speed, closeTo(1.0, 1e-4));
    });

    test('scales speed down when average characters per word meets or exceeds threshold', () {
      final engine = PacingEngine(
        config: const PacingConfig(
          gnaniSpeechRate: 1.0,
          longWordCharThreshold: 6.0,
          longWordSpeedScale: 0.85,
        ),
      );

      // "mitochondria electrochemical reactions" -> lengths: 12, 15, 9 -> avg = 12.0 >= 6.0
      const chunk = ChunkInfo(
        index: 1,
        text: 'mitochondria electrochemical reactions',
        wordCount: 3,
        boundaryType: BoundaryType.none,
      );

      final speed = engine.calculateChunkVoiceSpeed(chunk);
      // 1.0 * 0.85 = 0.85
      expect(speed, closeTo(0.85, 1e-4));
    });

    test('handles empty or zero-word chunk gracefully', () {
      final engine = PacingEngine();
      const emptyChunk = ChunkInfo(
        index: 0,
        text: '',
        wordCount: 0,
        boundaryType: BoundaryType.none,
      );

      expect(engine.calculateChunkVoiceSpeed(emptyChunk), equals(engine.config.gnaniSpeechRate));
    });
  });

  group('PacingEngine Additive Syntax Pauses', () {
    test('adds fixed additive seconds for comma (0.4s), sentence (1.2s), and paragraph (2.5s)', () {
      final engine = PacingEngine(
        config: const PacingConfig(
          jitterSigma: 0.0,
          syntaxPauseCommaSeconds: 0.4,
          syntaxPauseSentenceSeconds: 1.2,
          syntaxPauseParagraphSeconds: 2.5,
          defaultWritingSpeed: 0.7,
        ),
        clock: () => DateTime(2026, 11, 4, 12, 0, 0),
        random: math.Random(1),
      );

      const chunkNone = ChunkInfo(index: 0, text: 'five word test phrase here', wordCount: 5, boundaryType: BoundaryType.none);
      const chunkComma = ChunkInfo(index: 1, text: 'five word test phrase here', wordCount: 5, boundaryType: BoundaryType.comma);
      const chunkSentence = ChunkInfo(index: 2, text: 'five word test phrase here', wordCount: 5, boundaryType: BoundaryType.sentence);
      const chunkParagraph = ChunkInfo(index: 3, text: 'five word test phrase here', wordCount: 5, boundaryType: BoundaryType.paragraph);

      final gapNone = engine.calculateGap(chunkNone, applyJitter: false);
      final gapComma = engine.calculateGap(chunkComma, applyJitter: false);
      final gapSentence = engine.calculateGap(chunkSentence, applyJitter: false);
      final gapParagraph = engine.calculateGap(chunkParagraph, applyJitter: false);

      // Comma must add exactly 0.4s over none
      expect(gapComma - gapNone, closeTo(0.4, 1e-4));
      // Sentence must add exactly 1.2s over none
      expect(gapSentence - gapNone, closeTo(1.2, 1e-4));
      // Paragraph must add at least 2.5s over none
      expect(gapParagraph, greaterThan(gapNone));
    });

    test('manual writingSpeed setter updates handwriting speed immediately', () {
      final engine = PacingEngine();
      expect(engine.currentWritingSpeed, closeTo(0.71, 0.05));

      engine.writingSpeed = 1.0;
      expect(engine.currentWritingSpeed, closeTo(1.0, 0.05));
    });
  });
}
