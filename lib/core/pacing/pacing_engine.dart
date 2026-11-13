import 'dart:math' as math;
import 'package:characters/characters.dart';
import '../../config/pacing_config.dart';
import '../chunker/chunk_info.dart';

export '../../config/pacing_config.dart' show ScriptType;

/// Clock provider function to enable deterministic testing without DateTime.now().
typedef Clock = DateTime Function();

/// Pure Dart pacing engine for handwriting dictation based on grapheme clusters and LPM.
///
/// Implements the Pacing Redesign formula:
/// ```
/// writeSeconds = (graphemes / userLpm) * 60 * scriptFactor
/// gap          = max(minGap, writeSeconds - overlapFactor * speechSeconds) + boundaryPause
/// totalCycle   = speechSeconds + gap
/// ```
class PacingEngine {
  PacingEngine({
    this.config = PacingConfig.defaultConfig,
    double? userLpm,
    Clock? clock,
    math.Random? random,
  })  : _customUserLpm = userLpm,
        _clock = clock ?? DateTime.now,
        _random = random ?? math.Random() {
    _sessionStartTime = _clock();
    _lastBreathTime = _sessionStartTime;
  }

  final PacingConfig config;
  final Clock _clock;
  final math.Random _random;

  late DateTime _sessionStartTime;
  late DateTime _lastBreathTime;

  double _fatigueOffsetMinutes = 0.0;

  // Custom runtime overrides (e.g. from calibration, tuning panel, or adaptive feedback)
  double? _customUserLpm;
  double? _customScriptFactorLatin;
  double? _customScriptFactorDevanagari;
  double? _customScriptFactorKannada;
  double? _customFatigueStrength;
  double? _customCommaPause;
  double? _customSentencePause;
  double? _customParagraphPause;
  double? _customGnaniSpeechRate;
  double? _customMaxGapSeconds;

  /// Maximum gap duration in seconds (prevents runaway pauses between chunks).
  double get maxGapSeconds => _customMaxGapSeconds ?? config.maxGapSeconds;
  set maxGapSeconds(double val) => _customMaxGapSeconds = val.clamp(1.0, 60.0);

  /// User handwriting speed in letters per minute (LPM).
  double get userLpm {
    if (_customUserLpm != null) {
      return _customUserLpm!;
    }
    // Backward-compatibility: if tests or legacy configs explicitly override secondsPerGraphemeLatin
    if (config.secondsPerGraphemeLatin != 0.28 && config.secondsPerGraphemeLatin > 0) {
      return 60.0 / config.secondsPerGraphemeLatin;
    }
    return config.defaultUserLpm;
  }

  set userLpm(double val) => _customUserLpm = val.clamp(1.0, 100000.0);

  /// Convenient alias for [userLpm].
  double get lpm => userLpm;
  set lpm(double val) => userLpm = val;

  /// Counts non-whitespace Unicode Extended Grapheme Clusters using Dart [characters].
  ///
  /// Spaces (including all whitespace characters) are strictly excluded from the count.
  static int countGraphemes(String text) {
    if (text.isEmpty) return 0;
    return text.characters.where((c) => c != ' ' && c.trim().isNotEmpty).length;
  }

  /// Detects the script family of [text] or resolves from [languageCode].
  static ScriptType detectScript(String text, {String? languageCode}) {
    if (languageCode == 'kn-IN' || text.contains(RegExp(r'[\u0C80-\u0CFF]'))) {
      return ScriptType.kannada;
    }
    if (languageCode == 'hi-IN' || text.contains(RegExp(r'[\u0900-\u097F]'))) {
      return ScriptType.devanagari;
    }
    return ScriptType.latin;
  }

  /// Returns the script multiplier factor for a given script, text, or language code.
  double getScriptFactor({ScriptType? script, String? text, String? languageCode}) {
    final s = script ?? (text != null ? detectScript(text, languageCode: languageCode) : ScriptType.latin);
    switch (s) {
      case ScriptType.kannada:
        return _customScriptFactorKannada ?? config.scriptFactorKannada;
      case ScriptType.devanagari:
        return _customScriptFactorDevanagari ?? config.scriptFactorDevanagari;
      case ScriptType.latin:
        return _customScriptFactorLatin ?? config.scriptFactorLatin;
    }
  }

