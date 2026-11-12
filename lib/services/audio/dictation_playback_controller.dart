import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import '../../config/pacing_config.dart';
import '../../core/chunker/chunk_info.dart';
import '../../core/pacing/pacing_engine.dart';
import '../tts/voice_engine.dart';
import 'pausable_gap_timer.dart';
import 'temp_audio_file_manager.dart';

/// States of dictation playback.
enum DictationPlaybackState {
  idle,
  preparing,
  playingChunk,
  waitingGap,
  paused,
  completed,
  error,
}

/// Record of per-chunk execution for session observability, drift tracking, and copyable audit tables.
class DictationSessionLog {
  const DictationSessionLog({
    required this.chunkIndex,
    required this.text,
    int? graphemes,
    double? speechDurationSeconds,
    double? writingBudgetSeconds,
    required this.gapSeconds,
    double? totalCycleSeconds,
    required this.boundaryType,
    int? wordCount,
    double? audioDurationSeconds,
    double? realTimeFactor,
    this.userAction = 'none',
    this.synthesisTimeMs = 0,
    this.voiceSpeed = 1.0,
    this.isFromCache = false,
  })  : graphemes = graphemes ?? (wordCount != null ? wordCount * 5 : 0),
        speechDurationSeconds = speechDurationSeconds ?? (audioDurationSeconds ?? 0.0),
        writingBudgetSeconds = writingBudgetSeconds ?? 0.0,
        totalCycleSeconds = totalCycleSeconds ??
            ((speechDurationSeconds ?? (audioDurationSeconds ?? 0.0)) + gapSeconds);

  final int chunkIndex;
  final String text;
  final int graphemes;
  final double speechDurationSeconds;
  final double writingBudgetSeconds;
  final double gapSeconds;
  final double totalCycleSeconds;
  final BoundaryType boundaryType;
  final String userAction;
  final int synthesisTimeMs;
  final double voiceSpeed;
  final bool isFromCache;

  // Backwards compatibility getters
  int get wordCount => text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  double get realTimeFactor =>
      speechDurationSeconds > 0 ? (synthesisTimeMs / 1000.0) / speechDurationSeconds : 0.0;
  double get audioDurationSeconds => speechDurationSeconds;

  DictationSessionLog copyWith({String? userAction}) {
    return DictationSessionLog(
      chunkIndex: chunkIndex,
      text: text,
      graphemes: graphemes,
      speechDurationSeconds: speechDurationSeconds,
      writingBudgetSeconds: writingBudgetSeconds,
      gapSeconds: gapSeconds,
      totalCycleSeconds: totalCycleSeconds,
      boundaryType: boundaryType,
      userAction: userAction ?? this.userAction,
      synthesisTimeMs: synthesisTimeMs,
      voiceSpeed: voiceSpeed,
      isFromCache: isFromCache,
    );
  }

  @override
  String toString() {
    return '[Chunk #$chunkIndex] Graphemes: $graphemes | '
        'Speech: ${speechDurationSeconds.toStringAsFixed(2)}s | '
        'Budget: ${writingBudgetSeconds.toStringAsFixed(2)}s | '
        'Gap: ${gapSeconds.toStringAsFixed(2)}s | '
        'Cycle: ${totalCycleSeconds.toStringAsFixed(2)}s | '
        'Speed: ${voiceSpeed.toStringAsFixed(2)}x | '
        'Action: $userAction | '
        'Synth: ${synthesisTimeMs}ms${isFromCache ? " (Cached)" : ""} | '
        '"$text"';
  }

  /// Formats the session logs into a clean, GitHub Flavored Markdown table.
  static String formatSessionTableMarkdown(List<DictationSessionLog> logs) {
    final b = StringBuffer();
    b.writeln('| # | Graphemes | Speech (s) | Writing Budget (s) | Gap (s) | Total Cycle (s) | Boundary | User Action | Source | Chunk Text |');
    b.writeln('|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---|');
    for (final l in logs) {
      b.writeln(
        '| #${l.chunkIndex} | ${l.graphemes} | ${l.speechDurationSeconds.toStringAsFixed(2)} | '
        '${l.writingBudgetSeconds.toStringAsFixed(2)} | ${l.gapSeconds.toStringAsFixed(2)} | '
        '${l.totalCycleSeconds.toStringAsFixed(2)} | ${l.boundaryType.name} | ${l.userAction} | '
        '${l.isFromCache ? "⚡ Cache" : "☁️ API"} | "${l.text.replaceAll('|', '\\|')}" |',
      );
    }
    return b.toString();
  }
}

