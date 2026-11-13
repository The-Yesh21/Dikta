/// Supported writing script families for handwriting dictation pacing.
enum ScriptType {
  latin,
  devanagari,
  kannada,
}

/// Central configuration for all pacing, chunking, and timing parameters.
///
/// Per project specification in AGENTS.md:
/// "No magic numbers. Every tunable value lives in one config file."
class PacingConfig {
  const PacingConfig({
    this.tempo0 = 1.0,
    this.tempoMin = 0.7,
    this.tauMinutes = 12.0,
    this.overlapFactor = 0.5,
    this.scriptFactorLatin = 1.0,
    this.scriptFactorDevanagari = 1.0,
    this.scriptFactorKannada = 1.0,
    this.dictationFactor = 0.8,
    this.defaultUserLpm = 48.0,
    this.secondsPerGraphemeLatin = 0.28,
    this.secondsPerGraphemeDevanagari = 0.38,
    this.secondsPerGraphemeKannada = 0.45,
    this.syntaxPauseCommaSeconds = 0.4,
    this.syntaxPauseSentenceSeconds = 1.2,
    this.syntaxPauseParagraphSeconds = 2.5,
    this.jitterSigma = 0.15,
    this.minGapSeconds = 0.3,
    this.maxGapSeconds = 60.0,
    this.fatigueStrength = 1.0,
    this.sawtoothIntervalMinutes = 5.0,
    this.sawtoothRecoveryRatio = 0.5,
    this.minWordsPerChunk = 3,
    this.maxWordsPerChunk = 8,
    this.targetWordsPerChunk = 5,
    this.voiceSpeedVariationPercent = 0.05,
    this.adaptiveSlowerDelta = 0.03,
    this.adaptiveFasterDelta = 0.02,
    this.ttsNumThreads = 4,
    this.lookaheadTargetChunks = 3,
    this.gnaniSpeechRate = 0.85,
    this.defaultWritingSpeed = 0.7,
    this.kokoroSpeed = 0.8,
    this.longWordCharThreshold = 6.0,
    this.longWordSpeedScale = 0.85,
    this.defaultSpeakerId = 0,
  });

  /// Energy at the start of a session (default 1.0).
  final double tempo0;

  /// Floor the tempo decays toward as fatigue builds (default 0.7).
  final double tempoMin;

  /// Time constant in minutes for fatigue tempo decay (default 12 min).
  final double tauMinutes;

  /// Fraction of speech duration overlapping with handwriting (default 0.5).
  final double overlapFactor;

  /// Writing time multiplier for Latin script (default 1.0).
  final double scriptFactorLatin;

  /// Writing time multiplier for Devanagari script (default 1.0).
  final double scriptFactorDevanagari;

  /// Writing time multiplier for Kannada script (default 1.0).
  final double scriptFactorKannada;

  /// Factor applied to age-based writing prior to account for dictation listening overhead (default 0.8).
  final double dictationFactor;

  /// Default handwriting speed in letters per minute (default 48.0 LPM).
  final double defaultUserLpm;

  /// Writing seconds per grapheme for Latin script (English) - default 0.28s.
  final double secondsPerGraphemeLatin;

  /// Writing seconds per grapheme for Devanagari script (Hindi) - default 0.38s.
  final double secondsPerGraphemeDevanagari;

  /// Writing seconds per grapheme for Kannada script - default 0.45s.
  final double secondsPerGraphemeKannada;

  /// Additive pause duration in seconds after a comma or clause boundary (default 0.4s).
  final double syntaxPauseCommaSeconds;

  /// Additive pause duration in seconds after a sentence end (default 1.2s).
  final double syntaxPauseSentenceSeconds;

  /// Additive pause duration in seconds after a paragraph end (default 2.5s).
  final double syntaxPauseParagraphSeconds;

  /// Standard deviation for log-normal jitter (default 0.15).
  final double jitterSigma;

  /// Minimum allowable silence gap in seconds (default 0.3s).
  final double minGapSeconds;

  /// Maximum allowable silence gap in seconds (default 14.0s) to prevent runaway pauses.
  final double maxGapSeconds;

  /// Multiplier for tempo decay (0.0 turns off fatigue, 1.0 is full fatigue).
  final double fatigueStrength;

  /// Time interval in minutes between periodic fatigue recovery breaths (default 5.0 min).
  final double sawtoothIntervalMinutes;

  /// Fraction of accumulated fatigue cleared during a breath (default 0.5).
  final double sawtoothRecoveryRatio;

  /// Minimum word threshold before allowing a chunk boundary.
  final int minWordsPerChunk;

  /// Hard upper limit of words permitted in a single chunk.
  final int maxWordsPerChunk;

  /// Target word count for natural dictation chunk size.
  final int targetWordsPerChunk;

  /// Maximum allowed speed variation per chunk (+/- 5%).
  final double voiceSpeedVariationPercent;

  /// Handwriting speed decrease delta upon receiving "slower" or "repeat".
  final double adaptiveSlowerDelta;

  /// Handwriting speed increase delta when user tap-advances or stays fast.
  final double adaptiveFasterDelta;

  /// Number of CPU threads for background TTS inference.
  final int ttsNumThreads;

  /// Target number of pre-synthesized chunks in the lookahead buffer.
  final int lookaheadTargetChunks;

  /// Gnani Cloud TTS speech speed multiplier (supported range: 0.85 to 1.15).
  final double gnaniSpeechRate;

  /// Default handwriting speed in words/sec (legacy backwards compatibility).
  final double defaultWritingSpeed;