  /// Sets custom script factor multiplier for a given script family.
  void setScriptFactor(ScriptType script, double factor) {
    final clamped = factor.clamp(0.1, 5.0);
    switch (script) {
      case ScriptType.kannada:
        _customScriptFactorKannada = clamped;
        break;
      case ScriptType.devanagari:
        _customScriptFactorDevanagari = clamped;
        break;
      case ScriptType.latin:
        _customScriptFactorLatin = clamped;
        break;
    }
  }

  /// Backwards-compatibility helper for seconds per grapheme: (60 / LPM) * scriptFactor.
  double getWritingSecondsPerGrapheme({ScriptType? script, String? text, String? languageCode}) {
    final factor = getScriptFactor(script: script, text: text, languageCode: languageCode);
    return (60.0 / userLpm) * factor;
  }

  /// Backwards-compatibility setter for seconds per grapheme.
  void setSecondsPerGrapheme(ScriptType script, double seconds) {
    if (seconds > 0) {
      userLpm = 60.0 / seconds;
    }
  }

  // Live tuning getters and setters
  double get fatigueStrength => _customFatigueStrength ?? config.fatigueStrength;
  set fatigueStrength(double val) => _customFatigueStrength = val.clamp(0.0, 1.0);

  double get commaPause => _customCommaPause ?? config.syntaxPauseCommaSeconds;
  set commaPause(double val) => _customCommaPause = val.clamp(0.0, 3.0);

  double get sentencePause => _customSentencePause ?? config.syntaxPauseSentenceSeconds;
  set sentencePause(double val) => _customSentencePause = val.clamp(0.0, 5.0);

  double get paragraphPause => _customParagraphPause ?? config.syntaxPauseParagraphSeconds;
  set paragraphPause(double val) => _customParagraphPause = val.clamp(0.0, 8.0);

  double get gnaniSpeechRate => _customGnaniSpeechRate ?? config.gnaniSpeechRate;
  set gnaniSpeechRate(double val) => _customGnaniSpeechRate = val.clamp(0.85, 1.15);

  /// Backwards-compatibility getter for words/sec assuming ~5 graphemes per word.
  double get currentWritingSpeed => userLpm / (5.0 * 60.0);

  set writingSpeed(double wordsPerSec) {
    if (wordsPerSec > 0) {
      userLpm = wordsPerSec * 5.0 * 60.0;
    }
  }

  /// Resets the session timer to initial state.
  void reset() {
    _sessionStartTime = _clock();
    _lastBreathTime = _sessionStartTime;
    _fatigueOffsetMinutes = 0.0;
  }

  /// Calculates the current session tempo factor tempo(t) in [tempoMin, tempo0].
  double get currentTempo {
    final now = _clock();
    final elapsedMinutes =
        now.difference(_sessionStartTime).inMicroseconds / (1000000.0 * 60.0);

    // Periodic sawtooth breath
    final minutesSinceLastBreath =
        now.difference(_lastBreathTime).inMicroseconds / (1000000.0 * 60.0);
    if (minutesSinceLastBreath >= config.sawtoothIntervalMinutes) {
      applySawtoothBreath();
    }

    final effectiveMinutes = math.max(0.0, elapsedMinutes - _fatigueOffsetMinutes);

    if (fatigueStrength <= 0.0 || config.tauMinutes <= 0.0) {
      return config.tempo0;
    }

    final decayRange = (config.tempo0 - config.tempoMin) * fatigueStrength;
    final decayFactor = 1.0 - math.exp(-effectiveMinutes / config.tauMinutes);
    final tempo = config.tempo0 - (decayRange * decayFactor);

    return tempo.clamp(config.tempoMin, config.tempo0);
  }

  /// Computes the unjittered writing time in seconds for [chunk].
  ///
  /// Formula: writeSeconds = (graphemes / userLpm) * 60 * scriptFactor
  /// (scaled by current tempo if fatigue is active).
  double calculateWriteSeconds(ChunkInfo chunk, {String? languageCode}) {
    final graphemes = countGraphemes(chunk.text);
    if (graphemes <= 0) return 0.0;

    final scriptFactor = getScriptFactor(
      text: chunk.text,
      languageCode: languageCode,
    );
    final effectiveLpm = userLpm * currentTempo;
    if (effectiveLpm <= 0) return 0.0;

    return (graphemes / effectiveLpm) * 60.0 * scriptFactor;
  }

