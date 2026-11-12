import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Resolved local file system paths for Kokoro TTS model assets.
class KokoroModelPaths {
  const KokoroModelPaths({
    required this.modelPath,
    required this.voicesPath,
    required this.tokensPath,
    required this.dataDirPath,
    required this.isInt8,
    this.lexiconPath,
  });

  final String modelPath;
  final String voicesPath;
  final String tokensPath;
  final String dataDirPath;
  final bool isInt8;
  final String? lexiconPath;

  @override
  String toString() =>
      'KokoroModelPaths(model: $modelPath, isInt8: $isInt8, lexicon: $lexiconPath, dataDir: $dataDirPath)';
}

/// Abstract contract for discovering and locating on-device TTS models.
abstract class ModelLocator {
  Future<Directory> getModelsDirectory();
  Future<bool> isKokoroModelPresent();
  Future<KokoroModelPaths?> locateKokoroModel();
}

/// Dynamic ModelLocator resolving paths through [path_provider]'s external files directory.
///
/// Complies with project requirements:
/// - No hardcoded app ID or package name.
/// - No hardcoded /sdcard paths.
/// - Works on Android external app storage (`Context.getExternalFilesDir(null)`).
class ExternalStorageModelLocator implements ModelLocator {
  const ExternalStorageModelLocator();

  @override
  Future<Directory> getModelsDirectory() async {
    Directory? baseDir;
    try {
      baseDir = await getExternalStorageDirectory();
    } catch (_) {
      // Fallback on platforms without external files dir
    }

    baseDir ??= await getApplicationDocumentsDirectory();

    final modelsDir = Directory('${baseDir.path}/models/kokoro');
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir;
  }

  @override
  Future<bool> isKokoroModelPresent() async {
    final paths = await locateKokoroModel();
    return paths != null;
  }

  @override
  Future<KokoroModelPaths?> locateKokoroModel() async {
    final dir = await getModelsDirectory();

    // Check for int8 model first, then fp32
    final int8File = File('${dir.path}/model.int8.onnx');
    final fp32File = File('${dir.path}/model.onnx');

    String? selectedModelPath;
    bool isInt8 = false;

    if (await int8File.exists()) {
      selectedModelPath = int8File.path;
      isInt8 = true;
    } else if (await fp32File.exists()) {
      selectedModelPath = fp32File.path;
      isInt8 = false;
    } else {
      return null;
    }

    final voicesFile = File('${dir.path}/voices.bin');
    final tokensFile = File('${dir.path}/tokens.txt');
    final espeakDir = Directory('${dir.path}/espeak-ng-data');
    final lexiconUsEn = File('${dir.path}/lexicon-us-en.txt');
    final lexiconEnUs = File('${dir.path}/lexicon-en-us.txt');
    final lexiconGeneral = File('${dir.path}/lexicon.txt');

    String? lexiconPath;
    if (await lexiconUsEn.exists()) {
      lexiconPath = lexiconUsEn.path;
    } else if (await lexiconEnUs.exists()) {
      lexiconPath = lexiconEnUs.path;
    } else if (await lexiconGeneral.exists()) {
      lexiconPath = lexiconGeneral.path;
    }

    if (!await voicesFile.exists() ||
        !await tokensFile.exists()) {
      return null;
    }

    return KokoroModelPaths(
      modelPath: selectedModelPath,
      voicesPath: voicesFile.path,
      tokensPath: tokensFile.path,
      dataDirPath: espeakDir.existsSync() ? espeakDir.path : dir.path,
      lexiconPath: lexiconPath,
      isInt8: isInt8,
    );
  }
}