/// Abstract audio player interface allowing pure Dart unit tests without native audio hardware.
abstract class DictationAudioPlayer {
  Stream<void> get onPlayerComplete;
  Future<void> play(String filePath);
  Future<void> playBytes(Uint8List bytes);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> dispose();
}

/// Default implementation wrapping [AudioPlayer] with [DeviceFileSource].
class DefaultDictationAudioPlayer implements DictationAudioPlayer {
  DefaultDictationAudioPlayer({AudioPlayer? player}) : _player = player ?? AudioPlayer();
  final AudioPlayer _player;

  @override
  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

  @override
  Future<void> play(String filePath) => _player.play(DeviceFileSource(filePath));

  @override
  Future<void> playBytes(Uint8List bytes) => _player.play(BytesSource(bytes, mimeType: 'audio/wav'));

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// Orchestrates dictation chunk playback, pausable gap timers, and TTS synthesis.
class DictationPlaybackController {
  DictationPlaybackController({
    required this.voiceEngine,
    required this.pacingEngine,
    this.config = PacingConfig.defaultConfig,
    int? speakerId,
    String? voice,
    String? language,
    DictationAudioPlayer? audioPlayer,
    TempAudioFileManager? tempFileManager,
  })  : _speakerId = speakerId ?? config.defaultSpeakerId,
        _voice = voice,
        _language = language,
        _audioPlayer = audioPlayer ?? DefaultDictationAudioPlayer(),
        _tempFileManager = tempFileManager ?? TempAudioFileManager();

  final VoiceEngine voiceEngine;
  final PacingEngine pacingEngine;
  final PacingConfig config;
  final DictationAudioPlayer _audioPlayer;
  final TempAudioFileManager _tempFileManager;

  int _speakerId;
  int get speakerId => _speakerId;
  set speakerId(int id) {
    _speakerId = id;
  }

  String? _voice;
  String? get voice => _voice;
  set voice(String? v) {
    _voice = v;
  }

  String? _language;
  String? get language => _language;
  set language(String? l) {
    _language = l;
  }

  DictationPlaybackState _state = DictationPlaybackState.idle;
  DictationPlaybackState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  int _currentChunkIndex = 0;
  int get currentChunkIndex => _currentChunkIndex;

  ChunkInfo? _currentChunk;
  ChunkInfo? get currentChunk => _currentChunk;

  List<ChunkInfo> _chunks = [];
  List<ChunkInfo> get chunks => List.unmodifiable(_chunks);

  final List<DictationSessionLog> _sessionLogs = [];
  List<DictationSessionLog> get sessionLogs => List.unmodifiable(_sessionLogs);

  PausableGapTimer? _currentGapTimer;
  Duration _currentGapRemaining = Duration.zero;
  Duration get currentGapRemaining => _currentGapRemaining;
  double _currentGapProgress = 0.0;
  double get currentGapProgress => _currentGapProgress;

  String? _currentTempWavPath;
  bool _isStopRequested = false;
  DictationPlaybackState _pausedFromState = DictationPlaybackState.idle;
  String _currentUserActionForChunk = 'none';

  // Stream controllers for UI observability
  final _stateController = StreamController<DictationPlaybackState>.broadcast();
  Stream<DictationPlaybackState> get onStateChanged => _stateController.stream;

  final _logController = StreamController<DictationSessionLog>.broadcast();
  Stream<DictationSessionLog> get onLogAdded => _logController.stream;

  final _gapTickController = StreamController<Duration>.broadcast();
  Stream<Duration> get onGapTick => _gapTickController.stream;

  final _errorController = StreamController<String?>.broadcast();
  Stream<String?> get onErrorChanged => _errorController.stream;

  /// Starts or restarts dictation from chunk index 0.
  Future<void> start(List<ChunkInfo> chunks) async {
    if (chunks.isEmpty) return;
    await stop();

    _chunks = List.from(chunks);
    _currentChunkIndex = 0;
    _isStopRequested = false;
    _errorMessage = null;
    _errorController.add(null);
    _sessionLogs.clear();

    await _runPlaybackLoop();
  }

  /// Retries the current chunk after an error (no skipping, no reordering).
  Future<void> retryCurrentChunk() async {
    if (_state != DictationPlaybackState.error) return;
    _errorMessage = null;
    _errorController.add(null);
    _isStopRequested = false;
    await _runPlaybackLoop();
  }

  void _recordUserAction(String action) {
    _currentUserActionForChunk = action;
    if (_sessionLogs.isNotEmpty) {
      final last = _sessionLogs.removeLast();
      final updated = last.copyWith(userAction: action);
      _sessionLogs.add(updated);
      _logController.add(updated);
    }
  }

