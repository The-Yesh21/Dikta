import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dictation_app/config/pacing_config.dart';
import 'package:dictation_app/core/chunker/chunk_info.dart';
import 'package:dictation_app/core/pacing/pacing_engine.dart';
import 'package:dictation_app/services/audio/dictation_playback_controller.dart';
import 'package:dictation_app/services/audio/temp_audio_file_manager.dart';
import 'package:dictation_app/services/tts/voice_engine.dart';

class FakeVoiceEngine implements VoiceEngine {
  int synthesizeCallCount = 0;
  final List<String> synthesizedTexts = [];
  final List<double> synthesizedSpeeds = [];
  final List<int> synthesizedSpeakerIds = [];

  @override
  Future<void> init(dynamic paths, {int numThreads = 4}) async {}

  bool shouldThrow = false;
  Exception? throwException;

  @override
  Future<GeneratedAudio> synthesize(
    String text, {
    int speakerId = 0,
    String? voice,
    String? language,
    double speed = 1.0,
  }) async {
    if (shouldThrow) {
      throw throwException ?? Exception('Simulated network error');
    }
    synthesizeCallCount++;
    synthesizedTexts.add(text);
    synthesizedSpeeds.add(speed);
    synthesizedSpeakerIds.add(speakerId);
    return GeneratedAudio(
      samples: Float32List(1600),
      sampleRate: 16000,
      durationSeconds: 0.1,
    );
  }

  @override
  int get numSpeakers => 11;

  @override
  bool get isReady => true;

  @override
  Future<void> dispose() async {}
}

class FakeTempAudioFileManager extends TempAudioFileManager {
  final List<String> createdFiles = [];
  final List<String> deletedFiles = [];

  @override
  Future<String> writeTempWave({
    required Float32List samples,
    required int sampleRate,
    required int chunkIndex,
  }) async {
    final path = '/mock/temp/chunk_$chunkIndex.wav';
    createdFiles.add(path);
    return path;
  }

  @override
  Future<void> deleteTempWave(String filePath) async {
    deletedFiles.add(filePath);
  }

  @override
  Future<void> cleanupAll() async {
    deletedFiles.addAll(createdFiles);
  }
}

class FakeDictationAudioPlayer implements DictationAudioPlayer {
  final _completeController = StreamController<void>.broadcast();
  final List<String> playedFiles = [];
  bool isDisposed = false;

  @override
  Stream<void> get onPlayerComplete => _completeController.stream;

  @override
  Future<void> play(String filePath) async {
    playedFiles.add(filePath);
    scheduleMicrotask(() {
      if (!_completeController.isClosed) {
        _completeController.add(null);
      }
    });
  }

  @override
  Future<void> playBytes(Uint8List bytes) async {
    playedFiles.add('bytes:${bytes.length}');
    scheduleMicrotask(() {
      if (!_completeController.isClosed) {
        _completeController.add(null);
      }
    });
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    isDisposed = true;
    await _completeController.close();
  }
}

