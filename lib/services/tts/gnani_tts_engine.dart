import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../../config/gnani_config.dart';
import 'gnani_chunk_cache.dart';
import 'voice_engine.dart';

/// Base exception for Gnani Cloud TTS errors.
abstract class GnaniException implements Exception {
  const GnaniException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Thrown when device has no internet or network is unreachable.
class GnaniNetworkException extends GnaniException {
  const GnaniNetworkException([String message = 'No network connection. Please check your internet.'])
      : super(message);
}

/// Thrown when Gnani API rate limit (HTTP 429) is hit.
class GnaniRateLimitException extends GnaniException {
  const GnaniRateLimitException([String message = 'Gnani TTS rate limit reached. Retrying...'])
      : super(message, statusCode: 429);
}

/// Thrown when authentication fails (HTTP 401 or 403).
class GnaniAuthException extends GnaniException {
  const GnaniAuthException([String message = 'Authentication error. Please check your Gnani API key.'])
      : super(message, statusCode: 401);
}

/// Thrown for invalid input or other server errors (HTTP 400/500).
class GnaniApiException extends GnaniException {
  const GnaniApiException(super.message, {super.statusCode});
}

/// Cloud-first Text-to-Speech engine powered by Gnani Vachana API.
///
/// Implements [VoiceEngine] with transparent disk caching and failure handling.
class GnaniTtsEngine implements VoiceEngine {
  GnaniTtsEngine({
    String? apiKey,
    this.config = GnaniConfig.defaultConfig,
    GnaniChunkCache? cache,
    HttpClient? httpClient,
  })  : _apiKey = apiKey ?? GnaniConfig.resolveApiKey(),
        _cache = cache ?? GnaniChunkCache(),
        _httpClient = httpClient ?? HttpClient();

  final String _apiKey;
  final GnaniConfig config;
  final GnaniChunkCache _cache;
  final HttpClient _httpClient;
  final Map<String, GeneratedAudio> _memCache = {};

  String _currentVoice = GnaniConfig.defaultConfig.defaultVoice;
  String _currentLanguage = GnaniConfig.defaultConfig.defaultLanguage;
  String _currentModel = GnaniConfig.defaultConfig.defaultModel;

  String get currentVoice => _currentVoice;
  set currentVoice(String v) => _currentVoice = v;

  String get currentLanguage => _currentLanguage;
  set currentLanguage(String l) => _currentLanguage = l;

  String get currentModel => _currentModel;
  set currentModel(String m) => _currentModel = m;

  GnaniChunkCache get cache => _cache;

  @override
  int get numSpeakers => GnaniVoiceCatalog.timbreV3Voices.length + GnaniVoiceCatalog.timbreV25Voices.length;

