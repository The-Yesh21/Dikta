import 'package:flutter_test/flutter_test.dart';
import 'package:dictation_app/config/pacing_config.dart';
import 'package:dictation_app/config/pacing_priors.dart';
import 'package:dictation_app/core/chunker/chunk_info.dart';
import 'package:dictation_app/core/pacing/pacing_engine.dart';

void main() {
  group('Pacing Priors & Age Group Calculations', () {
    test('verifies prior LPM and effective starting LPM for each age group', () {
      // Age 8-10: 30 lpm -> effective = 30 * 0.8 = 24 lpm
      expect(AgeGroup.age8to10.priorLpm, equals(30.0));
      expect(AgeGroup.age8to10.effectiveStartingLpm(), closeTo(24.0, 1e-6));
      expect(PacingPriors.getPriorLpm(AgeGroup.age8to10), equals(30.0));
      expect(PacingPriors.getEffectiveStartingLpm(AgeGroup.age8to10), closeTo(24.0, 1e-6));

      // Age 11-13: 45 lpm -> effective = 45 * 0.8 = 36 lpm
      expect(AgeGroup.age11to13.priorLpm, equals(45.0));
      expect(AgeGroup.age11to13.effectiveStartingLpm(), closeTo(36.0, 1e-6));
      expect(PacingPriors.getPriorLpm(AgeGroup.age11to13), equals(45.0));
      expect(PacingPriors.getEffectiveStartingLpm(AgeGroup.age11to13), closeTo(36.0, 1e-6));

      // Age 14-17: 60 lpm -> effective = 60 * 0.8 = 48 lpm
      expect(AgeGroup.age14to17.priorLpm, equals(60.0));
      expect(AgeGroup.age14to17.effectiveStartingLpm(), closeTo(48.0, 1e-6));
      expect(PacingPriors.getPriorLpm(AgeGroup.age14to17), equals(60.0));
      expect(PacingPriors.getEffectiveStartingLpm(AgeGroup.age14to17), closeTo(48.0, 1e-6));

      // Age 18+: 60 lpm -> effective = 60 * 0.8 = 48 lpm
      expect(AgeGroup.age18Plus.priorLpm, equals(60.0));
      expect(AgeGroup.age18Plus.effectiveStartingLpm(), closeTo(48.0, 1e-6));
      expect(PacingPriors.getPriorLpm(AgeGroup.age18Plus), equals(60.0));
      expect(PacingPriors.getEffectiveStartingLpm(AgeGroup.age18Plus), closeTo(48.0, 1e-6));
    });

    test('supports custom dictationFactor in effective starting LPM calculation', () {
      expect(
        PacingPriors.getEffectiveStartingLpm(AgeGroup.age18Plus, dictationFactor: 1.0),
        equals(60.0),
      );
      expect(
        PacingPriors.getEffectiveStartingLpm(AgeGroup.age8to10, dictationFactor: 0.5),
        equals(15.0),
      );
    });

    test('priors map contains all defined age groups', () {
      for (final group in AgeGroup.values) {
        expect(PacingPriors.priorsByAge.containsKey(group), isTrue);
        expect(PacingPriors.priorsByAge[group], equals(group.priorLpm));
      }
    });
  });

  group('PacingConfig Default Parameters', () {
    test('verifies overlapFactor, scriptFactor, and dictationFactor defaults', () {
      const config = PacingConfig();
      expect(config.overlapFactor, equals(0.5));
      expect(config.scriptFactorLatin, equals(1.0));
      expect(config.scriptFactorDevanagari, equals(1.0));
      expect(config.scriptFactorKannada, equals(1.0));
      expect(config.dictationFactor, equals(0.8));
      expect(config.defaultUserLpm, equals(48.0));

      expect(config.getScriptFactor(ScriptType.latin), equals(1.0));
      expect(config.getScriptFactor(ScriptType.devanagari), equals(1.0));
      expect(config.getScriptFactor(ScriptType.kannada), equals(1.0));
    });

    test('copyWith updates new fields properly', () {
      const config = PacingConfig();
      final updated = config.copyWith(
        overlapFactor: 0.6,
        scriptFactorLatin: 1.1,
        scriptFactorDevanagari: 1.2,
        scriptFactorKannada: 1.3,
        dictationFactor: 0.85,
        defaultUserLpm: 50.0,
      );

      expect(updated.overlapFactor, equals(0.6));
      expect(updated.scriptFactorLatin, equals(1.1));
      expect(updated.scriptFactorDevanagari, equals(1.2));
      expect(updated.scriptFactorKannada, equals(1.3));
      expect(updated.dictationFactor, equals(0.85));
      expect(updated.defaultUserLpm, equals(50.0));
    });
  });

  group('PacingEngine Graphemes Excluding Spaces', () {
    test('spaces and whitespace are excluded from grapheme count', () {
      expect(PacingEngine.countGraphemes('hello world'), equals(10));
      expect(PacingEngine.countGraphemes('helloworld'), equals(10));
      expect(PacingEngine.countGraphemes('  h  e  l  l  o  '), equals(5));
      expect(PacingEngine.countGraphemes(''), equals(0));
      expect(PacingEngine.countGraphemes('   \t\n  '), equals(0));
    });
  });

  group('PacingEngine: Fewer Letters -> Shorter Gap', () {
    late PacingEngine engine;

    setUp(() {
      engine = PacingEngine(
        config: const PacingConfig(
          overlapFactor: 0.5,
          scriptFactorLatin: 1.0,
          minGapSeconds: 0.3,
          jitterSigma: 0.0,
          fatigueStrength: 0.0,
        ),
        userLpm: 48.0,
      );
    });

    test('strictly verifies that fewer letters yield a shorter gap', () {
      // Chunk with 25 characters (excluding spaces)
      const chunkLong = ChunkInfo(
        index: 0,
        text: 'Mitochondria produce energy', // 25 letters: Mitochondriaproduceenergy
        wordCount: 3,
        boundaryType: BoundaryType.none,
      );

      // Chunk with 16 characters
      const chunkMedium = ChunkInfo(
        index: 1,
        text: 'Produce energy now', // 16 letters: Produceenergynow
        wordCount: 3,
        boundaryType: BoundaryType.none,
      );

      // Chunk with 8 characters
      const chunkShort = ChunkInfo(
        index: 2,
        text: 'Cell ATP', // 7 letters: CellATP
        wordCount: 2,
        boundaryType: BoundaryType.none,
      );

      // Chunk with 3 characters
      const chunkVeryShort = ChunkInfo(
        index: 3,
        text: 'ATP', // 3 letters: ATP
        wordCount: 1,
        boundaryType: BoundaryType.none,
      );

      const speechDuration = 1.5; // Fixed 1.5s speech duration for all

      final gapLong = engine.calculateGap(chunkLong, speechDurationSeconds: speechDuration, applyJitter: false);
      final gapMedium = engine.calculateGap(chunkMedium, speechDurationSeconds: speechDuration, applyJitter: false);
      final gapShort = engine.calculateGap(chunkShort, speechDurationSeconds: speechDuration, applyJitter: false);
      final gapVeryShort = engine.calculateGap(chunkVeryShort, speechDurationSeconds: speechDuration, applyJitter: false);

      expect(PacingEngine.countGraphemes(chunkLong.text), greaterThan(PacingEngine.countGraphemes(chunkMedium.text)));
      expect(PacingEngine.countGraphemes(chunkMedium.text), greaterThan(PacingEngine.countGraphemes(chunkShort.text)));
      expect(PacingEngine.countGraphemes(chunkShort.text), greaterThan(PacingEngine.countGraphemes(chunkVeryShort.text)));

      // Gaps must be strictly monotonically decreasing with letter count
      expect(gapLong, greaterThan(gapMedium));
      expect(gapMedium, greaterThan(gapShort));
      expect(gapShort, greaterThan(gapVeryShort));
      expect(gapVeryShort, greaterThanOrEqualTo(0.3)); // Never below minGap
    });

    test('exact formula verification: writeSeconds = (graphemes / userLpm) * 60 * scriptFactor', () {
      // 24 graphemes, userLpm = 48.0 -> writeSeconds = (24 / 48) * 60 * 1.0 = 30.0s
      const chunk = ChunkInfo(
        index: 0,
        text: '123456789012345678901234',
        wordCount: 1,
        boundaryType: BoundaryType.comma,
      );

      final writeSeconds = engine.calculateWriteSeconds(chunk);
      expect(writeSeconds, closeTo(30.0, 1e-6));

      // Speech duration = 4.0s
      // Overlap = 0.5 * 4.0 = 2.0s
      // Net writing = 30.0 - 2.0 = 28.0s
      // Comma boundary = +0.4s
      // Total gap = 28.0 + 0.4 = 28.4s
      final gap = engine.calculateGap(chunk, speechDurationSeconds: 4.0, applyJitter: false);
      expect(gap, closeTo(28.4, 1e-6));
    });

    test('speech duration overlap never pulls gap below minGap + boundary pause', () {
      // 2 letters -> writeSeconds = (2 / 48) * 60 = 2.5s
      const chunk = ChunkInfo(
        index: 0,
        text: 'Go',
        wordCount: 1,
        boundaryType: BoundaryType.sentence,
      );

      // Extreme speech duration: 20.0s -> overlap = 10.0s -> 2.5 - 10 = -7.5s -> clamped to minGap 0.3s
      // Boundary sentence pause = 1.2s
      // Total gap = 0.3 + 1.2 = 1.5s
      final gap = engine.calculateGap(chunk, speechDurationSeconds: 20.0, applyJitter: false);
      expect(gap, closeTo(1.5, 1e-6));
    });
  });
}
