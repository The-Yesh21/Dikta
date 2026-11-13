import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/pacing_priors.dart';
import '../../core/pacing/pacing_engine.dart';
import '../../services/audio/dictation_playback_controller.dart';
import '../../services/storage/user_pacing_storage.dart';
import '../../services/tts/voice_engine.dart';

/// Supported steps in the calibration flow.
enum CalibrationStep {
  pickLanguage,
  pickAgeGroup,
  dictation,
  completed,
}

/// Screen for measuring individual user handwriting speed through audio dictation.
class WritingCalibrationScreen extends StatefulWidget {
  const WritingCalibrationScreen({
    super.key,
    this.language = 'en-IN',
    this.userId = UserPacingStorageService.defaultUserId,
    this.voiceEngine,
    this.audioPlayer,
    this.storageService,
    this.onLpmCalibrated,
    this.onSpeedCalibrated,
    this.onSkip,
  });

  final String language;
  final String userId;
  final VoiceEngine? voiceEngine;
  final DictationAudioPlayer? audioPlayer;
  final UserPacingStorageService? storageService;

  /// Callback with calibrated Letters Per Minute (LPM).
  final void Function(ScriptType script, double lpm)? onLpmCalibrated;

  /// Legacy callback with writing seconds per grapheme for backward compatibility.
  final void Function(ScriptType script, double secondsPerGrapheme)? onSpeedCalibrated;

  final VoidCallback? onSkip;

  @override
  State<WritingCalibrationScreen> createState() => _WritingCalibrationScreenState();
}

class _WritingCalibrationScreenState extends State<WritingCalibrationScreen> {
  static const Map<String, List<String>> calibrationSentencesByLanguage = {
    'en-IN': [
      'Light travels faster than sound in air.',
      'Cell organelles generate chemical energy.',
    ],
    'hi-IN': [
      'पौधे सूर्य के प्रकाश से भोजन बनाते हैं।',
      'जल वाष्प बनकर आकाश में बादल बनाता है।',
    ],
    'kn-IN': [
      'ಸಸ್ಯಗಳು ಸೂರ್ಯನ ಬೆಳಕಿನಿಂದ ಆಹಾರ ತಯಾರಿಸುತ್ತವೆ.',
      'ನೀರು ಆವಿಯಾಗಿ ಆಕಾಶದಲ್ಲಿ ಮೋಡವಾಗುತ್ತದೆ.',
    ],
  };

  late String _selectedLanguage;
  AgeGroup _selectedAgeGroup = AgeGroup.age18Plus;
  CalibrationStep _currentStep = CalibrationStep.pickLanguage;

  late final UserPacingStorageService _storage;
  DictationAudioPlayer? _player;
  bool _ownsPlayer = false;

  // Dictation calibration state
  int _currentSentenceIndex = 0; // 0 or 1
  bool _isSpeaking = false;
  bool _isWriting = false;
  final Stopwatch _writingStopwatch = Stopwatch();
  Timer? _tickerTimer;
  double _currentElapsedSeconds = 0.0;

  double? _sentence1Lpm;
  double? _sentence2Lpm;
  int? _sentence1Graphemes;
  int? _sentence2Graphemes;
  double? _averageLpm;

  @override
  void initState() {
    super.initState();
    _selectedLanguage = widget.language;
    _storage = widget.storageService ?? UserPacingStorageService();

    if (widget.audioPlayer != null) {
      _player = widget.audioPlayer;
    } else {
      _player = DefaultDictationAudioPlayer();
      _ownsPlayer = true;
    }

    _loadExistingProfile();
  }