  /// Synthesizes [text] using Gnani TTS API or returns cached audio if available.
  @override
  Future<GeneratedAudio> synthesize(
    String text, {
    int speakerId = 0,
    String? voice,
    String? language,
    double speed = 1.0,
    String? model,
  }) async {
    final effectiveLanguage = language ?? _currentLanguage;
    final effectiveVoice = voice ??
        (language != null && !GnaniVoiceCatalog.getVoicesForLanguage(effectiveLanguage).any((v) => v.name == _currentVoice)
            ? GnaniVoiceCatalog.getVoicesForLanguage(effectiveLanguage).first.name
            : _currentVoice);
    final effectiveModel = model ?? _currentModel;

    // Clamp speed to Gnani API supported range: [0.85, 1.15]
    final clampedSpeed = speed.clamp(config.minSpeed, config.maxSpeed);

    // 0. Fast In-Memory Cache Lookup (avoids repeated disk I/O and network)
    final memKey = '${effectiveLanguage.toLowerCase()}|${effectiveVoice.toLowerCase()}|${clampedSpeed.toStringAsFixed(2)}|${text.trim()}';
    if (_memCache.containsKey(memKey)) {
      final memAudio = _memCache[memKey]!;
      return GeneratedAudio(
        durationSeconds: memAudio.durationSeconds,
        sampleRate: memAudio.sampleRate,
        wavBytes: memAudio.wavBytes,
        audioFilePath: memAudio.audioFilePath,
        isFromCache: true,
      );
    }

    // 1. Check disk cache
    final cachedPath = await _cache.getCachedAudioPath(
      text: text,
      voice: effectiveVoice,
      language: effectiveLanguage,
      speed: clampedSpeed,
      model: effectiveModel,
    );

    if (cachedPath != null) {
      final file = File(cachedPath);
      final bytes = await file.readAsBytes();
      final duration = _extractWavDuration(bytes, config.defaultSampleRate);

      final audio = GeneratedAudio(
        durationSeconds: duration,
        sampleRate: config.defaultSampleRate,
        wavBytes: bytes,
        audioFilePath: cachedPath,
        isFromCache: true,
      );
      _memCache[memKey] = audio;
      return audio;
    }

    // 2. Ensure API key is configured
    if (_apiKey.isEmpty) {
      throw const GnaniAuthException(
        'Gnani API key is missing. Configure it in gnani_config.json or pass --dart-define=GNANI_API_KEY=...',
      );
    }

    // 3. Make HTTP request to Gnani REST API
    final Uint8List wavBytes;
    try {
      wavBytes = await _callInferenceApi(
        text: text,
        voice: effectiveVoice,
        language: effectiveLanguage,
        model: effectiveModel,
        speed: clampedSpeed,
      );
    } on SocketException {
      throw const GnaniNetworkException();
    } on HttpException catch (e) {
      throw GnaniApiException('Network HTTP failure: ${e.message}');
    }

    // 4. Save to disk cache for rewind and repeat operations
    final savedPath = await _cache.saveCachedAudio(
      text: text,
      wavBytes: wavBytes,
      voice: effectiveVoice,
      language: effectiveLanguage,
      speed: clampedSpeed,
      model: effectiveModel,
    );

    final duration = _extractWavDuration(wavBytes, config.defaultSampleRate);

    final generated = GeneratedAudio(
      durationSeconds: duration,
      sampleRate: config.defaultSampleRate,
      wavBytes: wavBytes,
      audioFilePath: savedPath,
      isFromCache: false,
    );
    _memCache[memKey] = generated;
    return generated;
  }

  Future<Uint8List> _callInferenceApi({
    required String text,
    required String voice,
    required String language,
    required String model,
    required double speed,
  }) async {
    final uri = Uri.parse(config.endpoint);
    final request = await _httpClient.postUrl(uri);

    // Standard headers
    request.headers.set('Content-Type', 'application/json');
    // Note: NEVER log or expose this header in debug output
    request.headers.set('X-API-Key-ID', _apiKey);
    request.headers.set('User-Agent', 'DictationApp/1.0 (Android; Flutter)');

    final payload = {
      'text': text,
      'voice': voice,
      'model': model,
      'language': language,
      'speed': speed,
      'audio_config': {
        'sample_rate': config.defaultSampleRate,
        'container': 'wav',
        'encoding': 'linear_pcm',
        'num_channels': 1,
        'sample_width': 2,
      },
    };

    request.write(jsonEncode(payload));
    final response = await request.close();

    final responseBodyBytes = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );

    final statusCode = response.statusCode;

    if (statusCode == 200) {
      final wavBytes = Uint8List.fromList(responseBodyBytes);
      return prependWavSilence(wavBytes, sampleRate: config.defaultSampleRate, leadingSilenceMs: 600);
    }