  /// Sequentially synthesizes and plays chunks, enforcing gap timers.
  Future<void> _runPlaybackLoop() async {
    while (_currentChunkIndex < _chunks.length && !_isStopRequested) {
      final chunk = _chunks[_currentChunkIndex];
      _currentChunk = chunk;
      _currentUserActionForChunk = 'none';

      // 1. Prepare: Synthesize chunk
      _transitionTo(DictationPlaybackState.preparing);

      // Compute speed with long-word adaptation
      final baseRate = _speakerId != null ? config.kokoroSpeed : pacingEngine.gnaniSpeechRate;
      final speed = pacingEngine.calculateChunkVoiceSpeed(chunk, baseRate: baseRate);

      GeneratedAudio audio;
      final stopwatch = Stopwatch()..start();
      try {
        audio = await voiceEngine.synthesize(
          chunk.text,
          speakerId: _speakerId,
          voice: _voice,
          language: _language,
          speed: speed,
        );
        stopwatch.stop();
      } catch (e) {
        _errorMessage = e.toString();
        _errorController.add(_errorMessage);
        _transitionTo(DictationPlaybackState.error);
        return;
      }

      if (_isStopRequested) break;

      final synthMs = stopwatch.elapsedMilliseconds;
      final durationSec = audio.durationSeconds;

      // 2. Compute graphemes, writing budget, gap, and total cycle
      final graphemes = PacingEngine.countGraphemes(chunk.text);
      final writingBudget = pacingEngine.calculateWritingBudget(chunk, languageCode: _language);
      final gapSeconds = pacingEngine.calculateGap(
        chunk,
        speechDurationSeconds: durationSec,
        languageCode: _language,
      );
      final totalCycleSeconds = durationSec + gapSeconds;

      final log = DictationSessionLog(
        chunkIndex: _currentChunkIndex,
        text: chunk.text,
        graphemes: graphemes,
        speechDurationSeconds: durationSec,
        writingBudgetSeconds: writingBudget,
        gapSeconds: gapSeconds,
        totalCycleSeconds: totalCycleSeconds,
        boundaryType: chunk.boundaryType,
        userAction: _currentUserActionForChunk,
        synthesisTimeMs: synthMs,
        voiceSpeed: speed,
        isFromCache: audio.isFromCache,
      );
      _sessionLogs.add(log);
      _logController.add(log);

      // 3. Resolve audio file path
      String playFilePath;
      bool isTempFile = false;

      try {
        if (audio.audioFilePath != null && File(audio.audioFilePath!).existsSync()) {
          playFilePath = audio.audioFilePath!;
          isTempFile = false;
        } else if (audio.wavBytes != null) {
          playFilePath = await _tempFileManager.writeTempWavBytes(
            bytes: audio.wavBytes!,
            chunkIndex: _currentChunkIndex,
          );
          isTempFile = true;
          _currentTempWavPath = playFilePath;
        } else if (audio.samples != null && audio.samples!.isNotEmpty) {
          playFilePath = await _tempFileManager.writeTempWave(
            samples: audio.samples!,
            sampleRate: audio.sampleRate,
            chunkIndex: _currentChunkIndex,
          );
          isTempFile = true;
          _currentTempWavPath = playFilePath;
        } else {
          throw StateError('GeneratedAudio contained no playable audio data');
        }
      } catch (e) {
        _errorMessage = 'Failed to prepare audio file: $e';
        _errorController.add(_errorMessage);
        _transitionTo(DictationPlaybackState.error);
        return;
      }

      if (_isStopRequested) {
        if (isTempFile) await _tempFileManager.deleteTempWave(playFilePath);
        break;
      }

      // 4. Play audio chunk
      _transitionTo(DictationPlaybackState.playingChunk);

      final playCompleter = Completer<void>();
      late StreamSubscription<void> completeSub;

      completeSub = _audioPlayer.onPlayerComplete.listen((_) {
        completeSub.cancel();
        if (!playCompleter.isCompleted) {
          playCompleter.complete();
        }
      });

      await _audioPlayer.play(playFilePath);
      await playCompleter.future;

      if (isTempFile) {
        await _tempFileManager.deleteTempWave(playFilePath);
        _currentTempWavPath = null;
      }

      if (_isStopRequested) break;

      // 5. Run PausableGapTimer for the pacing silence gap.
      // Every chunk (including final chunk) executes its gap so the student can copy it down.
      final effectiveGap = gapSeconds > 0 ? gapSeconds : config.minGapSeconds;
      _transitionTo(DictationPlaybackState.waitingGap);

      final gapDuration = Duration(milliseconds: (effectiveGap * 1000).round());
      _currentGapRemaining = gapDuration;
      _currentGapProgress = 0.0;

      _currentGapTimer = PausableGapTimer(
        totalDuration: gapDuration,
        onTick: (remaining, progress) {
          _currentGapRemaining = remaining;
          _currentGapProgress = progress;
          _gapTickController.add(remaining);
        },
      );

      await _currentGapTimer!.run();
      _currentGapTimer = null;
      _currentGapRemaining = Duration.zero;
      _currentGapProgress = 1.0;

      if (_isStopRequested) break;

      _currentChunkIndex++;
    }

    if (!_isStopRequested && _state != DictationPlaybackState.error) {
      _transitionTo(DictationPlaybackState.completed);
    }
  }

