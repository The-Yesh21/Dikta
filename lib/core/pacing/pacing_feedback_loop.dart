import 'dart:math' as math;
import '../../config/pacing_feedback_config.dart';

/// Signal classification for in-session user behavior and pacing adjustments.
enum PacingSignalType {
  /// User pressed Next before the gap elapsed (user writes faster than assumed).
  nextEarly,

  /// User requested repeating the chunk (user needs more time).
  repeat,

  /// User requested slower dictation (user needs more time).
  slower,

  /// User paused or requested to wait (user needs more time).
  wait,

  /// User requested faster dictation.
  faster,

  /// In-session prompt response: "Too slow" (dictation pace is too slow, speed up / shorter gaps).
  promptTooSlow,

  /// In-session prompt response: "Just right".
  promptJustRight,

  /// In-session prompt response: "Too fast" (dictation pace is too fast, slow down / longer gaps).
  promptTooFast,

  /// Full silence gap elapsed with no user intervention (about right).
  noAction,
}

/// A structured feedback event with timing context.
class PacingSignal {
  const PacingSignal({
    required this.type,
    this.plannedGapSeconds,
    this.elapsedGapSeconds,
    this.speechDurationSeconds,
    this.overlapFactor,
    this.extraWaitSeconds,
  });

  final PacingSignalType type;
  final double? plannedGapSeconds;
  final double? elapsedGapSeconds;
  final double? speechDurationSeconds;
  final double? overlapFactor;
  final double? extraWaitSeconds;

  bool get isManualCorrection {
    switch (type) {
      case PacingSignalType.nextEarly:
      case PacingSignalType.repeat:
      case PacingSignalType.slower:
      case PacingSignalType.wait:
      case PacingSignalType.faster:
      case PacingSignalType.promptTooSlow:
      case PacingSignalType.promptTooFast:
        return true;
      case PacingSignalType.promptJustRight:
      case PacingSignalType.noAction:
        return false;
    }
  }

  factory PacingSignal.nextEarly({
    required double plannedGapSeconds,
    required double elapsedGapSeconds,
    double? speechDurationSeconds,
    double? overlapFactor,
  }) {
    return PacingSignal(
      type: PacingSignalType.nextEarly,
      plannedGapSeconds: plannedGapSeconds,
      elapsedGapSeconds: elapsedGapSeconds,
      speechDurationSeconds: speechDurationSeconds,
      overlapFactor: overlapFactor,
    );
  }

  factory PacingSignal.repeat() => const PacingSignal(type: PacingSignalType.repeat);

  factory PacingSignal.slower() => const PacingSignal(type: PacingSignalType.slower);

  factory PacingSignal.wait({double? extraWaitSeconds, double? plannedGapSeconds}) {
    return PacingSignal(
      type: PacingSignalType.wait,
      extraWaitSeconds: extraWaitSeconds,
      plannedGapSeconds: plannedGapSeconds,
    );
  }

  factory PacingSignal.faster() => const PacingSignal(type: PacingSignalType.faster);

  factory PacingSignal.promptTooSlow() =>
      const PacingSignal(type: PacingSignalType.promptTooSlow);

  factory PacingSignal.promptJustRight() =>
      const PacingSignal(type: PacingSignalType.promptJustRight);

  factory PacingSignal.promptTooFast() =>
      const PacingSignal(type: PacingSignalType.promptTooFast);

  factory PacingSignal.noAction() => const PacingSignal(type: PacingSignalType.noAction);
}

/// Audit record of an adaptation iteration.
class PacingFeedbackStepLog {
  const PacingFeedbackStepLog({
    required this.chunkIndex,
    required this.signalType,
    required this.observedRatio,
    required this.alpha,
    required this.previousLpm,
    required this.newLpm,
    required this.consecutiveConsistentChunks,
    required this.isLocked,
  });

  final int chunkIndex;
  final PacingSignalType signalType;
  final double observedRatio;
  final double alpha;
  final double previousLpm;
  final double newLpm;
  final int consecutiveConsistentChunks;
  final bool isLocked;

  @override
  String toString() {
    return 'Step #$chunkIndex | ${signalType.name} | Ratio: ${observedRatio.toStringAsFixed(2)} | '
        'Alpha: ${alpha.toStringAsFixed(3)} | LPM: ${previousLpm.toStringAsFixed(1)} -> ${newLpm.toStringAsFixed(1)} | '
        'Consistent: $consecutiveConsistentChunks | Locked: $isLocked';
  }
}