  /// Backwards-compatibility alias for [calculateWriteSeconds].
  double calculateWritingBudget(ChunkInfo chunk, {String? languageCode}) {
    return calculateWriteSeconds(chunk, languageCode: languageCode);
  }

  /// Computes the silence pause duration following [chunk].
  ///
  /// Pacing Redesign Formula:
  ///   writeSeconds = (graphemes / userLpm) * 60 * scriptFactor
  ///   gap          = max(minGap, writeSeconds - overlapFactor * speechSeconds) + boundaryPause
  ///
  /// When writeSeconds minus overlapping speech falls below [minGapSeconds],
  /// the net gap evaluates strictly to [minGapSeconds] plus any punctuation [boundaryPause].
  double calculateGap(
    ChunkInfo chunk, {
    double speechDurationSeconds = 0.0,
    String? languageCode,
    bool applyJitter = true,
  }) {
    // 1. If this chunk ends a paragraph, apply a sawtooth breath before calculating gap.
    if (chunk.boundaryType == BoundaryType.paragraph) {
      applySawtoothBreath();
    }

    // 2. Compute writing time in seconds.
    final writeSeconds = calculateWriteSeconds(chunk, languageCode: languageCode);
    final jitter = applyJitter ? _generateLognormalJitter() : 1.0;
    final writingTime = writeSeconds * jitter;

    // 3. Overlap with speech: max(minGap, min(maxGap, writeSeconds) - overlapFactor * speechSeconds)
    final clampedWritingTime = math.min(maxGapSeconds, writingTime);
    final netWritingTime = math.max(
      config.minGapSeconds,
      clampedWritingTime - (config.overlapFactor * speechDurationSeconds),
    );

    // 4. Boundary pause added on top of net writing time.
    final boundaryPause = _resolveSyntaxPause(chunk.boundaryType);

    // 5. Total gap.
    return netWritingTime + boundaryPause;
  }

  /// Partially restores tempo at breaths (paragraph breaks or every 5 minutes).
  void applySawtoothBreath() {
    final now = _clock();
    final elapsedMinutes =
        now.difference(_sessionStartTime).inMicroseconds / (1000000.0 * 60.0);
    final currentAccumulatedFatigue =
        math.max(0.0, elapsedMinutes - _fatigueOffsetMinutes);

    final recoveredMinutes = currentAccumulatedFatigue * config.sawtoothRecoveryRatio;
    _fatigueOffsetMinutes += recoveredMinutes;
    _lastBreathTime = now;
  }

  /// Slower adaptation: user needs more time (lower LPM).
  void adaptSlower([ScriptType? script]) {
    userLpm = math.max(10.0, userLpm - 2.0);
  }

  /// Faster adaptation: user writes faster (higher LPM).
  void adaptFaster([ScriptType? script]) {
    userLpm = math.min(180.0, userLpm + 2.0);
  }

  /// Resolves boundary pause duration based on punctuation.
  double _resolveSyntaxPause(BoundaryType type) {
    switch (type) {
      case BoundaryType.comma:
        return commaPause;
      case BoundaryType.sentence:
        return sentencePause;
      case BoundaryType.paragraph:
        return paragraphPause;
      case BoundaryType.none:
        return 0.0;
    }
  }

  /// Generates a lognormally-distributed jitter multiplier with mean = 1.0.
  double _generateLognormalJitter() {
    if (config.jitterSigma <= 0.0) return 1.0;

    var u1 = _random.nextDouble();
    while (u1 <= 1e-12) {
      u1 = _random.nextDouble();
    }
    final u2 = _random.nextDouble();

    final z = math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2);
    final mu = -(config.jitterSigma * config.jitterSigma) / 2.0;
    return math.exp(mu + (config.jitterSigma * z));
  }

  /// Calculates voice speed (Kokoro offline or base Gnani).
  double calculateChunkVoiceSpeed(ChunkInfo chunk, {double? baseRate}) {
    final base = baseRate ?? (_customGnaniSpeechRate ?? gnaniSpeechRate);
    if (chunk.wordCount <= 0 || chunk.text.trim().isEmpty) {
      return base;
    }

    final words = chunk.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (words.isEmpty) return base;

    final totalChars = words.fold<int>(0, (sum, w) => sum + w.length);
    final avgChars = totalChars / words.length;

    if (avgChars >= config.longWordCharThreshold) {
      return base * config.longWordSpeedScale;
    }
    return base;
  }
}
