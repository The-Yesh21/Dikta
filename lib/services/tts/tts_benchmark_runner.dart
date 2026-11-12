import 'dart:async';
import 'dart:io';
import 'kokoro_engine.dart';
import 'model_locator.dart';

/// Single execution measurement from the TTS benchmark.
class BenchmarkRecord {
  const BenchmarkRecord({
    required this.phraseLabel,
    required this.text,
    required this.threads,
    required this.runNumber,
    required this.isCold,
    required this.synthesisTimeMs,
    required this.audioDurationSeconds,
    required this.realTimeFactor,
  });

  final String phraseLabel;
  final String text;
  final int threads;
  final int runNumber;
  final bool isCold;
  final int synthesisTimeMs;
  final double audioDurationSeconds;
  final double realTimeFactor;

  @override
  String toString() {
    final mode = isCold ? 'COLD' : 'WARM';
    return '$phraseLabel ($threads threads | Run #$runNumber $mode): ${synthesisTimeMs}ms, '
        'Audio: ${audioDurationSeconds.toStringAsFixed(2)}s, '
        'RTF: ${realTimeFactor.toStringAsFixed(2)}x';
  }
}

/// Results container for an on-device benchmark suite.
class BenchmarkSuiteResult {
  const BenchmarkSuiteResult({
    required this.records,
    required this.modelLoadTime2ThreadsMs,
    required this.modelLoadTime4ThreadsMs,
    required this.modelPath,
    required this.isInt8,
  });

  final List<BenchmarkRecord> records;
  final int modelLoadTime2ThreadsMs;
  final int modelLoadTime4ThreadsMs;
  final String modelPath;
  final bool isInt8;
}

/// Orchestrator for on-device TTS performance benchmarking.
class TtsBenchmarkRunner {
  const TtsBenchmarkRunner({required this.modelPaths});

  final KokoroModelPaths modelPaths;

  static const testPhrases = <String, String>{
    '3-word chunk': 'Mitochondria generate energy.',
    '5-word chunk': 'Mitochondria are membrane-bound cell organelles.',
    '8-word chunk': 'Glucose and oxygen are converted into carbon dioxide.',
    'Full sentence':
        'Mitochondria are membrane-bound cell organelles that generate most of the chemical energy needed to power the biochemical reactions of the cell.',
  };

  /// Executes full benchmark matrix: 2 threads vs 4 threads, cold vs warm, 3 runs each.
  Stream<String> runBenchmark({
    required void Function(BenchmarkSuiteResult result) onComplete,
  }) async* {
    final records = <BenchmarkRecord>[];
    int loadTime2Threads = 0;
    int loadTime4Threads = 0;

    for (final threads in [2, 4]) {
      yield 'Loading Kokoro model ($threads threads, isInt8: ${modelPaths.isInt8})...';
      print('[BENCHMARK] Loading Kokoro model with $threads threads...');

      final engine = KokoroEngine();
      final loadWatch = Stopwatch()..start();
      await engine.init(modelPaths, numThreads: threads);
      loadWatch.stop();

      final loadMs = loadWatch.elapsedMilliseconds;
      if (threads == 2) {
        loadTime2Threads = loadMs;
      } else {
        loadTime4Threads = loadMs;
      }

      yield 'Model loaded in ${loadMs}ms. Running phrase benchmarks...';
      print('[BENCHMARK] Model loaded in ${loadMs}ms ($threads threads)');

      for (final entry in testPhrases.entries) {
        final label = entry.key;
        final text = entry.value;

        for (var run = 1; run <= 3; run++) {
          final isCold = (run == 1 && label == testPhrases.keys.first);
          yield 'Synthesizing "$label" (Threads: $threads, Run #$run)...';

          final synthWatch = Stopwatch()..start();
          final audio = await engine.synthesize(text);
          synthWatch.stop();

          final synthMs = synthWatch.elapsedMilliseconds;
          final durationSec = audio.durationSeconds;
          final rtf = (synthMs / 1000.0) / (durationSec > 0 ? durationSec : 0.001);

          final record = BenchmarkRecord(
            phraseLabel: label,
            text: text,
            threads: threads,
            runNumber: run,
            isCold: isCold,
            synthesisTimeMs: synthMs,
            audioDurationSeconds: durationSec,
            realTimeFactor: rtf,
          );
          records.add(record);

          print('[BENCHMARK] $record');
          yield 'Done: $record';
        }
      }

      await engine.dispose();
      yield 'Completed $threads-thread benchmark pass.\n';
    }

    final suiteResult = BenchmarkSuiteResult(
      records: records,
      modelLoadTime2ThreadsMs: loadTime2Threads,
      modelLoadTime4ThreadsMs: loadTime4Threads,
      modelPath: modelPaths.modelPath,
      isInt8: modelPaths.isInt8,
    );

    onComplete(suiteResult);
  }
}
