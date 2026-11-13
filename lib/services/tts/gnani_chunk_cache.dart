import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// Local disk cache for synthesized TTS chunks.
///
/// Prevents redundant API requests when repeating phrases, rewinding,
/// or re-reading sections of text.
class GnaniChunkCache {
  GnaniChunkCache({Directory? customBaseDir}) : _customBaseDir = customBaseDir;

  final Directory? _customBaseDir;
  Directory? _cacheDir;

  /// Resolves or initializes the cache directory.
  Future<Directory> getCacheDirectory() async {
    if (_customBaseDir != null) {
      if (!await _customBaseDir!.exists()) {
        await _customBaseDir!.create(recursive: true);
      }
      return _customBaseDir!;
    }

    if (_cacheDir != null && await _cacheDir!.exists()) {
      return _cacheDir!;
    }

    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${baseDir.path}/gnani_tts_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  /// Generates a deterministic filename for the given synthesis parameters.
  String generateKey({
    required String text,
    required String voice,
    required String language,
    required double speed,
    required String model,
  }) {
    final normalizedText = text.trim();
    final speedStr = speed.toStringAsFixed(2);
    final raw = 'v3_s600|${language.toLowerCase()}|${model.toLowerCase()}|${voice.toLowerCase()}|$speedStr|$normalizedText';
    final bytes = utf8.encode(raw);
    
    // Simple 64-bit FNV-1a hash + length for collision resistance without external crypto package
    var hash = 0xcbf29ce484222325;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }

    // Combine hash with text prefix (sanitized)
    final safePrefix = normalizedText
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')
        .toLowerCase();
    final prefixSnippet = safePrefix.length > 20 ? safePrefix.substring(0, 20) : safePrefix;
    final hashHex = hash.toRadixString(16).padLeft(16, '0');

    return '${prefixSnippet}_$hashHex.wav';
  }

  /// Looks up cached audio for the given parameters. Returns file path if present, null otherwise.
  Future<String?> getCachedAudioPath({
    required String text,
    required String voice,
    required String language,
    required double speed,
    required String model,
  }) async {
    final dir = await getCacheDirectory();
    final fileName = generateKey(
      text: text,
      voice: voice,
      language: language,
      speed: speed,
      model: model,
    );
    final file = File('${dir.path}/$fileName');
    if (await file.exists() && await file.length() > 44) {
      final bytes = await file.readAsBytes();
      if (bytes.length >= 44 &&
          bytes[4] == 0xFF &&
          bytes[5] == 0xFF &&
          bytes[6] == 0xFF &&
          bytes[7] == 0xFF) {
        // Fix streaming placeholder in existing cached file
        final byteData = ByteData.sublistView(bytes);
        byteData.setUint32(4, bytes.length - 8, Endian.little);
        byteData.setUint32(40, bytes.length - 44, Endian.little);
        await file.writeAsBytes(bytes, flush: true);
      }
      return file.path;
    }
    return null;
  }

  /// Stores synthesized WAV bytes into the cache and returns the cached file path.
  Future<String> saveCachedAudio({
    required String text,
    required Uint8List wavBytes,
    required String voice,
    required String language,
    required double speed,
    required String model,
  }) async {
    final dir = await getCacheDirectory();
    final fileName = generateKey(
      text: text,
      voice: voice,
      language: language,
      speed: speed,
      model: model,
    );
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(wavBytes, flush: true);
    return file.path;
  }

  /// Clears all cached audio files.
  Future<void> clear() async {
    final dir = await getCacheDirectory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }
  }

  /// Returns total number of cached chunks.
  Future<int> getCachedCount() async {
    final dir = await getCacheDirectory();
    if (!await dir.exists()) return 0;
    final list = await dir.list().toList();
    return list.whereType<File>().length;
  }
}
