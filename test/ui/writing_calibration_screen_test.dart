import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dictation_app/core/pacing/pacing_engine.dart';
import 'package:dictation_app/services/audio/dictation_playback_controller.dart';
import 'package:dictation_app/services/storage/user_pacing_storage.dart';
import 'package:dictation_app/services/tts/voice_engine.dart';
import 'package:dictation_app/ui/screens/writing_calibration_screen.dart';

class TestVoiceEngine implements VoiceEngine {
  @override
  Future<GeneratedAudio> synthesize(
    String text, {
    int speakerId = 0,
    String? voice,
    String? language,
    double speed = 1.0,
  }) async {
    return const GeneratedAudio(
      samples: null,
      sampleRate: 16000,
      durationSeconds: 0.05,
      audioFilePath: '/test/audio.wav',
    );
  }

  @override
  int get numSpeakers => 1;

  @override
  Future<void> dispose() async {}
}

class TestAudioPlayer implements DictationAudioPlayer {
  final _completeController = StreamController<void>.broadcast();

  @override
  Stream<void> get onPlayerComplete => _completeController.stream;

  @override
  Future<void> play(String filePath) async {
    _completeController.add(null);
  }

  @override
  Future<void> playBytes(Uint8List bytes) async {
    _completeController.add(null);
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _completeController.close();
  }
}

void main() {
  group('WritingCalibrationScreen', () {
    late UserPacingStorageService storage;
    late TestVoiceEngine voiceEngine;
    late TestAudioPlayer audioPlayer;

    setUp(() {
      storage = UserPacingStorageService(inMemory: true);
      voiceEngine = TestVoiceEngine();
      audioPlayer = TestAudioPlayer();
    });

    tearDown(() async {
      await audioPlayer.dispose();
    });

    testWidgets('Step 1: Pick language, Step 2: Pick age group, Step 3: Dictation calibration flow', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      double? receivedLpm;
      double? receivedSecPerGrapheme;
      ScriptType? receivedScript;

      await tester.pumpWidget(
        MaterialApp(
          home: WritingCalibrationScreen(
            language: 'en-IN',
            storageService: storage,
            voiceEngine: voiceEngine,
            audioPlayer: audioPlayer,
            onLpmCalibrated: (script, lpm) {
              receivedScript = script;
              receivedLpm = lpm;
            },
            onSpeedCalibrated: (script, secPerGrapheme) {
              receivedSecPerGrapheme = secPerGrapheme;
            },
          ),
        ),
      );

      // Verify Step 1: Language selection
      expect(find.text('Step 1: Pick Language'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Hindi'), findsOneWidget);
      expect(find.text('Kannada'), findsOneWidget);

      // Tap Next to Step 2
      final nextAgeBtn = find.text('Next: Choose Age Group');
      await tester.ensureVisible(nextAgeBtn);
      await tester.tap(nextAgeBtn);
      await tester.pumpAndSettle();

      // Verify Step 2: Age group selection & starting LPM fallbacks
      expect(find.text('Step 2: Pick Age Group (Optional)'), findsOneWidget);
      expect(find.text('Age 8-10'), findsOneWidget);
      expect(find.text('Age 11-13'), findsOneWidget);
      expect(find.text('Age 14-17'), findsOneWidget);
      expect(find.text('Age 18+'), findsOneWidget);

      // Select Age 11-13
      final ageCard = find.text('Age 11-13');
      await tester.ensureVisible(ageCard);
      await tester.tap(ageCard);
      await tester.pumpAndSettle();

      // Proceed to Step 3: Dictation
      final nextDictBtn = find.text('Next: Calibrate via Dictation');
      await tester.ensureVisible(nextDictBtn);
      await tester.tap(nextDictBtn);
      await tester.pumpAndSettle();

      expect(find.text('Sentence 1 of 2'), findsOneWidget);
      expect(find.text('Listen & Dictate Sentence 1'), findsOneWidget);

      // Tap Listen & Dictate Sentence 1
      final dictateBtn1 = find.text('Listen & Dictate Sentence 1');
      await tester.ensureVisible(dictateBtn1);
      await tester.tap(dictateBtn1);
      await tester.pump();

      // Wait for audio synthesis & playback completion
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // Writing timer active
      final doneBtn1 = find.text('Done Writing');
      await tester.ensureVisible(doneBtn1);
      expect(doneBtn1, findsOneWidget);

      // Advance writing clock
      await tester.pump(const Duration(seconds: 2));

      // Done writing sentence 1 (cancels timer for sentence 1)
      await tester.tap(doneBtn1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Sentence 2 displayed
      expect(find.text('Sentence 2 of 2'), findsOneWidget);
      final dictateBtn2 = find.text('Listen & Dictate Sentence 2');
      await tester.ensureVisible(dictateBtn2);
      expect(dictateBtn2, findsOneWidget);

      // Tap Listen & Dictate Sentence 2
      await tester.tap(dictateBtn2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // Writing Sentence 2
      final doneBtn2 = find.text('Done Writing');
      await tester.ensureVisible(doneBtn2);
      expect(doneBtn2, findsOneWidget);
      await tester.pump(const Duration(seconds: 2));

      // Done writing sentence 2 (cancels timer)
      await tester.tap(doneBtn2);
      await tester.pump();
      await tester.pumpAndSettle();



      // Step 4: Completion screen
      expect(find.text('Calibration Completed!'), findsOneWidget);
      expect(find.textContaining('Average Calibrated Pace:'), findsOneWidget);

      // Verify callback outputs
      expect(receivedScript, ScriptType.latin);
      expect(receivedLpm, isNotNull);
      expect(receivedLpm! > 0, isTrue);
      expect(receivedSecPerGrapheme, isNotNull);

      // Verify persistence in local storage
      final savedLpm = await storage.getCalibratedLpm(script: ScriptType.latin);
      expect(savedLpm, isNotNull);
      expect(savedLpm, equals(receivedLpm));

      final profile = await storage.getProfile();
      expect(profile?.ageGroup, '11-13');
    });

    testWidgets('Skip button applies age prior fallback and persists to storage', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool skipped = false;
      double? receivedLpm;

      await tester.pumpWidget(
        MaterialApp(
          home: WritingCalibrationScreen(
            language: 'hi-IN',
            storageService: storage,
            audioPlayer: audioPlayer,
            onSkip: () {
              skipped = true;
            },
            onLpmCalibrated: (script, lpm) {
              receivedLpm = lpm;
            },
          ),
        ),
      );

      // Tap Skip in AppBar
      final skipBtn = find.widgetWithText(TextButton, 'Skip');
      expect(skipBtn, findsOneWidget);
      await tester.tap(skipBtn);
      await tester.pumpAndSettle();

      expect(skipped, isTrue);
      // For 18+ (default), effective starting LPM is 60 * 0.8 = 48.0
      expect(receivedLpm, 48.0);

      // Check persistent storage
      final savedLpm = await storage.getCalibratedLpm(script: ScriptType.devanagari);
      expect(savedLpm, 48.0);
    });
  });
}
