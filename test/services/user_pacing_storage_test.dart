import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dictation_app/core/pacing/pacing_engine.dart';
import 'package:dictation_app/services/storage/user_pacing_storage.dart';

void main() {
  group('UserPacingStorageService', () {
    late Directory tempDir;
    late File testFile;
    late UserPacingStorageService storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pacing_storage_test_');
      testFile = File('${tempDir.path}/test_profiles.json');
      storage = UserPacingStorageService(storageFile: testFile);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns null when profile does not exist', () async {
      final profile = await storage.getProfile(userId: 'user_123');
      expect(profile, isNull);

      final lpm = await storage.getCalibratedLpm(userId: 'user_123', script: ScriptType.latin);
      expect(lpm, isNull);
    });

    test('saves and loads full profile', () async {
      final profile = UserPacingProfile(
        userId: 'student_1',
        ageGroup: '11-13',
        calibratedLpm: {
          ScriptType.latin: 42.5,
          ScriptType.devanagari: 38.0,
        },
      );

      await storage.saveProfile(profile);

      final loaded = await storage.getProfile(userId: 'student_1');
      expect(loaded, isNotNull);
      expect(loaded!.userId, 'student_1');
      expect(loaded.ageGroup, '11-13');
      expect(loaded.calibratedLpm[ScriptType.latin], 42.5);
      expect(loaded.calibratedLpm[ScriptType.devanagari], 38.0);
      expect(loaded.lastUpdated, isNotNull);
    });

    test('saves and retrieves individual script LPM', () async {
      await storage.saveCalibratedLpm(
        userId: 'student_2',
        script: ScriptType.kannada,
        lpm: 35.5,
      );

      final lpm = await storage.getCalibratedLpm(
        userId: 'student_2',
        script: ScriptType.kannada,
      );
      expect(lpm, 35.5);

      // Other scripts still null
      final latinLpm = await storage.getCalibratedLpm(
        userId: 'student_2',
        script: ScriptType.latin,
      );
      expect(latinLpm, isNull);
    });

    test('updates age group without losing calibrated LPM', () async {
      await storage.saveCalibratedLpm(
        userId: 'student_3',
        script: ScriptType.latin,
        lpm: 50.0,
      );

      await storage.saveAgeGroup(
        userId: 'student_3',
        ageGroup: '14-17',
      );

      final profile = await storage.getProfile(userId: 'student_3');
      expect(profile, isNotNull);
      expect(profile!.ageGroup, '14-17');
      expect(profile.calibratedLpm[ScriptType.latin], 50.0);
    });

    test('handles corrupt json gracefully without crashing', () async {
      await testFile.writeAsString('{ invalid_json: ');
      final profile = await storage.getProfile(userId: 'any_user');
      expect(profile, isNull);
    });
  });
}
