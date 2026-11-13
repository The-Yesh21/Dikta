/// Central configuration for closed-loop pacing adaptation, alpha scheduling,
/// and in-session user feedback prompts.
///
/// Per project specification in AGENTS.md:
/// "No magic numbers. Every tunable value lives in one config file."
class PacingFeedbackConfig {
  const PacingFeedbackConfig({
    this.initialAlpha = 0.25,
    this.minAlpha = 0.05,
    this.alphaDecayRate = 0.90,
    this.promptFirstChunkInterval = 5,
    this.promptSubsequentChunkInterval = 20,
    this.lockConsecutiveChunksThreshold = 6,
    this.repeatObservedRatio = 0.80,
    this.slowerObservedRatio = 0.85,
    this.fasterObservedRatio = 1.15,
    this.waitExtraRatio = 0.80,
    this.tooSlowPromptRatio = 0.85,
    this.tooFastPromptRatio = 1.15,
    this.minObservedRatio = 0.40,
    this.maxObservedRatio = 2.50,
    this.minLpm = 10.0,
    this.maxLpm = 150.0,
    this.consistencyTolerance = 0.15,
  });

  /// Starting adaptation learning rate alpha (default 0.25).
  final double initialAlpha;

  /// Lower floor for adaptation learning rate alpha once locked or consistent (default 0.05).
  final double minAlpha;

  /// Decay rate for alpha when corrections are small and consistent (default 0.90).
  final double alphaDecayRate;

  /// Number of initial chunks before presenting the first "Pace OK?" prompt (default 5).
  final int promptFirstChunkInterval;

  /// Chunk interval between subsequent "Pace OK?" prompts until pace is locked (default 20).
  final int promptSubsequentChunkInterval;

  /// Number of consecutive chunks with no manual correction required to lock pace (default 6).
  final int lockConsecutiveChunksThreshold;

  /// Synthetic observed ratio applied when user taps "repeat" (default 0.80 -> requires ~25% more time).
  final double repeatObservedRatio;

  /// Synthetic observed ratio applied when user taps "slower" (default 0.85).
  final double slowerObservedRatio;

  /// Synthetic observed ratio applied when user taps "faster" (default 1.15).
  final double fasterObservedRatio;

  /// Synthetic observed ratio applied when user gives generic "wait" command (default 0.80).
  final double waitExtraRatio;

  /// Synthetic observed ratio applied when user responds "Too slow" on prompt (default 1.20 -> user wants faster dictation).
  final double tooSlowPromptRatio;

  /// Synthetic observed ratio applied when user responds "Too fast" on prompt (default 0.80 -> user wants slower dictation).
  final double tooFastPromptRatio;

  /// Minimum clamp for observedRatio to prevent destabilizing update shocks (default 0.40).
  final double minObservedRatio;

  /// Maximum clamp for observedRatio to prevent runaway increases (default 2.50).
  final double maxObservedRatio;

  /// Hard lower bound for user LPM in letters per minute (default 10.0 LPM).
  final double minLpm;

  /// Hard upper bound for user LPM in letters per minute (default 150.0 LPM).
  final double maxLpm;

  /// Maximum deviation of observedRatio from 1.0 to be deemed consistent (default 0.15).
  final double consistencyTolerance;

  static const PacingFeedbackConfig defaultConfig = PacingFeedbackConfig();

  PacingFeedbackConfig copyWith({
    double? initialAlpha,
    double? minAlpha,
    double? alphaDecayRate,
    int? promptFirstChunkInterval,
    int? promptSubsequentChunkInterval,
    int? lockConsecutiveChunksThreshold,
    double? repeatObservedRatio,
    double? slowerObservedRatio,
    double? fasterObservedRatio,
    double? waitExtraRatio,
    double? tooSlowPromptRatio,
    double? tooFastPromptRatio,
    double? minObservedRatio,
    double? maxObservedRatio,
    double? minLpm,
    double? maxLpm,
    double? consistencyTolerance,
  }) {
    return PacingFeedbackConfig(
      initialAlpha: initialAlpha ?? this.initialAlpha,
      minAlpha: minAlpha ?? this.minAlpha,
      alphaDecayRate: alphaDecayRate ?? this.alphaDecayRate,
      promptFirstChunkInterval: promptFirstChunkInterval ?? this.promptFirstChunkInterval,
      promptSubsequentChunkInterval: promptSubsequentChunkInterval ?? this.promptSubsequentChunkInterval,
      lockConsecutiveChunksThreshold: lockConsecutiveChunksThreshold ?? this.lockConsecutiveChunksThreshold,
      repeatObservedRatio: repeatObservedRatio ?? this.repeatObservedRatio,
      slowerObservedRatio: slowerObservedRatio ?? this.slowerObservedRatio,
      fasterObservedRatio: fasterObservedRatio ?? this.fasterObservedRatio,
      waitExtraRatio: waitExtraRatio ?? this.waitExtraRatio,
      tooSlowPromptRatio: tooSlowPromptRatio ?? this.tooSlowPromptRatio,
      tooFastPromptRatio: tooFastPromptRatio ?? this.tooFastPromptRatio,
      minObservedRatio: minObservedRatio ?? this.minObservedRatio,
      maxObservedRatio: maxObservedRatio ?? this.maxObservedRatio,
      minLpm: minLpm ?? this.minLpm,
      maxLpm: maxLpm ?? this.maxLpm,
      consistencyTolerance: consistencyTolerance ?? this.consistencyTolerance,
    );
  }
}