/// Closed-loop pacing adaptation engine.
///
/// Implements the project update rule:
/// ```
/// lpm_new = lpm * (1 + alpha * (observedRatio - 1))
/// ```
///
/// Pure Dart class separate from UI to allow deterministic unit testing.
class PacingFeedbackLoop {
  PacingFeedbackLoop({
    double initialLpm = 48.0,
    this.config = PacingFeedbackConfig.defaultConfig,
  })  : _currentLpm = initialLpm.clamp(config.minLpm, config.maxLpm),
        _alpha = config.initialAlpha;

  final PacingFeedbackConfig config;

  double _currentLpm;
  double _alpha;
  int _consecutiveConsistentChunks = 0;
  bool _isLocked = false;
  int _processedChunkCount = 0;

  final List<PacingFeedbackStepLog> _history = [];

  /// Current estimated writing speed in letters per minute.
  double get currentLpm => _currentLpm;

  /// Current adaptation learning rate alpha.
  double get currentAlpha => _alpha;

  /// Count of consecutive chunks without manual corrections or within consistency tolerance.
  int get consecutiveConsistentChunks => _consecutiveConsistentChunks;

  /// Whether the user pace has locked (after 6 consecutive consistent chunks).
  bool get isLocked => _isLocked;

  /// Total number of chunks processed through the feedback loop.
  int get processedChunkCount => _processedChunkCount;

  /// Complete adaptation audit log.
  List<PacingFeedbackStepLog> get history => List.unmodifiable(_history);

  /// Resets the feedback loop to an initial LPM and fresh state.
  void reset({double? newInitialLpm}) {
    if (newInitialLpm != null) {
      _currentLpm = newInitialLpm.clamp(config.minLpm, config.maxLpm);
    }
    _alpha = config.initialAlpha;
    _consecutiveConsistentChunks = 0;
    _isLocked = false;
    _processedChunkCount = 0;
    _history.clear();
  }

  /// Computes the [observedRatio] based on the user's signal:
  /// - Next early: ratio of planned time to elapsed time.
  /// - Repeat / Slower / Wait: adjusts ratio below 1.0 (requires more time).
  /// - No action / Just right: 1.0.
  double computeObservedRatio(PacingSignal signal) {
    switch (signal.type) {
      case PacingSignalType.nextEarly:
        final planned = signal.plannedGapSeconds ?? 1.0;
        final elapsed = signal.elapsedGapSeconds ?? planned;
        final speech = signal.speechDurationSeconds ?? 0.0;
        final overlap = signal.overlapFactor ?? 0.0;

        if (speech > 0.0 && overlap > 0.0) {
          final totalPlanned = planned + (overlap * speech);
          final totalObserved = math.max(0.05, elapsed + (overlap * speech));
          return (totalPlanned / totalObserved).clamp(
            config.minObservedRatio,
            config.maxObservedRatio,
          );
        } else {
          return (planned / math.max(0.05, elapsed)).clamp(
            config.minObservedRatio,
            config.maxObservedRatio,
          );
        }

      case PacingSignalType.repeat:
        return config.repeatObservedRatio;

      case PacingSignalType.slower:
        return config.slowerObservedRatio;

      case PacingSignalType.wait:
        if (signal.extraWaitSeconds != null &&
            signal.plannedGapSeconds != null &&
            signal.plannedGapSeconds! > 0) {
          final ratio = signal.plannedGapSeconds! /
              (signal.plannedGapSeconds! + signal.extraWaitSeconds!);
          return ratio.clamp(config.minObservedRatio, config.maxObservedRatio);
        }
        return config.waitExtraRatio;

      case PacingSignalType.faster:
        return config.fasterObservedRatio;

      case PacingSignalType.promptTooSlow:
        return config.tooSlowPromptRatio;

      case PacingSignalType.promptJustRight:
        return 1.0;

      case PacingSignalType.promptTooFast:
        return config.tooFastPromptRatio;

      case PacingSignalType.noAction:
        return 1.0;
    }
  }

