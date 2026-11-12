import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/pacing/pacing_engine.dart';

/// Screen for measuring individual user handwriting speed at session start.
class WritingCalibrationScreen extends StatefulWidget {
  const WritingCalibrationScreen({
    super.key,
    required this.language,
    required this.onSpeedCalibrated,
    this.onSkip,
  });

  final String language;
  final void Function(ScriptType script, double secondsPerGrapheme) onSpeedCalibrated;
  final VoidCallback? onSkip;

  @override
  State<WritingCalibrationScreen> createState() => _WritingCalibrationScreenState();
}

class _WritingCalibrationScreenState extends State<WritingCalibrationScreen> {
  static const Map<String, String> calibrationSentences = {
    'en-IN': 'Cell organelles generate chemical energy.',
    'hi-IN': 'पौधे सूर्य के प्रकाश से ऊर्जा बनाते हैं।',
    'kn-IN': 'ಸಸ್ಯಗಳು ಸೂರ್ಯನ ಬೆಳಕಿನಿಂದ ಆಹಾರ ತಯಾರಿಸುತ್ತವೆ.',
  };

  late String _activeLanguage;
  late ScriptType _activeScript;
  late String _sentence;
  late int _graphemeCount;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  bool _isWriting = false;
  bool _isFinished = false;
  double _elapsedSeconds = 0.0;
  double? _calibratedSecondsPerGrapheme;

  @override
  void initState() {
    super.initState();
    _activeLanguage = widget.language;
    _updateSentence();
  }

  void _updateSentence() {
    _sentence = calibrationSentences[_activeLanguage] ?? calibrationSentences['en-IN']!;
    _activeScript = PacingEngine.detectScript(_sentence, languageCode: _activeLanguage);
    _graphemeCount = PacingEngine.countGraphemes(_sentence);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    setState(() {
      _stopwatch.reset();
      _stopwatch.start();
      _isWriting = true;
      _isFinished = false;
      _calibratedSecondsPerGrapheme = null;
    });

    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        setState(() {
          _elapsedSeconds = _stopwatch.elapsedMilliseconds / 1000.0;
        });
      }
    });
  }

  void _stopTimer() {
    _stopwatch.stop();
    _timer?.cancel();
    _elapsedSeconds = _stopwatch.elapsedMilliseconds / 1000.0;

    final secPerGrapheme = _graphemeCount > 0 ? _elapsedSeconds / _graphemeCount : 0.35;

    setState(() {
      _isWriting = false;
      _isFinished = true;
      _calibratedSecondsPerGrapheme = secPerGrapheme.clamp(0.12, 1.50);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Handwriting Speed Calibration'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () {
              widget.onSkip?.call();
              Navigator.pop(context);
            },
            child: const Text('Skip', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Copy the sentence below by hand on paper.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap "Start Writing" when your pen touches the paper, copy at your normal comfortable speed, and tap "Done" when you finish.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('English'),
                  selected: _activeLanguage == 'en-IN',
                  onSelected: (val) {
                    if (val && !_isWriting) {
                      setState(() {
                        _activeLanguage = 'en-IN';
                        _updateSentence();
                      });
                    }
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Hindi'),
                  selected: _activeLanguage == 'hi-IN',
                  onSelected: (val) {
                    if (val && !_isWriting) {
                      setState(() {
                        _activeLanguage = 'hi-IN';
                        _updateSentence();
                      });
                    }
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Kannada'),
                  selected: _activeLanguage == 'kn-IN',
                  onSelected: (val) {
                    if (val && !_isWriting) {
                      setState(() {
                        _activeLanguage = 'kn-IN';
                        _updateSentence();
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 3,
              color: Colors.teal.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _sentence,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Length: $_graphemeCount grapheme clusters (${_activeScript.name.toUpperCase()})',
                      style: TextStyle(fontSize: 12, color: Colors.teal.shade800),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '${_elapsedSeconds.toStringAsFixed(1)}s',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: _isWriting ? Colors.teal : Colors.black87,
                    ),
                  ),
                  Text(
                    _isWriting
                      ? '⏱️ Timer running... copy the sentence'
                      : _isFinished
                          ? '✅ Completed'
                          : 'Ready to begin',
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (!_isWriting && !_isFinished)
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Writing', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _startTimer,
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
                onPressed: _stopTimer,
              ),
            if (_isFinished && _calibratedSecondsPerGrapheme != null) ...[
              Card(
                elevation: 2,
                color: Colors.green.shade50,
                margin: const EdgeInsets.only(top: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Calibration Result:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Writing Pace: ${_calibratedSecondsPerGrapheme!.toStringAsFixed(3)} seconds / grapheme',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'Equivalent speed: ~${(60.0 / (_calibratedSecondsPerGrapheme! * 5.0)).round()} words / minute',
                        style: const TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Apply Calibrated Pace to Session',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  widget.onSpeedCalibrated(_activeScript, _calibratedSecondsPerGrapheme!);
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _startTimer,
                child: const Text('Recalibrate (Try Again)'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
