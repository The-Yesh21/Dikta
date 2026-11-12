import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dictation_app/config/gnani_config.dart';
import 'package:dictation_app/services/tts/gnani_chunk_cache.dart';
import 'package:dictation_app/services/tts/gnani_tts_engine.dart';

/// Helper creating a minimal 44-byte RIFF WAV byte array for tests.
Uint8List createMockWavBytes({int sampleRate = 24000, int numSamples = 24000}) {
  final dataSize = numSamples * 2; // 16-bit mono = 2 bytes per sample
  final totalSize = 36 + dataSize;
  final bytes = ByteData(44 + dataSize);

  // 'RIFF'
  bytes.setUint8(0, 0x52);
  bytes.setUint8(1, 0x49);
  bytes.setUint8(2, 0x46);
  bytes.setUint8(3, 0x46);
  bytes.setUint32(4, totalSize, Endian.little);
  // 'WAVE'
  bytes.setUint8(8, 0x57);
  bytes.setUint8(9, 0x41);
  bytes.setUint8(10, 0x56);
  bytes.setUint8(11, 0x45);
  // 'fmt '
  bytes.setUint8(12, 0x66);
  bytes.setUint8(13, 0x6D);
  bytes.setUint8(14, 0x74);
  bytes.setUint8(15, 0x20);
  bytes.setUint32(16, 16, Endian.little); // Subchunk1Size
  bytes.setUint16(20, 1, Endian.little); // PCM format
  bytes.setUint16(22, 1, Endian.little); // Mono
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
  bytes.setUint16(32, 2, Endian.little); // BlockAlign
  bytes.setUint16(34, 16, Endian.little); // BitsPerSample
  // 'data'
  bytes.setUint8(36, 0x64);
  bytes.setUint8(37, 0x61);
  bytes.setUint8(38, 0x74);
  bytes.setUint8(39, 0x61);
  bytes.setUint32(40, dataSize, Endian.little);

  return bytes.buffer.asUint8List();
}

void main() {
  group('GnaniChunkCache Tests', () {
    late Directory tempDir;
    late GnaniChunkCache cache;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('gnani_cache_test_');
      cache = GnaniChunkCache(customBaseDir: tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('generates deterministic keys for identical parameters', () {
      final key1 = cache.generateKey(
        text: 'Hello world',
        voice: 'Shivani',
        language: 'en-IN',
        speed: 1.0,
        model: 'timbre-v3.0',
      );
      final key2 = cache.generateKey(
        text: 'Hello world',
        voice: 'Shivani',
        language: 'en-IN',
        speed: 1.0,
        model: 'timbre-v3.0',
      );
      final keyDifferentVoice = cache.generateKey(
        text: 'Hello world',
        voice: 'Avinash',
        language: 'en-IN',
        speed: 1.0,
        model: 'timbre-v3.0',
      );

      expect(key1, equals(key2));
      expect(key1, isNot(equals(keyDifferentVoice)));
    });

    test('saves and retrieves cached audio successfully', () async {
      final mockWav = createMockWavBytes(numSamples: 24000);

      // Initially null
      final initial = await cache.getCachedAudioPath(
        text: 'Sample test',
        voice: 'Shivani',
        language: 'en-IN',
        speed: 1.0,
        model: 'timbre-v3.0',
      );
      expect(initial, isNull);

      // Save
      final savedPath = await cache.saveCachedAudio(
        text: 'Sample test',
        wavBytes: mockWav,
        voice: 'Shivani',
        language: 'en-IN',
        speed: 1.0,
        model: 'timbre-v3.0',
      );
      expect(File(savedPath).existsSync(), isTrue);

      // Retrieve
      final retrieved = await cache.getCachedAudioPath(
        text: 'Sample test',
        voice: 'Shivani',
        language: 'en-IN',
        speed: 1.0,
        model: 'timbre-v3.0',
      );
      expect(retrieved, equals(savedPath));
      expect(await cache.getCachedCount(), equals(1));
    });

    test('clear removes all cached files', () async {
      final mockWav = createMockWavBytes();
      await cache.saveCachedAudio(
        text: 'Chunk 1',
        wavBytes: mockWav,
        voice: 'Shivani',
        language: 'en-IN',
        speed: 1.0,
        model: 'timbre-v3.0',
      );
      await cache.saveCachedAudio(
        text: 'Chunk 2',
        wavBytes: mockWav,
        voice: 'Shivani',
        language: 'en-IN',
        speed: 1.0,
        model: 'timbre-v3.0',
      );
      expect(await cache.getCachedCount(), equals(2));

      await cache.clear();
      expect(await cache.getCachedCount(), equals(0));
    });
  });

  group('GnaniTtsEngine Cache Integration & Failure Handling', () {
    late Directory tempDir;
    late GnaniChunkCache cache;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('gnani_engine_test_');
      cache = GnaniChunkCache(customBaseDir: tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns cached audio immediately without invoking network', () async {
      final mockWav = createMockWavBytes(numSamples: 24000); // exactly 1.0s audio
      await cache.saveCachedAudio(
        text: 'Cached sentence',
        wavBytes: mockWav,
        voice: 'Shivani',
        language: 'en-IN',
        speed: 1.0,
        model: 'timbre-v3.0',
      );

      final engine = GnaniTtsEngine(
        apiKey: 'test-key',
        cache: cache,
      );

      final audio = await engine.synthesize(
        'Cached sentence',
        voice: 'Shivani',
        language: 'en-IN',
        speed: 1.0,
        model: 'timbre-v3.0',
      );

      expect(audio.isFromCache, isTrue);
      expect(audio.durationSeconds, closeTo(1.0, 0.05));
      expect(audio.audioFilePath, isNotNull);
    });

    test('throws GnaniAuthException if API key is empty', () async {
      final engine = GnaniTtsEngine(
        apiKey: '',
        cache: cache,
      );

      expect(
        () => engine.synthesize('Hello world'),
        throwsA(isA<GnaniAuthException>()),
      );
    });
  });
}