  /// Processes [signal] for a chunk and updates [currentLpm] and [currentAlpha].
  PacingFeedbackStepLog processSignal(PacingSignal signal, {int? chunkIndex}) {
    _processedChunkCount++;
    final idx = chunkIndex ?? _processedChunkCount;

    final observedRatio = computeObservedRatio(signal);
    final previousLpm = _currentLpm;

    // Update rule: lpm_new = lpm * (1 + alpha * (observedRatio - 1))
    final delta = _alpha * (observedRatio - 1.0);
    final newLpm = (previousLpm * (1.0 + delta)).clamp(config.minLpm, config.maxLpm);
    _currentLpm = newLpm;

    // Consistency check:
    // Consistent if:
    // 1. Not a manual correction (e.g. noAction or promptJustRight)
    // 2. OR observedRatio is within tolerance of 1.0 (user has adapted close to target)
    final isConsistent = !signal.isManualCorrection ||
        (observedRatio - 1.0).abs() <= config.consistencyTolerance;

    if (isConsistent) {
      _consecutiveConsistentChunks++;
    } else {
      _consecutiveConsistentChunks = 0;
    }

    // Lock pace after 6 consecutive consistent chunks
    if (!_isLocked &&
        _consecutiveConsistentChunks >= config.lockConsecutiveChunksThreshold) {
      _isLocked = true;
    }

    // Alpha scheduling:
    // Once locked, pin alpha to minAlpha.
    // As corrections get consistent, decay alpha toward minAlpha.
    if (_isLocked) {
      _alpha = config.minAlpha;
    } else if (isConsistent) {
      _alpha = math.max(config.minAlpha, _alpha * config.alphaDecayRate);
    }

    final log = PacingFeedbackStepLog(
      chunkIndex: idx,
      signalType: signal.type,
      observedRatio: observedRatio,
      alpha: _alpha,
      previousLpm: previousLpm,
      newLpm: newLpm,
      consecutiveConsistentChunks: _consecutiveConsistentChunks,
      isLocked: _isLocked,
    );
    _history.add(log);
    return log;
  }

  /// Determines whether the in-session 'Pace OK?' prompt should be shown.
  ///
  /// Specification:
  /// "After first 5 chunks, and every 20 chunks until locked, show a quick 'Pace OK?' prompt"
  bool shouldShowPacePrompt(int chunkCount1Based) {
    if (_isLocked) return false;
    if (chunkCount1Based == config.promptFirstChunkInterval) return true;
    if (chunkCount1Based > config.promptFirstChunkInterval) {
      return (chunkCount1Based - config.promptFirstChunkInterval) %
              config.promptSubsequentChunkInterval ==
          0;
    }
    return false;
  }

  // Convenient trigger helpers
  PacingFeedbackStepLog onNextEarly({
    required double plannedGapSeconds,
    required double elapsedGapSeconds,
    double? speechDurationSeconds,
    double? overlapFactor,
    int? chunkIndex,
  }) {
    return processSignal(
      PacingSignal.nextEarly(
        plannedGapSeconds: plannedGapSeconds,
        elapsedGapSeconds: elapsedGapSeconds,
        speechDurationSeconds: speechDurationSeconds,
        overlapFactor: overlapFactor,
      ),
      chunkIndex: chunkIndex,
    );
  }

  PacingFeedbackStepLog onRepeat({int? chunkIndex}) {
    return processSignal(PacingSignal.repeat(), chunkIndex: chunkIndex);
  }

  PacingFeedbackStepLog onSlower({int? chunkIndex}) {
    return processSignal(PacingSignal.slower(), chunkIndex: chunkIndex);
  }

  PacingFeedbackStepLog onWait({
    double? extraWaitSeconds,
    double? plannedGapSeconds,
    int? chunkIndex,
  }) {
    return processSignal(
      PacingSignal.wait(
        extraWaitSeconds: extraWaitSeconds,
        plannedGapSeconds: plannedGapSeconds,
      ),
      chunkIndex: chunkIndex,
    );
  }

  PacingFeedbackStepLog onFaster({int? chunkIndex}) {
    return processSignal(PacingSignal.faster(), chunkIndex: chunkIndex);
  }

  PacingFeedbackStepLog onPromptResponse(PacingSignalType promptChoice, {int? chunkIndex}) {
    return processSignal(PacingSignal(type: promptChoice), chunkIndex: chunkIndex);
  }

  PacingFeedbackStepLog onNoAction({int? chunkIndex}) {
    return processSignal(PacingSignal.noAction(), chunkIndex: chunkIndex);
  }
}