void main() {
  group('DictationPlaybackController Sequence & Safety Tests', () {
    test('never skips or reorders chunks and logs each chunk execution', () async {
      final fakeEngine = FakeVoiceEngine();
      final fakeTempManager = FakeTempAudioFileManager();
      final fakePlayer = FakeDictationAudioPlayer();
      final pacingEngine = PacingEngine(
        config: const PacingConfig(
          minGapSeconds: 0.01,
          secondsPerGraphemeLatin: 0.001,
          defaultWritingSpeed: 100.0,
        ),
      );

      final controller = DictationPlaybackController(
        voiceEngine: fakeEngine,
        pacingEngine: pacingEngine,
        audioPlayer: fakePlayer,
        tempFileManager: fakeTempManager,
        config: const PacingConfig(
          minGapSeconds: 0.01,
          secondsPerGraphemeLatin: 0.001,
          defaultWritingSpeed: 100.0,
        ),
      );

      final chunks = [
        const ChunkInfo(index: 0, text: 'First chunk', wordCount: 2, boundaryType: BoundaryType.comma),
        const ChunkInfo(index: 1, text: 'Second chunk', wordCount: 2, boundaryType: BoundaryType.none),
        const ChunkInfo(index: 2, text: 'Third chunk', wordCount: 2, boundaryType: BoundaryType.sentence),
      ];

      await controller.start(chunks);

      expect(fakeEngine.synthesizedTexts, [
        'First chunk',
        'Second chunk',
        'Third chunk',
      ]);
      expect(fakePlayer.playedFiles.length, 3);
      expect(controller.sessionLogs.length, 3);
      expect(controller.state, DictationPlaybackState.completed);
    });

    test('BUG REGRESSION: Every chunk is followed by a gap, regardless of boundary type', () async {
      final fakeEngine = FakeVoiceEngine();
      final fakeTempManager = FakeTempAudioFileManager();
      final fakePlayer = FakeDictationAudioPlayer();
      final pacingEngine = PacingEngine(
        config: const PacingConfig(
          minGapSeconds: 0.01,
          secondsPerGraphemeLatin: 0.001,
          defaultWritingSpeed: 100.0,
        ),
      );

      final controller = DictationPlaybackController(
        voiceEngine: fakeEngine,
        pacingEngine: pacingEngine,
        audioPlayer: fakePlayer,
        tempFileManager: fakeTempManager,
        config: const PacingConfig(
          minGapSeconds: 0.01,
          secondsPerGraphemeLatin: 0.001,
          defaultWritingSpeed: 100.0,
        ),
      );

      // Chunks explicitly include BoundaryType.none without punctuation
      final chunks = [
        const ChunkInfo(index: 0, text: 'Mitochondria are membrane-bound', wordCount: 3, boundaryType: BoundaryType.none),
        const ChunkInfo(index: 1, text: 'cell organelles producing', wordCount: 3, boundaryType: BoundaryType.none),
        const ChunkInfo(index: 2, text: 'cellular energy,', wordCount: 2, boundaryType: BoundaryType.comma),
        const ChunkInfo(index: 3, text: 'stored in ATP.', wordCount: 3, boundaryType: BoundaryType.sentence),
      ];

      final recordedStates = <DictationPlaybackState>[];
      final stateSub = controller.onStateChanged.listen((state) {
        recordedStates.add(state);
      });

      await controller.start(chunks);
      await stateSub.cancel();

      // Verify every chunk has a positive gap computed by PacingEngine
      for (var i = 0; i < controller.sessionLogs.length; i++) {
        final log = controller.sessionLogs[i];
        expect(
          log.gapSeconds,
          greaterThan(0.0),
          reason: 'Chunk #${log.chunkIndex} (${log.boundaryType}) played without a gap!',
        );
      }

      // Check state transitions:
      // Count how many times waitingGap state was entered.
      // Every chunk (all 4) is followed by waitingGap so the user has time to copy it down.
      final waitingGapCount = recordedStates.where((s) => s == DictationPlaybackState.waitingGap).length;
      expect(
        waitingGapCount,
        equals(4),
        reason: 'Expected 4 waitingGap states for the 4 chunks, but found $waitingGapCount',
      );
    });

    test('Per-chunk speech speed scaling slows down chunks with long technical words', () async {
      final fakeEngine = FakeVoiceEngine();
      final fakeTempManager = FakeTempAudioFileManager();
      final fakePlayer = FakeDictationAudioPlayer();
      final pacingEngine = PacingEngine(
        config: const PacingConfig(
          kokoroSpeed: 0.8,
          longWordCharThreshold: 6.0,
          longWordSpeedScale: 0.85,
          minGapSeconds: 0.01,
          secondsPerGraphemeLatin: 0.001,
          defaultWritingSpeed: 100.0,
        ),
      );

      final controller = DictationPlaybackController(
        voiceEngine: fakeEngine,
        pacingEngine: pacingEngine,
        audioPlayer: fakePlayer,
        tempFileManager: fakeTempManager,
        speakerId: 7, // British Female (bf_emma)
        config: const PacingConfig(
          kokoroSpeed: 0.8,
          longWordCharThreshold: 6.0,
          longWordSpeedScale: 0.85,
          minGapSeconds: 0.01,
          secondsPerGraphemeLatin: 0.001,
          defaultWritingSpeed: 100.0,
        ),
      );

      final chunks = [
        // Short/normal words -> average char count < 6.0 -> speed = 0.8
        const ChunkInfo(index: 0, text: 'This is a normal note', wordCount: 5, boundaryType: BoundaryType.none),
        // Long technical words -> average char count >= 6.0 -> speed = 0.8 * 0.85 = 0.68
        const ChunkInfo(index: 1, text: 'electrochemical phosphorylation reactions', wordCount: 3, boundaryType: BoundaryType.sentence),
      ];

      await controller.start(chunks);

      expect(fakeEngine.synthesizedSpeeds.length, 2);
      expect(fakeEngine.synthesizedSpeeds[0], closeTo(0.8, 1e-4));
      expect(fakeEngine.synthesizedSpeeds[1], closeTo(0.68, 1e-4));
      expect(fakeEngine.synthesizedSpeakerIds[0], 7);
      expect(fakeEngine.synthesizedSpeakerIds[1], 7);

      expect(controller.sessionLogs[0].voiceSpeed, closeTo(0.8, 1e-4));
      expect(controller.sessionLogs[1].voiceSpeed, closeTo(0.68, 1e-4));
    });

    test('Tap-to-advance (skipGap) skips remaining gap and adapts writing speed faster', () async {
      final fakeEngine = FakeVoiceEngine();
      final fakeTempManager = FakeTempAudioFileManager();
      final fakePlayer = FakeDictationAudioPlayer();
      final pacingEngine = PacingEngine(
        config: const PacingConfig(
          defaultWritingSpeed: 0.7,
          minGapSeconds: 5.0, // Large gap to ensure it stays in waitingGap
        ),
      );

      final controller = DictationPlaybackController(
        voiceEngine: fakeEngine,
        pacingEngine: pacingEngine,
        audioPlayer: fakePlayer,
        tempFileManager: fakeTempManager,
      );

      final chunks = [
        const ChunkInfo(index: 0, text: 'First phrase', wordCount: 2, boundaryType: BoundaryType.none),
        const ChunkInfo(index: 1, text: 'Second phrase.', wordCount: 2, boundaryType: BoundaryType.sentence),
      ];

      final initialSpeed = pacingEngine.currentWritingSpeed;

      // Listen for waitingGap state, then immediately trigger skipGap()
      controller.onStateChanged.listen((state) {
        if (state == DictationPlaybackState.waitingGap) {
          scheduleMicrotask(() {
            controller.skipGap();
          });
        }
      });

      final watch = Stopwatch()..start();
      await controller.start(chunks);
      watch.stop();

      // Ensure that 5-second gap was skipped (completed in less than 2 seconds)
      expect(watch.elapsedMilliseconds, lessThan(2000));
      // Ensure adaptFaster() was called
      expect(pacingEngine.currentWritingSpeed, greaterThan(initialSpeed));
      expect(controller.state, DictationPlaybackState.completed);
    });

    test('session log captures per-chunk synthesis time, speed, and gap metrics', () {
      const log = DictationSessionLog(
        chunkIndex: 0,
        text: 'Hello test',
        wordCount: 2,
        boundaryType: BoundaryType.comma,
        synthesisTimeMs: 125,
        audioDurationSeconds: 1.5,
        realTimeFactor: 0.08,
        gapSeconds: 2.4,
        voiceSpeed: 0.8,
      );

      expect(log.chunkIndex, 0);
      expect(log.synthesisTimeMs, 125);
      expect(log.audioDurationSeconds, 1.5);
      expect(log.gapSeconds, 2.4);
      expect(log.voiceSpeed, 0.8);
      expect(log.toString(), contains('Synth: 125ms'));
      expect(log.toString(), contains('Speed: 0.80x'));
      expect(log.toString(), contains('Gap: 2.40s'));
    });

    test('FAILURE HANDLING: Never skips or reorders chunks on synthesis error, and retries the same chunk', () async {
      final fakeEngine = FakeVoiceEngine();
      final pacingEngine = PacingEngine();
      final fakePlayer = FakeDictationAudioPlayer();
      final fakeFileManager = FakeTempAudioFileManager();

      final controller = DictationPlaybackController(
        voiceEngine: fakeEngine,
        pacingEngine: pacingEngine,
        audioPlayer: fakePlayer,
        tempFileManager: fakeFileManager,
      );

      final chunks = [
        const ChunkInfo(text: 'First chunk', index: 0, wordCount: 2, boundaryType: BoundaryType.none),
        const ChunkInfo(text: 'Second chunk', index: 1, wordCount: 2, boundaryType: BoundaryType.sentence),
      ];

      // Simulate network failure on chunk 0
      fakeEngine.shouldThrow = true;
      fakeEngine.throwException = Exception('Gnani network timeout');

      await controller.start(chunks);

      // State must be error, and currentChunkIndex must remain 0 (not skipped)
      expect(controller.state, DictationPlaybackState.error);
      expect(controller.currentChunkIndex, 0);
      expect(controller.errorMessage, contains('Gnani network timeout'));
      expect(fakePlayer.playedFiles, isEmpty);

      // Now restore network connection and retry
      fakeEngine.shouldThrow = false;
      await controller.retryCurrentChunk();

      // Ensure playback finished successfully and both chunks played in exact sequential order
      expect(controller.state, DictationPlaybackState.completed);
      expect(fakePlayer.playedFiles.length, 2);
      expect(fakePlayer.playedFiles[0], '/mock/temp/chunk_0.wav');
      expect(fakePlayer.playedFiles[1], '/mock/temp/chunk_1.wav');
      expect(fakeEngine.synthesizedTexts, ['First chunk', 'Second chunk']);
    });
  });
}
