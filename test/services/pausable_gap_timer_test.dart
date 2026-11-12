import 'package:flutter_test/flutter_test.dart';
import 'package:dictation_app/services/audio/pausable_gap_timer.dart';

void main() {
  group('PausableGapTimer Tests', () {
    test('completes when duration expires', () async {
      final timer = PausableGapTimer(
        totalDuration: const Duration(milliseconds: 100),
        tickInterval: const Duration(milliseconds: 20),
      );

      final watch = Stopwatch()..start();
      await timer.run();
      watch.stop();

      expect(timer.remainingDuration, Duration.zero);
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(90));
    });

    test('pause stops countdown and resume completes remaining duration', () async {
      final timer = PausableGapTimer(
        totalDuration: const Duration(milliseconds: 200),
        tickInterval: const Duration(milliseconds: 20),
      );

      final runFuture = timer.run();

      // Let it run for 60ms
      await Future<void>.delayed(const Duration(milliseconds: 60));
      timer.pause();

      final remainingAfterPause = timer.remainingDuration;
      expect(remainingAfterPause.inMilliseconds, lessThan(180));
      expect(remainingAfterPause.inMilliseconds, greaterThan(80));

      // Wait 50ms while paused, verify remaining doesn't change
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(timer.remainingDuration.inMilliseconds, closeTo(remainingAfterPause.inMilliseconds, 10));

      // Resume
      timer.resume();
      await runFuture;

      expect(timer.remainingDuration, Duration.zero);
    });

    test('cancel completes future immediately', () async {
      final timer = PausableGapTimer(
        totalDuration: const Duration(seconds: 10),
      );

      final runFuture = timer.run();
      timer.cancel();

      await runFuture;
      expect(timer.isRunning, isFalse);
    });
  });
}
