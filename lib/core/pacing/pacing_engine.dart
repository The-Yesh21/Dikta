import 'dart:math' as math;
import 'package:characters/characters.dart';
import '../../config/pacing_config.dart';
import '../chunker/chunk_info.dart';

/// Clock provider function to enable deterministic testing without DateTime.now().
typedef Clock = DateTime Function();

/// Supported writing script families for grapheme-based handwriting pacing.
enum ScriptType {
  latin,
  devanagari,
  kannada,
}

/// Pure Dart pacing engine for handwriting dictation based on grapheme clusters.
///
/// Implements the exact user-specified formula:
/// ```
/// writingBudget = ( graphemes * secondsPerGrapheme ) / tempo(t)
/// writingTime   = writingBudget * jitter          (counted from START of speech)
/// gap           = max(minGap, writingTime - speechDuration) + boundaryPause
/// totalCycle    = speechDuration + gap
/// ```
class PacingEngine {
  PacingEngine({
    this.config = PacingConfig.defaultConfig,
    Clock? clock,
    math.Random? random,
  })  : _clock = clock ?? DateTime.now,
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

  // Custom runtime overrides (e.g. from calibration or live tuning panel)
  double? _customSecondsPerGraphemeLatin;
  double? _customSecondsPerGraphemeDevanagari;
  double? _customSecondsPerGraphemeKannada;
  double? _customFatigueStrength;
  double? _customCommaPause;
  double? _customSentencePause;
  double? _customParagraphPause;
  double? _customGnaniSpeechRate;

  /// Counts non-whitespace Unicode Extended Grapheme Clusters using Dart [characters].
  static int countGraphemes(String text) {
    if (text.isEmpty) return 0;
    return text.characters.where((c) => c.trim().isNotEmpty).length;
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

  /// Returns the configured writing seconds per grapheme for a given script or text.
  double getWritingSecondsPerGrapheme({ScriptType? script, String? text, String? languageCode}) {
    final s = script ?? (text != null ? detectScript(text, languageCode: languageCode) : ScriptType.latin);
    switch (s) {
      case ScriptType.kannada:
        return _customSecondsPerGraphemeKannada ?? config.secondsPerGraphemeKannada;
      case ScriptType.devanagari:
        return _customSecondsPerGraphemeDevanagari ?? config.secondsPerGraphemeDevanagari;
      case ScriptType.latin:
        return _customSecondsPerGraphemeLatin ?? config.secondsPerGraphemeLatin;
    }
  }

  /// Sets custom writing seconds per grapheme for a given script.
  void setSecondsPerGrapheme(ScriptType script, double seconds) {
    final clamped = seconds.clamp(0.1, 2.0);
    switch (script) {
      case ScriptType.kannada:
        _customSecondsPerGraphemeKannada = clamped;
        break;
      case ScriptType.devanagari:
        _customSecondsPerGraphemeDevanagari = clamped;
        break;
      case ScriptType.latin:
        _customSecondsPerGraphemeLatin = clamped;
        break;
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

  /// Backwards-compatibility getter for tests.
  double get currentWritingSpeed {
    // Equivalent words/sec assuming ~5 graphemes per word
    final secPerGrapheme = getWritingSecondsPerGrapheme(script: ScriptType.latin);
    return secPerGrapheme > 0 ? (1.0 / (secPerGrapheme * 5.0)) : config.defaultWritingSpeed;
  }

  set writingSpeed(double wordsPerSec) {
    if (wordsPerSec > 0) {
      // 1 word = ~5 graphemes -> sec/grapheme = 1 / (wordsPerSec * 5)
      final secPerGrapheme = (1.0 / (wordsPerSec * 5.0)).clamp(0.1, 2.0);
      setSecondsPerGrapheme(ScriptType.latin, secPerGrapheme);
      setSecondsPerGrapheme(ScriptType.devanagari, secPerGrapheme * 1.35);
      setSecondsPerGrapheme(ScriptType.kannada, secPerGrapheme * 1.6);
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

  /// Computes the unjittered writing time budget in seconds for [chunk].
  ///
  /// Budget = ( graphemes * secondsPerGrapheme ) / tempo(t)
  double calculateWritingBudget(ChunkInfo chunk, {String? languageCode}) {
    final graphemes = countGraphemes(chunk.text);
    if (graphemes <= 0) return 0.0;

    final secPerGrapheme = getWritingSecondsPerGrapheme(
      text: chunk.text,
      languageCode: languageCode,
    );
    final tempo = currentTempo;
    return (graphemes * secPerGrapheme) / tempo;
  }

  /// Computes the silence pause duration following [chunk].
  ///
  /// Formula:
  ///   writingBudget = ( graphemes * secondsPerGrapheme ) / tempo(t)
  ///   writingTime   = writingBudget * jitter
  ///   netWriting    = max(minGap, writingTime - speechDuration)
  ///   gap           = netWriting + boundaryPause
  ///
  /// When speech duration exceeds the writing budget, [netWriting] strictly
  /// evaluates to [minGapSeconds], ensuring the gap is never negative and
  /// boundary pauses are always preserved.
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

    // 2. Writing time budget from START of speech.
    final writingBudget = calculateWritingBudget(chunk, languageCode: languageCode);
    final jitter = applyJitter ? _generateLognormalJitter() : 1.0;
    final writingTime = writingBudget * jitter;

    // 3. Net writing time remaining after speech ends: max(minGap, writingTime - speechDuration)
    final netWritingTime = math.max(
      config.minGapSeconds,
      writingTime - speechDurationSeconds,
    );

    // 4. Boundary pause added on top of writing time.
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

  /// Slower adaptation: increases seconds per grapheme slightly.
  void adaptSlower([ScriptType? script]) {
    final s = script ?? ScriptType.latin;
    final current = getWritingSecondsPerGrapheme(script: s);
    setSecondsPerGrapheme(s, current + 0.02);
  }

  /// Faster adaptation: decreases seconds per grapheme slightly.
  void adaptFaster([ScriptType? script]) {
    final s = script ?? ScriptType.latin;
    final current = getWritingSecondsPerGrapheme(script: s);
    setSecondsPerGrapheme(s, math.max(0.10, current - 0.015));
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