    // Decode error body
    String errorMessage = 'Synthesis failed with status $statusCode';
    try {
      final decoded = jsonDecode(utf8.decode(responseBodyBytes));
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('message')) {
          errorMessage = decoded['message'].toString();
        } else if (decoded.containsKey('detail') && decoded['detail'] is Map) {
          final detail = decoded['detail'] as Map;
          errorMessage = detail['message']?.toString() ?? detail['error_code']?.toString() ?? errorMessage;
        } else if (decoded.containsKey('error') && decoded['error'] is Map) {
          final err = decoded['error'] as Map;
          errorMessage = err['message']?.toString() ?? errorMessage;
        }
      }
    } catch (_) {
      // Fallback to generic message
    }

    if (statusCode == 429) {
      throw GnaniRateLimitException('Rate limit exceeded: $errorMessage');
    } else if (statusCode == 401 || statusCode == 403) {
      throw GnaniAuthException('Authentication failed: $errorMessage');
    } else {
      throw GnaniApiException(errorMessage, statusCode: statusCode);
    }
  }

  /// Calculates duration from RIFF WAV header (subchunk2 size / byte rate).
  double _extractWavDuration(Uint8List bytes, int sampleRate) {
    if (bytes.length >= 44 &&
        bytes[0] == 0x52 && // 'R'
        bytes[1] == 0x49 && // 'I'
        bytes[2] == 0x46 && // 'F'
        bytes[3] == 0x46) { // 'F'
      // Locate 'data' chunk
      var offset = 12;
      while (offset + 8 <= bytes.length) {
        final chunkId = String.fromCharCode(bytes[offset]) +
            String.fromCharCode(bytes[offset + 1]) +
            String.fromCharCode(bytes[offset + 2]) +
            String.fromCharCode(bytes[offset + 3]);
        final chunkSize = bytes[offset + 4] |
            (bytes[offset + 5] << 8) |
            (bytes[offset + 6] << 16) |
            (bytes[offset + 7] << 24);

        if (chunkId == 'data') {
          // 16-bit mono = 2 bytes per sample
          final byteRate = sampleRate * 1 * 2;
          return chunkSize / byteRate;
        }
        offset += 8 + chunkSize;
      }
    }

    // Fallback: estimate from total payload assuming 44-byte header
    final payloadSize = (bytes.length - 44).clamp(0, bytes.length);
    return payloadSize / (sampleRate * 2);
  }

  /// Prepends [leadingSilenceMs] of silence (zeros) to the WAV audio payload.
  ///
  /// Solves the Android hardware DAC / Bluetooth cold startup ramp-up latency
  /// where the first 200-300ms of audio are muted by hardware power-management.
  static Uint8List prependWavSilence(
    Uint8List bytes, {
    int sampleRate = 16000,
    int leadingSilenceMs = 600,
  }) {
    if (bytes.length < 44 || leadingSilenceMs <= 0) {
      return normalizeWavHeader(bytes);
    }

    final silenceSampleCount = (sampleRate * (leadingSilenceMs / 1000.0)).round();
    final silenceBytesCount = silenceSampleCount * 2; // 16-bit mono = 2 bytes per sample

    final builder = BytesBuilder(copy: false)
      ..add(bytes.sublist(0, 44))
      ..add(Uint8List(silenceBytesCount))
      ..add(bytes.sublist(44));

    final combined = builder.toBytes();
    return normalizeWavHeader(combined);
  }

  /// Normalizes streaming WAV headers where cloud API leaves chunk sizes as 0xFFFFFFFF.
  ///
  /// Android's native MediaPlayer / MediaExtractor crashes with MEDIA_ERROR_UNKNOWN
  /// on WAV files that declare a 4GB size but terminate at 50-200 KB. Setting the
  /// exact byte sizes guarantees seamless playback across all platforms.
  static Uint8List normalizeWavHeader(Uint8List bytes) {
    if (bytes.length >= 44 &&
        bytes[0] == 0x52 && // 'R'
        bytes[1] == 0x49 && // 'I'
        bytes[2] == 0x46 && // 'F'
        bytes[3] == 0x46) { // 'F'
      final byteData = ByteData.sublistView(bytes);
      final riffSize = bytes.length - 8;
      final dataSize = bytes.length - 44;
      byteData.setUint32(4, riffSize, Endian.little);
      byteData.setUint32(40, dataSize, Endian.little);
    }
    return bytes;
  }

  @override
  Future<void> dispose() async {
    _httpClient.close(force: true);
  }
}
