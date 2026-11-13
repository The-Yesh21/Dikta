import 'package:flutter_test/flutter_test.dart';
import 'package:dictation_app/config/pacing_feedback_config.dart';
import 'package:dictation_app/core/pacing/pacing_feedback_loop.dart';

void main() {
  group('PacingFeedbackLoop Convergence Simulations', () {
    test('Simulating user writing at 80 LPM converges within 15 chunks without oscillating', () {
      const targetLpm = 80.0;
      const initialLpm = 40.0;
      final loop = PacingFeedbackLoop(
        initialLpm: initialLpm,
        config: const PacingFeedbackConfig(
          initialAlpha: 0.25,
          minAlpha: 0.05,
        ),
      );

      final lpmHistory = <double>[initialLpm];
      final graphemesPerChunk = 20;

      for (var chunk = 1; chunk <= 15; chunk++) {
        // Target user takes (20 / 80) * 60 = 15.0 seconds to write this chunk
        final userActualWriteSeconds = (graphemesPerChunk / targetLpm) * 60.0;

        // App planned gap for current estimated LPM
        final appPlannedGap = (graphemesPerChunk / loop.currentLpm) * 60.0;

        // User finishes early at userActualWriteSeconds and taps Next early
        expect(userActualWriteSeconds, lessThan(appPlannedGap));
        final log = loop.onNextEarly(
          plannedGapSeconds: appPlannedGap,
          elapsedGapSeconds: userActualWriteSeconds,
          chunkIndex: chunk,
        );

        lpmHistory.add(log.newLpm);
      }

      // 1. Verify strictly monotonic convergence (no oscillation)
      for (var i = 1; i < lpmHistory.length; i++) {
        final prev = lpmHistory[i - 1];
        final curr = lpmHistory[i];
        expect(
          curr,
          greaterThan(prev),
          reason: 'LPM should strictly increase towards 80 at step $i without oscillating backwards ($prev -> $curr)',
        );
        expect(
          curr,
          lessThanOrEqualTo(targetLpm),
          reason: 'LPM should never overshoot target 80 LPM ($curr)',
        );
      }

      // 2. Verify convergence within 15 chunks (converges to within ~2.5 LPM of 80 LPM / >97% accuracy)
      final finalLpm = loop.currentLpm;
      expect((finalLpm - targetLpm).abs(), lessThan(2.5),
          reason: 'LPM should converge to ~80 LPM within 15 chunks (reached $finalLpm)');
      expect(loop.history.length, equals(15));
    });

    test('Simulating user writing at 20 LPM converges within 15 chunks without oscillating', () {
      const targetLpm = 20.0;
      const initialLpm = 40.0;
      final loop = PacingFeedbackLoop(
        initialLpm: initialLpm,
        config: const PacingFeedbackConfig(
          initialAlpha: 0.25,
          minAlpha: 0.05,
        ),
      );

      final lpmHistory = <double>[initialLpm];
      final graphemesPerChunk = 20;

      for (var chunk = 1; chunk <= 15; chunk++) {
        // Target user takes (20 / 20) * 60 = 60.0 seconds to write this chunk
        final userActualWriteSeconds = (graphemesPerChunk / targetLpm) * 60.0;

        // App planned gap for current estimated LPM
        final appPlannedGap = (graphemesPerChunk / loop.currentLpm) * 60.0;

        // User needs more time: finishes writing after waiting extra time
        final extraWaitNeeded = userActualWriteSeconds - appPlannedGap;
        expect(extraWaitNeeded, greaterThanOrEqualTo(0.0));

        final log = loop.onWait(
          plannedGapSeconds: appPlannedGap,
          extraWaitSeconds: extraWaitNeeded,
          chunkIndex: chunk,
        );

        lpmHistory.add(log.newLpm);
      }

      // 1. Verify strictly monotonic convergence (no oscillation)
      for (var i = 1; i < lpmHistory.length; i++) {
        final prev = lpmHistory[i - 1];
        final curr = lpmHistory[i];
        expect(
          curr,
          lessThan(prev),
          reason: 'LPM should strictly decrease towards 20 at step $i without oscillating forwards ($prev -> $curr)',
        );
        expect(
          curr,
          greaterThanOrEqualTo(targetLpm),
          reason: 'LPM should never undershoot target 20 LPM ($curr)',
        );
      }

      // 2. Verify convergence within 15 chunks (within 1 LPM / >98% accuracy)
      final finalLpm = loop.currentLpm;
      expect((finalLpm - targetLpm).abs(), lessThan(1.0),
          reason: 'LPM should converge to ~20 LPM within 15 chunks (reached $finalLpm)');
      expect(loop.history.length, equals(15));
    });

    test('Simulating user writing at 40 LPM stays stable and locks after 6 chunks', () {
      const targetLpm = 40.0;
      final loop = PacingFeedbackLoop(
        initialLpm: targetLpm,
        config: const PacingFeedbackConfig(
          initialAlpha: 0.25,
          minAlpha: 0.05,
          lockConsecutiveChunksThreshold: 6,
        ),
      );

      expect(loop.isLocked, isFalse);

      for (var chunk = 1; chunk <= 15; chunk++) {
        // User is comfortable: no action taken during gap
        final log = loop.onNoAction(chunkIndex: chunk);
        expect(log.newLpm, equals(targetLpm));

        if (chunk < 6) {
          expect(loop.isLocked, isFalse);
          expect(loop.consecutiveConsistentChunks, equals(chunk));
        } else {
          expect(loop.isLocked, isTrue);
          expect(loop.currentAlpha, equals(0.05));
        }
      }

      expect(loop.currentLpm, equals(targetLpm));
      expect(loop.isLocked, isTrue);
      expect(loop.currentAlpha, equals(0.05));
    });
  });

  group('Alpha Scheduling and Locking', () {
    test('Alpha decays toward minAlpha as corrections get consistent and pins at minAlpha when locked', () {
      final loop = PacingFeedbackLoop(
        initialLpm: 45.0,
        config: const PacingFeedbackConfig(
          initialAlpha: 0.25,
          minAlpha: 0.05,
          alphaDecayRate: 0.85,
          lockConsecutiveChunksThreshold: 6,
        ),
      );

      expect(loop.currentAlpha, equals(0.25));

      // 3 chunks of promptJustRight (consistent)
      loop.onPromptResponse(PacingSignalType.promptJustRight);
      expect(loop.currentAlpha, closeTo(0.25 * 0.85, 0.001));

      loop.onPromptResponse(PacingSignalType.promptJustRight);
      expect(loop.currentAlpha, closeTo(0.25 * 0.85 * 0.85, 0.001));

      loop.onPromptResponse(PacingSignalType.promptJustRight);
      expect(loop.currentAlpha, closeTo(0.25 * 0.85 * 0.85 * 0.85, 0.001));

      // 4th, 5th, 6th chunks
      loop.onNoAction();
      loop.onNoAction();
      loop.onNoAction(); // 6th consistent chunk

      expect(loop.isLocked, isTrue);
      expect(loop.currentAlpha, equals(0.05));

      // Further chunks keep adapting at low alpha
      loop.onNextEarly(plannedGapSeconds: 10.0, elapsedGapSeconds: 8.0);
      expect(loop.currentAlpha, equals(0.05));
      expect(loop.isLocked, isTrue);
    });

    test('Manual correction resets consecutiveConsistentChunks before pace is locked', () {
      final loop = PacingFeedbackLoop(
        initialLpm: 45.0,
        config: const PacingFeedbackConfig(
          lockConsecutiveChunksThreshold: 6,
        ),
      );

      loop.onNoAction();
      loop.onNoAction();
      loop.onNoAction();
      expect(loop.consecutiveConsistentChunks, equals(3));
      expect(loop.isLocked, isFalse);

      // Manual repeat correction
      loop.onRepeat();
      expect(loop.consecutiveConsistentChunks, equals(0));
      expect(loop.isLocked, isFalse);
    });
  });

  group('In-session UI Prompt Schedule', () {
    test('Prompts after first 5 chunks, then every 20 chunks until locked', () {
      final loop = PacingFeedbackLoop(
        initialLpm: 45.0,
        config: const PacingFeedbackConfig(
          promptFirstChunkInterval: 5,
          promptSubsequentChunkInterval: 20,
        ),
      );

      expect(loop.shouldShowPacePrompt(1), isFalse);
      expect(loop.shouldShowPacePrompt(4), isFalse);
      expect(loop.shouldShowPacePrompt(5), isTrue); // First 5 chunks
      expect(loop.shouldShowPacePrompt(6), isFalse);
      expect(loop.shouldShowPacePrompt(24), isFalse);
      expect(loop.shouldShowPacePrompt(25), isTrue); // 5 + 20
      expect(loop.shouldShowPacePrompt(26), isFalse);
      expect(loop.shouldShowPacePrompt(45), isTrue); // 5 + 40
      expect(loop.shouldShowPacePrompt(65), isTrue); // 5 + 60
    });

    test('Prompt is never shown once pace is locked', () {
      final loop = PacingFeedbackLoop(
        initialLpm: 45.0,
        config: const PacingFeedbackConfig(
          lockConsecutiveChunksThreshold: 6,
          promptFirstChunkInterval: 5,
          promptSubsequentChunkInterval: 20,
        ),
      );

      // Lock pace with 6 consistent chunks
      for (var i = 0; i < 6; i++) {
        loop.onNoAction();
      }
      expect(loop.isLocked, isTrue);

      // Even on prompt intervals, prompt should not show once locked
      expect(loop.shouldShowPacePrompt(5), isFalse);
      expect(loop.shouldShowPacePrompt(25), isFalse);
      expect(loop.shouldShowPacePrompt(45), isFalse);
    });
  });

  group('Pacing Signals and Corrections', () {
    test('Repeat and Slower signals decrease LPM', () {
      final loop = PacingFeedbackLoop(initialLpm: 50.0);

      final logRepeat = loop.onRepeat();
      expect(logRepeat.observedRatio, equals(0.80));
      expect(logRepeat.newLpm, lessThan(50.0));

      final lpmAfterRepeat = loop.currentLpm;
      final logSlower = loop.onSlower();
      expect(logSlower.observedRatio, equals(0.85));
      expect(logSlower.newLpm, lessThan(lpmAfterRepeat));
    });

    test('Prompt buttons Too Slow, Just Right, and Too Fast adjust LPM appropriately', () {
      final loop = PacingFeedbackLoop(initialLpm: 50.0);

      // 'Too slow' means the dictation is too slow for the user (i.e. user writes faster -> increase LPM)
      // or if prompt is "Pace OK?":
      // "Too slow" -> user wants faster dictation (LPM increases)
      // "Too fast" -> user wants slower dictation (LPM decreases)
      final logTooFast = loop.onPromptResponse(PacingSignalType.promptTooFast);
      expect(logTooFast.newLpm, greaterThan(50.0));

      final beforeTooSlow = loop.currentLpm;
      final logTooSlow = loop.onPromptResponse(PacingSignalType.promptTooSlow);
      expect(logTooSlow.newLpm, lessThan(beforeTooSlow));

      final beforeJustRight = loop.currentLpm;
      final logJustRight = loop.onPromptResponse(PacingSignalType.promptJustRight);
      expect(logJustRight.newLpm, equals(beforeJustRight));
    });

    test('Next early with speech duration and overlap computes accurate observed ratio', () {
      final loop = PacingFeedbackLoop(initialLpm: 40.0);

      // Planned gap = 10s, speech = 4s, overlap = 0.5 -> total planned = 10 + 2 = 12s
      // User pressed Next at 4s into gap -> total observed = 4 + 2 = 6s
      // Observed ratio = 12 / 6 = 2.0
      final log = loop.onNextEarly(
        plannedGapSeconds: 10.0,
        elapsedGapSeconds: 4.0,
        speechDurationSeconds: 4.0,
        overlapFactor: 0.5,
      );

      expect(log.observedRatio, equals(2.0));
      expect(log.newLpm, equals(40.0 * (1.0 + 0.25 * (2.0 - 1.0))));
    });
  });
}
