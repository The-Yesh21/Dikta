import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'model_locator.dart';
import 'voice_engine.dart';

/// Messages passed to the background Kokoro synthesis isolate.
sealed class _WorkerMessage {}

class _InitMessage extends _WorkerMessage {
  _InitMessage({
    required this.paths,
    required this.numThreads,
    required this.sendPort,
  });

  final KokoroModelPaths paths;
  final int numThreads;
  final SendPort sendPort;
}

class _SynthesizeMessage extends _WorkerMessage {
  _SynthesizeMessage({
    required this.requestId,
    required this.text,
    required this.speakerId,
    required this.speed,
    required this.replyPort,
  });

  final int requestId;
  final String text;
  final int speakerId;
  final double speed;
  final SendPort replyPort;
}

class _DisposeMessage extends _WorkerMessage {}

/// Kokoro-82M TTS implementation executing entirely inside a background [Isolate].
///
/// Guarantees that heavy ONNX model inference never blocks the Flutter UI thread.
class KokoroEngine implements VoiceEngine {
  Isolate? _workerIsolate;
  SendPort? _workerSendPort;
  int _numSpeakers = 0;
  int _requestCounter = 0;

  @override
  int get numSpeakers => _numSpeakers;

  @override
  Future<void> init(KokoroModelPaths paths, {int numThreads = 2}) async {
    await dispose();

    final initPort = ReceivePort();
    _workerIsolate = await Isolate.spawn(
      _kokoroWorkerEntry,
      _InitMessage(
        paths: paths,
        numThreads: numThreads,
        sendPort: initPort.sendPort,
      ),
    );

    final result = await initPort.first;
    initPort.close();

    if (result is Map && result['status'] == 'ok') {
      _workerSendPort = result['sendPort'] as SendPort;
      _numSpeakers = result['numSpeakers'] as int? ?? 0;
    } else {
      throw Exception('Failed to initialize Kokoro worker isolate: $result');
    }
  }

  @override
  Future<GeneratedAudio> synthesize(
    String text, {
    int speakerId = 0,
    String? voice,
    String? language,
    double speed = 1.0,
  }) async {
    final sendPort = _workerSendPort;
    if (sendPort == null) {
      throw StateError('KokoroEngine is not initialized. Call init() first.');
    }

    final requestId = ++_requestCounter;
    final responsePort = ReceivePort();

    sendPort.send(
      _SynthesizeMessage(
        requestId: requestId,
        text: text,
        speakerId: speakerId,
        speed: speed,
        replyPort: responsePort.sendPort,
      ),
    );

    final dynamic response = await responsePort.first;
    responsePort.close();

    if (response is Map) {
      if (response['status'] == 'ok') {
        final samples = response['samples'] as Float32List;
        final sampleRate = response['sampleRate'] as int;
        final duration = (sampleRate > 0 && samples.isNotEmpty)
            ? (samples.length / sampleRate)
            : 0.0;
        return GeneratedAudio(
          samples: samples,
          sampleRate: sampleRate,
          durationSeconds: duration,
        );
      } else {
        throw Exception('Synthesis error: ${response['error']}');
      }
    }
    throw Exception('Unexpected isolate response format: $response');
  }

  @override
  Future<void> dispose() async {
    _workerSendPort?.send(_DisposeMessage());
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _workerSendPort = null;
    _numSpeakers = 0;
  }
}

/// Entry point executed inside the spawned background Isolate.
void _kokoroWorkerEntry(_InitMessage initMessage) {
  final commandPort = ReceivePort();

  try {
    // 1. Initialize FFI bindings in this isolate.
    sherpa_onnx.initBindings();

    // 2. Configure Kokoro model.
    final config = sherpa_onnx.OfflineTtsConfig(
      model: sherpa_onnx.OfflineTtsModelConfig(
        kokoro: sherpa_onnx.OfflineTtsKokoroModelConfig(
          model: initMessage.paths.modelPath,
          voices: initMessage.paths.voicesPath,
          tokens: initMessage.paths.tokensPath,
          dataDir: initMessage.paths.dataDirPath,
          lexicon: initMessage.paths.lexiconPath ?? '',
        ),
        numThreads: initMessage.numThreads,
        provider: 'cpu',
      ),
    );

    final tts = sherpa_onnx.OfflineTts(config);
    final numSpeakers = tts.numSpeakers;

    // Report readiness back to caller with the isolate's listening SendPort.
    initMessage.sendPort.send({
      'status': 'ok',
      'sendPort': commandPort.sendPort,
      'numSpeakers': numSpeakers,
    });

    // 3. Listen for incoming synthesis and control requests.
    commandPort.listen((dynamic message) {
      if (message is _SynthesizeMessage) {
        try {
          final audio = tts.generate(
            text: message.text,
            sid: message.speakerId,
            speed: message.speed,
          );

          if (audio.samples.isEmpty) {
            // ignore: avoid_print
            print('[KOKORO WORKER] Warning: generate returned empty samples for "${message.text}"');
          }

          // Transfer samples as typed data
          message.replyPort.send({
            'status': 'ok',
            'samples': audio.samples,
            'sampleRate': audio.sampleRate,
          });
        } catch (e) {
          message.replyPort.send({
            'status': 'error',
            'error': e.toString(),
          });
        }
      } else if (message is _DisposeMessage) {
        commandPort.close();
        tts.free();
      }
    });
  } catch (e) {
    initMessage.sendPort.send({
      'status': 'error',
      'error': e.toString(),
    });
  }
}