  /// Tap-to-advance: skips the remaining silence gap, records 'next', speeds up pacing,
  /// and immediately starts the next chunk.
  void skipGap() {
    if (_state == DictationPlaybackState.waitingGap && _currentGapTimer != null) {
      _recordUserAction('next (advance)');
      final script = PacingEngine.detectScript(_currentChunk?.text ?? '', languageCode: _language);
      pacingEngine.adaptFaster(script);
      _currentGapTimer?.cancel();
    }
  }

  /// Slower: user requests slower pacing.
  void slower() {
    _recordUserAction('slower');
    final script = PacingEngine.detectScript(_currentChunk?.text ?? '', languageCode: _language);
    pacingEngine.adaptSlower(script);
  }

  /// Faster: user requests faster pacing.
  void faster() {
    _recordUserAction('faster');
    final script = PacingEngine.detectScript(_currentChunk?.text ?? '', languageCode: _language);
    pacingEngine.adaptFaster(script);
  }

  /// Rewinds to the previous chunk without calling API again if cached.
  Future<void> previousChunk() async {
    if (_chunks.isEmpty) return;
    _recordUserAction('back');
    _currentGapTimer?.cancel();
    _currentGapTimer = null;
    await _audioPlayer.stop();

    if (_currentTempWavPath != null) {
      await _tempFileManager.deleteTempWave(_currentTempWavPath!);
      _currentTempWavPath = null;
    }

    if (_currentChunkIndex > 0) {
      _currentChunkIndex--;
    }
    _isStopRequested = false;
    await _runPlaybackLoop();
  }

  /// Repeats the current chunk.
  Future<void> repeatCurrentChunk() async {
    if (_chunks.isEmpty) return;
    _recordUserAction('repeat');
    final script = PacingEngine.detectScript(_currentChunk?.text ?? '', languageCode: _language);
    pacingEngine.adaptSlower(script);

    _currentGapTimer?.cancel();
    _currentGapTimer = null;
    await _audioPlayer.stop();

    if (_currentTempWavPath != null) {
      await _tempFileManager.deleteTempWave(_currentTempWavPath!);
      _currentTempWavPath = null;
    }

    _isStopRequested = false;
    await _runPlaybackLoop();
  }

  /// Pauses playback. Tracks remaining time if paused during a silence gap.
  Future<void> pause() async {
    if (_state == DictationPlaybackState.paused ||
        _state == DictationPlaybackState.idle ||
        _state == DictationPlaybackState.completed) {
      return;
    }

    _pausedFromState = _state;

    if (_state == DictationPlaybackState.playingChunk) {
      await _audioPlayer.pause();
    } else if (_state == DictationPlaybackState.waitingGap) {
      _currentGapTimer?.pause();
    }

    _transitionTo(DictationPlaybackState.paused);
  }

  /// Resumes playback from paused position.
  Future<void> resume() async {
    if (_state != DictationPlaybackState.paused) return;

    final targetState = _pausedFromState;

    if (targetState == DictationPlaybackState.playingChunk) {
      _transitionTo(DictationPlaybackState.playingChunk);
      await _audioPlayer.resume();
    } else if (targetState == DictationPlaybackState.waitingGap) {
      _transitionTo(DictationPlaybackState.waitingGap);
      _currentGapTimer?.resume();
    } else {
      _transitionTo(targetState);
    }
  }

  /// Stops playback, clears timers, and cleans up temporary files.
  Future<void> stop() async {
    _isStopRequested = true;
    _currentGapTimer?.cancel();
    _currentGapTimer = null;
    await _audioPlayer.stop();

    if (_currentTempWavPath != null) {
      await _tempFileManager.deleteTempWave(_currentTempWavPath!);
      _currentTempWavPath = null;
    }

    await _tempFileManager.cleanupAll();
    _currentGapRemaining = Duration.zero;
    _currentGapProgress = 0.0;
    _transitionTo(DictationPlaybackState.idle);
  }

  void _transitionTo(DictationPlaybackState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  Future<void> dispose() async {
    await stop();
    await _audioPlayer.dispose();
    await _stateController.close();
    await _logController.close();
    await _gapTickController.close();
    await _errorController.close();
  }
}
