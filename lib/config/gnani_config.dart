import 'dart:io';
import 'gnani_secrets.dart';

/// Configuration and metadata for Gnani Cloud TTS integration.
class GnaniConfig {
  const GnaniConfig({
    this.endpoint = 'https://api.vachana.ai/api/v1/tts/inference',
    this.defaultModel = 'timbre-v3.0',
    this.defaultLanguage = 'en-IN',
    this.defaultVoice = 'Shivani',
    this.defaultSampleRate = 24000,
    this.defaultSpeed = 1.0,
    this.minSpeed = 0.85,
    this.maxSpeed = 1.15,
  });

  final String endpoint;
  final String defaultModel;
  final String defaultLanguage;
  final String defaultVoice;
  final int defaultSampleRate;
  final double defaultSpeed;
  final double minSpeed;
  final double maxSpeed;

  static const GnaniConfig defaultConfig = GnaniConfig();

  /// Safely resolves the API key without logging or printing it.
  ///
  /// Resolution precedence:
  /// 1. Compile-time `--dart-define=GNANI_API_KEY=...`
  /// 2. Untracked `kLocalGnaniApiKey` in `gnani_secrets.dart`
  /// 3. Local untracked `gnani_config.json` in current directory (if readable)
  static String resolveApiKey() {
    // 1. Check dart-define
    const envKey = String.fromEnvironment('GNANI_API_KEY');
    if (envKey.isNotEmpty) {
      return envKey.trim();
    }

    // 2. Check untracked dart secrets file
    if (kLocalGnaniApiKey.isNotEmpty && !kLocalGnaniApiKey.startsWith('YOUR_')) {
      return kLocalGnaniApiKey.trim();
    }

    // 3. Check local JSON file (useful for desktop/tests)
    try {
      final file = File('gnani_config.json');
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        // Parse simple json without logging
        final match = RegExp(r'"apiKey"\s*:\s*"([^"]+)"').firstMatch(content);
        if (match != null && match.group(1) != null) {
          return match.group(1)!.trim();
        }
      }
    } catch (_) {
      // Ignore file access errors on sandboxed mobile runtimes
    }

    return '';
  }
}

/// Metadata description of a Gnani voice.
class GnaniVoiceInfo {
  const GnaniVoiceInfo({
    required this.name,
    required this.gender,
    required this.model,
    required this.language,
    required this.description,
  });

  final String name;
  final String gender; // 'Female' | 'Male'
  final String model; // 'timbre-v3.0' | 'timbre-v2.5'
  final String language; // 'en-IN', 'hi-IN', 'kn-IN', or 'all'
  final String description;

  String get displayName => '$name ($gender • $model)';
}

/// Curated voice catalogs for Indian English, Hindi, and Kannada.
class GnaniVoiceCatalog {
  static const List<GnaniVoiceInfo> timbreV3Voices = [
    GnaniVoiceInfo(
      name: 'Shivani',
      gender: 'Female',
      model: 'timbre-v3.0',
      language: 'all',
      description: 'Warm, patient, empathetic voice',
    ),
    GnaniVoiceInfo(
      name: 'Lakshmi',
      gender: 'Female',
      model: 'timbre-v3.0',
      language: 'all',
      description: 'Expressive, warm narration voice',
    ),
    GnaniVoiceInfo(
      name: 'Kalpana',
      gender: 'Female',
      model: 'timbre-v3.0',
      language: 'all',
      description: 'Empathetic, composed voice',
    ),
    GnaniVoiceInfo(
      name: 'Chetana',
      gender: 'Female',
      model: 'timbre-v3.0',
      language: 'all',
      description: 'Gentle, empathetic tone',
    ),
    GnaniVoiceInfo(
      name: 'Avinash',
      gender: 'Male',
      model: 'timbre-v3.0',
      language: 'all',
      description: 'Professional, deliberate, firm voice',
    ),
    GnaniVoiceInfo(
      name: 'Shubham',
      gender: 'Male',
      model: 'timbre-v3.0',
      language: 'all',
      description: 'Energetic, confident voice',
    ),
    GnaniVoiceInfo(
      name: 'Prakash',
      gender: 'Male',
      model: 'timbre-v3.0',
      language: 'all',
      description: 'Steady, deliberate voice',
    ),
    GnaniVoiceInfo(
      name: 'Devansh',
      gender: 'Male',
      model: 'timbre-v3.0',
      language: 'all',
      description: 'Young conversational voice',
    ),
  ];

  static const List<GnaniVoiceInfo> timbreV25Voices = [
    // English
    GnaniVoiceInfo(
      name: 'Kaveri',
      gender: 'Female',
      model: 'timbre-v2.5',
      language: 'en-IN',
      description: 'Firm, articulate professional voice',
    ),
    GnaniVoiceInfo(
      name: 'Devika',
      gender: 'Female',
      model: 'timbre-v2.5',
      language: 'en-IN',
      description: 'Authoritative professional voice',
    ),
    GnaniVoiceInfo(
      name: 'Pranav',
      gender: 'Male',
      model: 'timbre-v2.5',
      language: 'en-IN',
      description: 'Conversational, natural male voice',
    ),
    GnaniVoiceInfo(
      name: 'Girish',
      gender: 'Male',
      model: 'timbre-v2.5',
      language: 'en-IN',
      description: 'Warm, expressive storytelling voice',
    ),
    // Hindi
    GnaniVoiceInfo(
      name: 'Nalini',
      gender: 'Female',
      model: 'timbre-v2.5',
      language: 'hi-IN',
      description: 'Friendly, natural Hindi voice',
    ),
    GnaniVoiceInfo(
      name: 'Bhavna',
      gender: 'Female',
      model: 'timbre-v2.5',
      language: 'hi-IN',
      description: 'Warm, empathetic Hindi voice',
    ),
    GnaniVoiceInfo(
      name: 'Deepak',
      gender: 'Male',
      model: 'timbre-v2.5',
      language: 'hi-IN',
      description: 'Clear, measured corporate voice',
    ),
    GnaniVoiceInfo(
      name: 'Roopesh',
      gender: 'Male',
      model: 'timbre-v2.5',
      language: 'hi-IN',
      description: 'Confident, natural Hindi male voice',
    ),
    // Kannada
    GnaniVoiceInfo(
      name: 'Saanvi',
      gender: 'Female',
      model: 'timbre-v2.5',
      language: 'kn-IN',
      description: 'Clear, natural Kannada female voice',
    ),
    GnaniVoiceInfo(
      name: 'Kavin',
      gender: 'Male',
      model: 'timbre-v2.5',
      language: 'kn-IN',
      description: 'Firm, articulate Kannada male voice',
    ),
  ];

  /// Returns available voices matching the specified language.
  static List<GnaniVoiceInfo> getVoicesForLanguage(String language) {
    final v3 = timbreV3Voices; // all v3 voices speak all languages
    final v25 = timbreV25Voices.where((v) => v.language == language).toList();
    return [...v3, ...v25];
  }

  /// Finds metadata for a voice by name (case-insensitive).
  static GnaniVoiceInfo? findVoice(String voiceName) {
    for (final v in timbreV3Voices) {
      if (v.name.toLowerCase() == voiceName.toLowerCase()) return v;
    }
    for (final v in timbreV25Voices) {
      if (v.name.toLowerCase() == voiceName.toLowerCase()) return v;
    }
    return null;
  }
}