  /// Kokoro offline speed multiplier.
  final double kokoroSpeed;

  /// Threshold for average characters per word to trigger long-word rate slowdown.
  final double longWordCharThreshold;

  /// Speed scaling factor applied to technical chunks with long words.
  final double longWordSpeedScale;

  /// Default speaker ID.
  final int defaultSpeakerId;

  /// Returns the script multiplier factor for the given [script].
  double getScriptFactor(ScriptType script) {
    switch (script) {
      case ScriptType.latin:
        return scriptFactorLatin;
      case ScriptType.devanagari:
        return scriptFactorDevanagari;
      case ScriptType.kannada:
        return scriptFactorKannada;
    }
  }

  /// Default configuration constants.
  static const PacingConfig defaultConfig = PacingConfig();

  PacingConfig copyWith({
    double? tempo0,
    double? tempoMin,
    double? tauMinutes,
    double? overlapFactor,
    double? scriptFactorLatin,
    double? scriptFactorDevanagari,
    double? scriptFactorKannada,
    double? dictationFactor,
    double? defaultUserLpm,
    double? secondsPerGraphemeLatin,
    double? secondsPerGraphemeDevanagari,
    double? secondsPerGraphemeKannada,
    double? syntaxPauseCommaSeconds,
    double? syntaxPauseSentenceSeconds,
    double? syntaxPauseParagraphSeconds,
    double? jitterSigma,
    double? minGapSeconds,
    double? maxGapSeconds,
    double? fatigueStrength,
    double? sawtoothIntervalMinutes,
    double? sawtoothRecoveryRatio,
    int? minWordsPerChunk,
    int? maxWordsPerChunk,
    int? targetWordsPerChunk,
    double? voiceSpeedVariationPercent,
    double? adaptiveSlowerDelta,
    double? adaptiveFasterDelta,
    int? ttsNumThreads,
    int? lookaheadTargetChunks,
    double? gnaniSpeechRate,
    double? defaultWritingSpeed,
    double? kokoroSpeed,
    double? longWordCharThreshold,
    double? longWordSpeedScale,
    int? defaultSpeakerId,
  }) {
    return PacingConfig(
      tempo0: tempo0 ?? this.tempo0,
      tempoMin: tempoMin ?? this.tempoMin,
      tauMinutes: tauMinutes ?? this.tauMinutes,
      overlapFactor: overlapFactor ?? this.overlapFactor,
      scriptFactorLatin: scriptFactorLatin ?? this.scriptFactorLatin,
      scriptFactorDevanagari: scriptFactorDevanagari ?? this.scriptFactorDevanagari,
      scriptFactorKannada: scriptFactorKannada ?? this.scriptFactorKannada,
      dictationFactor: dictationFactor ?? this.dictationFactor,
      defaultUserLpm: defaultUserLpm ?? this.defaultUserLpm,
      secondsPerGraphemeLatin: secondsPerGraphemeLatin ?? this.secondsPerGraphemeLatin,
      secondsPerGraphemeDevanagari: secondsPerGraphemeDevanagari ?? this.secondsPerGraphemeDevanagari,
      secondsPerGraphemeKannada: secondsPerGraphemeKannada ?? this.secondsPerGraphemeKannada,
      syntaxPauseCommaSeconds: syntaxPauseCommaSeconds ?? this.syntaxPauseCommaSeconds,
      syntaxPauseSentenceSeconds: syntaxPauseSentenceSeconds ?? this.syntaxPauseSentenceSeconds,
      syntaxPauseParagraphSeconds: syntaxPauseParagraphSeconds ?? this.syntaxPauseParagraphSeconds,
      jitterSigma: jitterSigma ?? this.jitterSigma,
      minGapSeconds: minGapSeconds ?? this.minGapSeconds,
      maxGapSeconds: maxGapSeconds ?? this.maxGapSeconds,
      fatigueStrength: fatigueStrength ?? this.fatigueStrength,
      sawtoothIntervalMinutes: sawtoothIntervalMinutes ?? this.sawtoothIntervalMinutes,
      sawtoothRecoveryRatio: sawtoothRecoveryRatio ?? this.sawtoothRecoveryRatio,
      minWordsPerChunk: minWordsPerChunk ?? this.minWordsPerChunk,
      maxWordsPerChunk: maxWordsPerChunk ?? this.maxWordsPerChunk,
      targetWordsPerChunk: targetWordsPerChunk ?? this.targetWordsPerChunk,
      voiceSpeedVariationPercent: voiceSpeedVariationPercent ?? this.voiceSpeedVariationPercent,
      adaptiveSlowerDelta: adaptiveSlowerDelta ?? this.adaptiveSlowerDelta,
      adaptiveFasterDelta: adaptiveFasterDelta ?? this.adaptiveFasterDelta,
      ttsNumThreads: ttsNumThreads ?? this.ttsNumThreads,
      lookaheadTargetChunks: lookaheadTargetChunks ?? this.lookaheadTargetChunks,
      gnaniSpeechRate: gnaniSpeechRate ?? this.gnaniSpeechRate,
      defaultWritingSpeed: defaultWritingSpeed ?? this.defaultWritingSpeed,
      kokoroSpeed: kokoroSpeed ?? this.kokoroSpeed,
      longWordCharThreshold: longWordCharThreshold ?? this.longWordCharThreshold,
      longWordSpeedScale: longWordSpeedScale ?? this.longWordSpeedScale,
      defaultSpeakerId: defaultSpeakerId ?? this.defaultSpeakerId,
    );
  }
}
