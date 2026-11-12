import 'dart:async';

/// Callback reporting remaining duration and elapsed progress [0.0, 1.0].
typedef GapTimerTick = void Function(Duration remaining, double progress);

/// A pausable, restartable timer for managing silence gaps between dictation chunks.
///
/// Features:
/// - Precise tracking of elapsed and remaining time.
/// - Pausable at any millisecond without losing remaining duration.
/// - Zero silence PCM generation (pure timer).
/// - Periodic progress callbacks for UI countdown display.
class PausableGapTimer {
  PausableGapTimer({
    required this.totalDuration,
    this.tickInterval = const Duration(milliseconds: 50),
    this.onTick,
  })  : _remaining = totalDuration,
        _initialTotal = totalDuration;

  final Duration totalDuration;
  final Duration _initialTotal;
  final Duration tickInterval;
  final GapTimerTick? onTick;

  Duration _remaining;
  DateTime? _lastResumeTime;
  Timer? _tickerTimer;
  Completer<void>? _completer;
  bool _isPaused = false;
  bool _isCancelled = false;

  Duration get remainingDuration => _remaining;
  Duration get totalGapDuration => _initialTotal;
  bool get isPaused => _isPaused;
  bool get isRunning => _tickerTimer != null && !_isPaused && !_isCancelled;

  /// Starts or resumes the gap timer. Returns a Future that completes when the gap ends.
  Future<void> run() {
    if (_completer != null && !_completer!.isCompleted) {
      return _completer!.future;
    }

    _completer = Completer<void>();
    _isPaused = false;
    _isCancelled = false;

    if (_remaining <= Duration.zero) {
      _notifyTick(Duration.zero, 1.0);
      _completer!.complete();
      return _completer!.future;
    }

    _startInternalTicker();
    return _completer!.future;
  }

  void pause() {
    if (_isPaused || _isCancelled || _tickerTimer == null) return;

    _updateRemainingTime();
    _tickerTimer?.cancel();
    _tickerTimer = null;
    _isPaused = true;
    _notifyTick(_remaining, _calculateProgress());
  }

  void resume() {
    if (!_isPaused || _isCancelled) return;

    _isPaused = false;
    if (_remaining <= Duration.zero) {
      _tickerTimer?.cancel();
      _notifyTick(Duration.zero, 1.0);
      if (_completer != null && !_completer!.isCompleted) {
        _completer!.complete();
      }
      return;
    }

    _startInternalTicker();
  }

  void cancel() {
    _isCancelled = true;
    _tickerTimer?.cancel();
    _tickerTimer = null;
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
    }
  }

  void _startInternalTicker() {
    _lastResumeTime = DateTime.now();
    _tickerTimer?.cancel();

    _notifyTick(_remaining, _calculateProgress());

    _tickerTimer = Timer.periodic(tickInterval, (timer) {
      _updateRemainingTime();

      if (_remaining <= Duration.zero) {
        timer.cancel();
        _tickerTimer = null;
        _remaining = Duration.zero;
        _notifyTick(Duration.zero, 1.0);
        if (_completer != null && !_completer!.isCompleted) {
          _completer!.complete();
        }
      } else {
        _notifyTick(_remaining, _calculateProgress());
      }
    });
  }

  void _updateRemainingTime() {
    if (_lastResumeTime != null) {
      final now = DateTime.now();
      final elapsedSinceResume = now.difference(_lastResumeTime!);
      _remaining -= elapsedSinceResume;
      _lastResumeTime = now;
      if (_remaining < Duration.zero) {
        _remaining = Duration.zero;
      }
    }
  }

  double _calculateProgress() {
    if (_initialTotal.inMicroseconds == 0) return 1.0;
    final elapsed = _initialTotal - _remaining;
    final progress = elapsed.inMicroseconds / _initialTotal.inMicroseconds;
    return progress.clamp(0.0, 1.0);
  }

  void _notifyTick(Duration remaining, double progress) {
    if (onTick != null && !_isCancelled) {
      onTick!(remaining, progress);
    }
  }
}