  Future<void> _loadExistingProfile() async {
    final profile = await _storage.getProfile(userId: widget.userId);
    if (profile?.ageGroup != null && mounted) {
      for (final ag in AgeGroup.values) {
        if (ag.label == profile!.ageGroup) {
          setState(() {
            _selectedAgeGroup = ag;
          });
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    _writingStopwatch.stop();
    if (_ownsPlayer) {
      _player?.dispose();
    }
    super.dispose();
  }

  ScriptType get _currentScript =>
      PacingEngine.detectScript('', languageCode: _selectedLanguage);

  List<String> get _sentences =>
      calibrationSentencesByLanguage[_selectedLanguage] ??
      calibrationSentencesByLanguage['en-IN']!;

  static int countGraphemesExcludingSpaces(String text) {
    if (text.isEmpty) return 0;
    return text.characters.where((c) => c.trim().isNotEmpty).length;
  }

  void _handleSkip() async {
    final fallbackLpm = _selectedAgeGroup.effectiveStartingLpm();
    final script = _currentScript;

    widget.onSkip?.call();
    widget.onLpmCalibrated?.call(script, fallbackLpm);
    widget.onSpeedCalibrated?.call(script, 60.0 / fallbackLpm);

    await _storage.saveCalibratedLpm(
      userId: widget.userId,
      script: script,
      lpm: fallbackLpm,
    );
    await _storage.saveAgeGroup(
      userId: widget.userId,
      ageGroup: _selectedAgeGroup.label,
    );

    if (mounted) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _startSentenceAudio() async {
    final sentence = _sentences[_currentSentenceIndex];
    setState(() {
      _isSpeaking = true;
      _isWriting = false;
      _currentElapsedSeconds = 0.0;
    });

    try {
      if (widget.voiceEngine != null && _player != null) {
        final generated = await widget.voiceEngine!.synthesize(
          sentence,
          language: _selectedLanguage,
        );

        final completer = Completer<void>();
        late final StreamSubscription sub;
        sub = _player!.onPlayerComplete.listen((_) {
          if (!completer.isCompleted) {
            completer.complete();
          }
        });

        // Safety fallback timeout based on generated audio duration + 1s
        final durationMs = (generated.durationSeconds * 1000).toInt().clamp(500, 15000);
        final safetyTimer = Timer(Duration(milliseconds: durationMs + 1000), () {
          if (!completer.isCompleted) {
            completer.complete();
          }
        });

        if (generated.audioFilePath != null) {
          await _player!.play(generated.audioFilePath!);
        } else if (generated.wavBytes != null) {
          await _player!.playBytes(generated.wavBytes!);
        }

        await completer.future;
        safetyTimer.cancel();
        sub.cancel();
      } else {
        // Fallback simulated dictation reading time (2.0s)
        await Future.delayed(const Duration(milliseconds: 2000));
      }
    } catch (_) {
      // If audio fails, grace period before writing starts
      await Future.delayed(const Duration(milliseconds: 1000));
    }

    if (!mounted) return;

    // SPEECH HAS ENDED -> Strictly start measurement from END OF SPEECH
    _startWritingTimer();
  }

  void _startWritingTimer() {
    setState(() {
      _isSpeaking = false;
      _isWriting = true;
      _writingStopwatch.reset();
      _writingStopwatch.start();
    });

    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        setState(() {
          _currentElapsedSeconds = _writingStopwatch.elapsedMilliseconds / 1000.0;
        });
      }
    });
  }

  Future<void> _finishSentenceWriting() async {
    _writingStopwatch.stop();
    _tickerTimer?.cancel();

    final elapsedSeconds = _writingStopwatch.elapsedMilliseconds / 1000.0;
    final elapsedMinutes = (elapsedSeconds <= 0 ? 0.1 : elapsedSeconds) / 60.0;
    final currentSentence = _sentences[_currentSentenceIndex];
    final graphemes = countGraphemesExcludingSpaces(currentSentence);

    // LPM strictly from END OF SPEECH to tap:
    final lpm = graphemes / elapsedMinutes;

    if (_currentSentenceIndex == 0) {
      setState(() {
        _sentence1Graphemes = graphemes;
        _sentence1Lpm = lpm;
        _isWriting = false;
        _currentSentenceIndex = 1;
      });
    } else {
      // Sentence 2 finished
      final avg = ((_sentence1Lpm ?? lpm) + lpm) / 2.0;
      final clampedAvg = avg.clamp(10.0, 180.0);

      setState(() {
        _sentence2Graphemes = graphemes;
        _sentence2Lpm = lpm;
        _averageLpm = clampedAvg;
        _isWriting = false;
        _currentStep = CalibrationStep.completed;
      });

      final script = _currentScript;
      widget.onLpmCalibrated?.call(script, clampedAvg);
      widget.onSpeedCalibrated?.call(script, 60.0 / clampedAvg);

      // Persist calibrated LPM and age group to storage
      await _storage.saveCalibratedLpm(
        userId: widget.userId,
        script: script,
        lpm: clampedAvg,
      );
      await _storage.saveAgeGroup(
        userId: widget.userId,
        ageGroup: _selectedAgeGroup.label,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Writing Calibration'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _handleSkip,
            child: const Text(
              'Skip',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildProgressHeader(),
              const SizedBox(height: 20),
              if (_currentStep == CalibrationStep.pickLanguage)
                _buildLanguageStep()
              else if (_currentStep == CalibrationStep.pickAgeGroup)
                _buildAgeGroupStep()
              else if (_currentStep == CalibrationStep.dictation)
                _buildDictationStep()
              else if (_currentStep == CalibrationStep.completed)
                _buildCompletedStep(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressHeader() {
    int activeIndex = 0;
    if (_currentStep == CalibrationStep.pickAgeGroup) activeIndex = 1;
    if (_currentStep == CalibrationStep.dictation) activeIndex = 2;
    if (_currentStep == CalibrationStep.completed) activeIndex = 3;

    return Row(
      children: [
        _buildStepBadge('1. Language', activeIndex >= 0, activeIndex == 0),
        const Expanded(child: Divider(thickness: 2)),
        _buildStepBadge('2. Age', activeIndex >= 1, activeIndex == 1),
        const Expanded(child: Divider(thickness: 2)),
        _buildStepBadge('3. Dictate', activeIndex >= 2, activeIndex == 2),
      ],
    );
  }

  Widget _buildStepBadge(String label, bool isDoneOrActive, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.teal
            : isDoneOrActive
                ? Colors.teal.shade100
                : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isActive
              ? Colors.white
              : isDoneOrActive
                  ? Colors.teal.shade900
                  : Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildLanguageStep() {
    final languages = [
      {'code': 'en-IN', 'name': 'English', 'script': 'Latin Script'},
      {'code': 'hi-IN', 'name': 'Hindi', 'script': 'Devanagari Script'},
      {'code': 'kn-IN', 'name': 'Kannada', 'script': 'Kannada Script'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Step 1: Pick Language',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose the language script you want to calibrate your handwriting pace for.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 20),
        ...languages.map((lang) {
          final isSelected = _selectedLanguage == lang['code'];
          return Card(
            elevation: isSelected ? 3 : 1,
            color: isSelected ? Colors.teal.shade50 : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isSelected ? Colors.teal : Colors.grey.shade300,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: ListTile(
              title: Text(
                lang['name']!,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(lang['script']!),
              trailing: isSelected
                  ? const Icon(Icons.check_circle, color: Colors.teal)
                  : const Icon(Icons.circle_outlined, color: Colors.grey),
              onTap: () {
                setState(() {
                  _selectedLanguage = lang['code']!;
                });
              },
            ),
          );
        }),
        const SizedBox(height: 24),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: () {
            setState(() {
              _currentStep = CalibrationStep.pickAgeGroup;
            });
          },
          child: const Text('Next: Choose Age Group', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  Widget _buildAgeGroupStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Step 2: Pick Age Group (Optional)',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Age priors set an empirical baseline handwriting speed and a safe fallback if dictation calibration is skipped.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 20),
        ...AgeGroup.values.map((group) {
          final isSelected = _selectedAgeGroup == group;
          final fallbackLpm = group.effectiveStartingLpm();
          return Card(
            elevation: isSelected ? 3 : 1,
            color: isSelected ? Colors.teal.shade50 : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isSelected ? Colors.teal : Colors.grey.shade300,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: ListTile(
              title: Text(
                'Age ${group.label}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Starting LPM fallback: ${fallbackLpm.toStringAsFixed(1)} letters/min (Prior: ${group.priorLpm.toInt()} LPM × 0.8 dictation factor)',
              ),
              trailing: isSelected
                  ? const Icon(Icons.check_circle, color: Colors.teal)
                  : const Icon(Icons.circle_outlined, color: Colors.grey),
              onTap: () {
                setState(() {
                  _selectedAgeGroup = group;
                });
              },
            ),
          );
        }),
        const SizedBox(height: 24),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: () {
            setState(() {
              _currentSentenceIndex = 0;
              _currentStep = CalibrationStep.dictation;
            });
          },
          child: const Text('Next: Calibrate via Dictation', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _handleSkip,
          child: Text('Skip & Use ${_selectedAgeGroup.label} Fallback (${_selectedAgeGroup.effectiveStartingLpm().toStringAsFixed(1)} LPM)'),
        ),
      ],
    );
  }

  Widget _buildDictationStep() {
    final currentSentence = _sentences[_currentSentenceIndex];
    final graphemeCount = countGraphemesExcludingSpaces(currentSentence);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Sentence ${_currentSentenceIndex + 1} of 2',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal),
            ),
            Text(
              '$graphemeCount letters (${_currentScript.name})',
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          color: Colors.teal.shade50,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentSentence,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.4),
                ),
                const SizedBox(height: 8),
                const Text(
                  '1. Tap "Listen & Dictate".\n2. Listen until the speech ends.\n3. Write the sentence down on paper.\n4. Tap "Done Writing" as soon as your pen lifts.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                '${_currentElapsedSeconds.toStringAsFixed(1)}s',
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.bold,
                  color: _isWriting
                      ? Colors.teal
                      : _isSpeaking
                          ? Colors.orange
                          : Colors.black54,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _isSpeaking
                    ? '🎧 App is dictating... please listen'
                    : _isWriting
                        ? '✍️ Writing time active! Tap Done when finished'
                        : 'Ready to listen',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _isSpeaking
                      ? Colors.orange.shade800
                      : _isWriting
                          ? Colors.teal.shade800
                          : Colors.black54,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (!_isSpeaking && !_isWriting)
          ElevatedButton.icon(
            icon: const Icon(Icons.volume_up),
            label: Text(
              'Listen & Dictate Sentence ${_currentSentenceIndex + 1}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: _startSentenceAudio,
          ),
        if (_isSpeaking)
          ElevatedButton.icon(
            icon: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            label: const Text('Playing Audio...', style: TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: null, // Disabled during speech
          ),
        if (_isWriting)
          ElevatedButton.icon(
            icon: const Icon(Icons.check_circle),
            label: const Text('Done Writing', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: _finishSentenceWriting,
          ),
      ],
    );
  }

  Widget _buildCompletedStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle_outline, size: 64, color: Colors.teal),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'Calibration Completed!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          color: Colors.teal.shade50,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Language Script: ${_currentScript.name.toUpperCase()}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Divider(),
                Text(
                  'Sentence 1 (${_sentence1Graphemes ?? 0} letters): ${_sentence1Lpm?.toStringAsFixed(1) ?? "--"} LPM',
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  'Sentence 2 (${_sentence2Graphemes ?? 0} letters): ${_sentence2Lpm?.toStringAsFixed(1) ?? "--"} LPM',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  'Average Calibrated Pace: ${_averageLpm?.toStringAsFixed(1) ?? "--"} LPM',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal),
                ),
                const SizedBox(height: 4),
                Text(
                  'Age ${_selectedAgeGroup.label} Prior Baseline: ${_selectedAgeGroup.effectiveStartingLpm().toStringAsFixed(1)} LPM',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: () {
            if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
          },
          child: const Text('Apply Calibrated Pace to Dictation', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () {
            setState(() {
              _currentSentenceIndex = 0;
              _sentence1Lpm = null;
              _sentence2Lpm = null;
              _averageLpm = null;
              _currentStep = CalibrationStep.dictation;
            });
          },
          child: const Text('Recalibrate'),
        ),
      ],
    );
  }
}
