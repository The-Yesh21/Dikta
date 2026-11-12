import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// Manages creation and safe cleanup of temporary WAV files for audio playback.
///
/// Follows official sherpa-onnx integration pattern:
/// 1. PCM float samples are written to a temp .wav file on disk via [sherpa_onnx.writeWave].
/// 2. Audio is played via [audioplayers] pointing to the temp file.
/// 3. Temp file is deleted immediately after playback completes or on session cleanup.
class TempAudioFileManager {
  TempAudioFileManager();

  final List<String> _trackedFiles = [];

  /// Writes [samples] to a unique temporary WAV file and returns its path.
  Future<String> writeTempWave({
    required Float32List samples,
    required int sampleRate,
    required int chunkIndex,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final filePath = '${tempDir.path}/dictation_chunk_${chunkIndex}_$timestamp.wav';

    final success = sherpa_onnx.writeWave(
      filename: filePath,
      samples: samples,
      sampleRate: sampleRate,
    );

    if (!success) {
      throw FileSystemException('Failed to write WAV file at $filePath');
    }

    _trackedFiles.add(filePath);
    return filePath;
  }

  /// Writes raw binary WAV [bytes] to a temporary WAV file and returns its path.
  Future<String> writeTempWavBytes({
    required Uint8List bytes,
    required int chunkIndex,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final filePath = '${tempDir.path}/dictation_chunk_${chunkIndex}_$timestamp.wav';

    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);

    _trackedFiles.add(filePath);
    return filePath;
  }

  /// Deletes a specific temporary audio file.
  Future<void> deleteTempWave(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore OS file-busy or non-fatal file deletion errors
    } finally {
      _trackedFiles.remove(filePath);
    }
  }

  /// Cleans up all tracked temporary files created during this session.
  Future<void> cleanupAll() async {
    final toDelete = List<String>.from(_trackedFiles);
    for (final path in toDelete) {
      await deleteTempWave(path);
    }
    _trackedFiles.clear();
  }
}
