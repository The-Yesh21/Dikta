import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/gnani_config.dart';
import '../../config/pacing_config.dart';
import '../../core/chunker/chunk_info.dart';
import '../../core/chunker/text_chunker.dart';
import '../../core/pacing/pacing_engine.dart';
import '../../core/pacing/pacing_feedback_loop.dart';
import '../../services/audio/dictation_playback_controller.dart';
import '../../services/storage/user_pacing_storage.dart';
import '../../services/tts/gnani_tts_engine.dart';
import 'live_tuning_panel.dart';
import 'voice_audition_screen.dart';
import 'writing_calibration_screen.dart';

/// Dictation App: Cloud-first MVP using Gnani Cloud TTS & Adaptive Grapheme Pacing.
/// Redesigned using the Unslop craft framework: calm, exact, notebook-inspired interface.
class DictationTestScreen extends StatefulWidget {
  const DictationTestScreen({super.key});

  @override
  State<DictationTestScreen> createState() => _DictationTestScreenState();
}

class _DictationTestScreenState extends State<DictationTestScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();

  late final GnaniTtsEngine _ttsEngine;
  late final PacingEngine _pacingEngine;
  DictationPlaybackController? _playbackController;

  bool _isEngineReady = false;
  String _statusMessage = 'Connecting Gnani Cloud...';

  // Subscriptions
  StreamSubscription<DictationPlaybackState>? _stateSub;
  StreamSubscription<DictationSessionLog>? _logSub;
  StreamSubscription<Duration>? _gapSub;
  StreamSubscription<String?>? _errorSub;
  StreamSubscription<bool>? _pacePromptSub;

  // Dedicated ValueNotifiers for jitter-free, 120fps smooth gap timer animation
  final ValueNotifier<double> _gapProgressNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<Duration> _gapRemainingNotifier = ValueNotifier<Duration>(Duration.zero);

  bool _showPacePrompt = false;
  bool _isLogsExpanded = false;

  DictationPlaybackState _playbackState = DictationPlaybackState.idle;
  final List<DictationSessionLog> _logs = [];
  ChunkInfo? _currentChunk;
  int _currentChunkIndex = 0;
  int _totalChunks = 0;
  String? _errorMessage;

  String _currentLanguage = 'en-IN';
  String _currentVoice = 'Shivani';

  static const List<Map<String, String>> sampleTexts = [
    {
      'lang': 'en-IN',
      'title': 'English · Mitochondria',
      'text':
          'Mitochondria are membrane-bound cell organelles that generate most of the chemical energy needed to power the biochemical reactions of the cell. Chemical energy produced by the mitochondria is stored in a small molecule called ATP.',
    },
    {
      'lang': 'hi-IN',
      'title': 'Hindi · प्रकाश संश्लेषण',
      'text':
          'प्रकाश संश्लेषण एक ऐसी जैविक प्रक्रिया है जिसके द्वारा हरे पौधे सूर्य के प्रकाश की ऊर्जा को रासायनिक ऊर्जा में परिवर्तित करते हैं। इस प्रक्रिया में पौधे वायुमंडल से कार्बन डाइऑक्साइड और मिट्टी से जल अवशोषित करते हैं।',
    },
    {
      'lang': 'kn-IN',
      'title': 'Kannada · ದ್ಯುತಿಸಂಶ್ಲೇಷಣೆ',
      'text':
          'ದ್ಯುತಿಸಂಶ್ಲೇಷಣೆಯು ಸಸ್ಯಗಳು ಸೂರ್ಯನ ಬೆಳಕು, ನೀರು ಮತ್ತು ಇಂಗಾಲದ ಡೈಆಕ್ಸೈಡ್ ಅನ್ನು ಬಳಸಿಕೊಂಡು ತಮ್ಮ ಆಹಾರವನ್ನು ತಾವೇ ತಯಾರಿಸಿಕೊಳ್ಳುವ ಒಂದು ಅದ್ಭುತ ಜೈವಿಕ ಪ್ರಕ್ರಿಯೆಯಾಗಿದೆ. ಈ ಕ್ರಿಯೆಯು ಹರಿದ್ರೇಣುವಿನ ಕ್ಲೋರೋಫಿಲ್ ವರ್ಣದ್ರವ್ಯದ ಸಹಾಯದಿಂದ ಜರುಗುತ್ತದೆ.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _textController.text = sampleTexts.first['text']!;
    _initEngine();
  }

  Future<void> _initEngine() async {
    _ttsEngine = GnaniTtsEngine();
    _pacingEngine = PacingEngine(config: PacingConfig.defaultConfig);

    // Apply writer-friendly defaults: slower speech rate for dictation, tight gaps (max 7s)
    _pacingEngine.gnaniSpeechRate = 0.85; // Slower clear speech for dictation
    _pacingEngine.maxGapSeconds = 7.0;    // Human gap between phrases (never 30-50s)
    _pacingEngine.userLpm = 90.0;         // Natural student writing speed

    // Load saved user profile if calibrated
    try {
      final storage = UserPacingStorageService();
      final profile = await storage.getProfile();
      if (profile != null) {
        final script = PacingEngine.detectScript('', languageCode: _currentLanguage);
        final savedLpm = profile.calibratedLpm[script];
        if (savedLpm != null && savedLpm > 0) {
          _pacingEngine.userLpm = savedLpm;
        }
      }
    } catch (_) {}

    _playbackController = DictationPlaybackController(
      voiceEngine: _ttsEngine,
      pacingEngine: _pacingEngine,
      voice: _currentVoice,
      language: _currentLanguage,
      enablePrefetch: true,
    );

    _stateSub = _playbackController!.onStateChanged.listen((state) {
      if (mounted) {
        if (state == DictationPlaybackState.waitingGap) {
          _gapProgressNotifier.value = 0.0;
          _gapRemainingNotifier.value = _playbackController?.currentGapRemaining ?? Duration.zero;
        }
        setState(() {
          _playbackState = state;
          _currentChunk = _playbackController?.currentChunk;
          _currentChunkIndex = _playbackController?.currentChunkIndex ?? 0;
        });
      }
    });

    _logSub = _playbackController!.onLogAdded.listen((log) {
      if (mounted) {
        setState(() {
          _logs.insert(0, log);
        });
      }
    });

    // Smooth updates through ValueNotifiers without rebuilding the whole tree
    _gapSub = _playbackController!.onGapTick.listen((remaining) {
      _gapRemainingNotifier.value = remaining;
      _gapProgressNotifier.value = _playbackController?.currentGapProgress ?? 0.0;
    });

    _errorSub = _playbackController!.onErrorChanged.listen((err) {
      if (mounted) {
        setState(() {
          _errorMessage = err;
        });
      }
    });

    _pacePromptSub = _playbackController!.onPacePromptRequested.listen((shouldShow) {
      if (mounted) {
        setState(() {
          _showPacePrompt = shouldShow;
        });
      }
    });

    setState(() {
      _isEngineReady = true;
      _statusMessage = 'Gnani Cloud Engine Ready';
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _logSub?.cancel();
    _gapSub?.cancel();
    _errorSub?.cancel();
    _pacePromptSub?.cancel();
    _gapProgressNotifier.dispose();
    _gapRemainingNotifier.dispose();
    _playbackController?.dispose();
    _ttsEngine.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _startPlayback() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _playbackController == null) return;

    final chunker = TextChunker(config: PacingConfig.defaultConfig);
    final chunks = chunker.chunk(text);

    setState(() {
      _totalChunks = chunks.length;
      _logs.clear();
      _errorMessage = null;
    });

    _playbackController!.voice = _currentVoice;
    _playbackController!.language = _currentLanguage;

    await _playbackController!.start(chunks);
  }

  void _onLanguageChanged(String newLang) {
    setState(() {
      _currentLanguage = newLang;
      final voices = GnaniVoiceCatalog.getVoicesForLanguage(newLang);
      if (!voices.any((v) => v.name == _currentVoice)) {
        _currentVoice = voices.first.name;
      }
      _playbackController?.voice = _currentVoice;
      _playbackController?.language = _currentLanguage;

      final matchingSample = sampleTexts.firstWhere(
        (s) => s['lang'] == newLang,
        orElse: () => sampleTexts.first,
      );
      _textController.text = matchingSample['text']!;
    });
  }

  void _copySessionLogsToClipboard() {
    if (_logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No session logs to copy yet.')),
      );
      return;
    }

    final table = DictationSessionLog.formatSessionTableMarkdown(_logs.reversed.toList());
    Clipboard.setData(ClipboardData(text: table));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${_logs.length} chunk log rows (Markdown)!')),
    );
  }

  void _openCalibrationScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WritingCalibrationScreen(
          language: _currentLanguage,
          voiceEngine: _ttsEngine,
          onLpmCalibrated: (script, lpm) {
            _pacingEngine.userLpm = lpm;
            _playbackController?.feedbackLoop.reset(newInitialLpm: lpm);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Set ${script.name.toUpperCase()} writing speed to ${lpm.toStringAsFixed(1)} LPM',
                ),
              ),
            );
            setState(() {});
          },
          onSpeedCalibrated: (script, secPerGrapheme) {
            _pacingEngine.setSecondsPerGrapheme(script, secPerGrapheme);
            setState(() {});
          },
        ),
      ),
    );
  }

  void _openLiveTuningPanel() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LiveTuningPanel(
          pacingEngine: _pacingEngine,
          onChanged: () => setState(() {}),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Ink & Paper Palette (Unslop)
    const backgroundParchment = Color(0xFFFBF9F5);
    const inkSlate = Color(0xFF0F172A);
    const inkMuted = Color(0xFF64748B);
    const hairlineBorder = Color(0xFFE2E8F0);

    return Scaffold(
      backgroundColor: backgroundParchment,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dikta',
              style: TextStyle(
                fontFamily: 'serif',
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: inkSlate,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'Handwriting Dictation Companion',
              style: TextStyle(
                fontSize: 11,
                color: inkMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: hairlineBorder, height: 1),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note, color: inkSlate),
            tooltip: 'Calibrate Handwriting Speed',
            onPressed: _openCalibrationScreen,
          ),
          IconButton(
            icon: const Icon(Icons.tune, color: inkSlate),
            tooltip: 'Live Tuning Panel',
            onPressed: _openLiveTuningPanel,
          ),
          IconButton(
            icon: const Icon(Icons.record_voice_over_outlined, color: inkSlate),
            tooltip: 'Audition Voices',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VoiceAuditionScreen(
                    selectedVoiceName: _currentVoice,
                    selectedLanguage: _currentLanguage,
                    onSelectVoice: (voiceName, lang) {
                      setState(() {
                        _currentVoice = voiceName;
                        _currentLanguage = lang;
                        _playbackController?.voice = voiceName;
                        _playbackController?.language = lang;
                      });
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildPacingStatusBar(),
          if (_errorMessage != null) _buildErrorBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              children: [
                _buildActiveDictationCard(),
                const SizedBox(height: 12),
                _buildQuickPacingSettingsBar(),
                const SizedBox(height: 16),
                _buildControlsSection(),
                const SizedBox(height: 16),
                _buildPacePromptCard(),
                _buildLanguageAndNoteSection(),
                const SizedBox(height: 16),
                _buildSessionLogSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Status bar showing engine state and adaptive LPM
  Widget _buildPacingStatusBar() {
    final isLocked = _playbackController?.feedbackLoop.isLocked ?? false;
    final currentAlpha = _playbackController?.feedbackLoop.currentAlpha ?? 0.25;
    final userLpm = _pacingEngine.userLpm;

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _playbackState == DictationPlaybackState.playingChunk
                      ? const Color(0xFF10B981)
                      : _playbackState == DictationPlaybackState.waitingGap
                          ? const Color(0xFF3B82F6)
                          : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _playbackState == DictationPlaybackState.playingChunk
                    ? 'Speaking chunk (${_pacingEngine.gnaniSpeechRate.toStringAsFixed(2)}x)'
                    : _playbackState == DictationPlaybackState.waitingGap
                        ? 'Writing pause (≤${_pacingEngine.maxGapSeconds.toInt()}s)'
                        : _playbackState == DictationPlaybackState.preparing
                            ? 'Preparing audio'
                            : 'Ready',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isLocked ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isLocked ? const Color(0xFFA7F3D0) : const Color(0xFFCBD5E1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isLocked ? Icons.lock_outline : Icons.speed,
                  size: 13,
                  color: isLocked ? const Color(0xFF047857) : const Color(0xFF475569),
                ),
                const SizedBox(width: 4),
                Text(
                  isLocked
                      ? '${userLpm.toStringAsFixed(0)} LPM · Locked'
                      : '${userLpm.toStringAsFixed(0)} LPM · α=${currentAlpha.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isLocked ? const Color(0xFF047857) : const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The Hero Moment: Ruled Notebook Note Sheet for Dictation
  Widget _buildActiveDictationCard() {
    final isPlaying = _playbackState == DictationPlaybackState.playingChunk;
    final isPreparing = _playbackState == DictationPlaybackState.preparing;
    final isGap = _playbackState == DictationPlaybackState.waitingGap;
    final isPaused = _playbackState == DictationPlaybackState.paused;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Signature: Notebook Ruled Left Margin Indicator Line
              Container(
                width: 5,
                color: isGap
                    ? const Color(0xFF2563EB)
                    : isPlaying
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF43F5E).withOpacity(0.5),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Card Header Row: Progress & Boundary
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _totalChunks > 0
                                ? 'PHRASE ${_currentChunkIndex + 1} OF $_totalChunks'
                                : 'DICTATION READY',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          if (_currentChunk != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Text(
                                '${PacingEngine.countGraphemes(_currentChunk!.text)} letters · ${_currentChunk!.boundaryType.name}',
                                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Spoken Phrase Text with Smooth Animated Transition
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          _currentChunk?.text ?? 'Tap Start Dictation below to begin copying your notes.',
                          key: ValueKey(_currentChunk?.text ?? 'idle'),
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            height: 1.45,
                            color: _currentChunk != null ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                            fontFamily: 'serif',
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Writing Countdown & Instant Advance Moment (Smooth, Jitter-Free)
                      if (isGap) ...[
                        _SmoothGapCountdown(
                          progressNotifier: _gapProgressNotifier,
                          remainingNotifier: _gapRemainingNotifier,
                          onDone: () => _playbackController?.skipGap(),
                        ),
                      ] else if (isPlaying) ...[
                        Row(
                          children: [
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Speaking aloud at ${_pacingEngine.gnaniSpeechRate.toStringAsFixed(2)}x dictation speed...',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF059669), fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ] else if (isPreparing) ...[
                        const Row(
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3B82F6)),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Synthesizing next phrase via Gnani...',
                              style: TextStyle(fontSize: 12, color: Color(0xFF2563EB), fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ] else if (isPaused) ...[
                        const Text(
                          'Playback paused',
                          style: TextStyle(fontSize: 12, color: Color(0xFFD97706), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Direct quick controls for speech speed and gap pause length
  Widget _buildQuickPacingSettingsBar() {
    final speechRate = _pacingEngine.gnaniSpeechRate;
    final maxGap = _pacingEngine.maxGapSeconds;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          // Speech Speed Row (Dictation needs to be less)
          Row(
            children: [
              const Icon(Icons.record_voice_over, size: 14, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              const Text('Voice Speed:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
              const Spacer(),
              _buildSpeedPill(0.85, '0.85x (Slower)'),
              const SizedBox(width: 6),
              _buildSpeedPill(0.92, '0.92x'),
              const SizedBox(width: 6),
              _buildSpeedPill(1.00, '1.00x'),
            ],
          ),
          const Divider(height: 14, color: Color(0xFFF1F5F9)),
          // Gap Pause Length Row (Gap between parts needs to be less)
          Row(
            children: [
              const Icon(Icons.hourglass_bottom, size: 14, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              const Text('Pause Between Parts:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
              const Spacer(),
              _buildGapPill(4.0, 'Tight (4s)'),
              const SizedBox(width: 6),
              _buildGapPill(7.0, 'Normal (7s)'),
              const SizedBox(width: 6),
              _buildGapPill(11.0, 'Relaxed (11s)'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedPill(double rate, String label) {
    final isSelected = (_pacingEngine.gnaniSpeechRate - rate).abs() < 0.03;
    return InkWell(
      onTap: () {
        setState(() {
          _pacingEngine.gnaniSpeechRate = rate;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildGapPill(double maxGap, String label) {
    final isSelected = (_pacingEngine.maxGapSeconds - maxGap).abs() < 0.5;
    return InkWell(
      onTap: () {
        setState(() {
          _pacingEngine.maxGapSeconds = maxGap;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  /// Quiet, tactile dictation controls
  Widget _buildControlsSection() {
    final isPlaying = _playbackState == DictationPlaybackState.playingChunk;
    final isPreparing = _playbackState == DictationPlaybackState.preparing;
    final isGap = _playbackState == DictationPlaybackState.waitingGap;
    final isPaused = _playbackState == DictationPlaybackState.paused;
    final isActive = isPlaying || isGap || isPaused || isPreparing;

    return Column(
      children: [
        // Primary Play/Pause Row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isActive) ...[
              IconButton.outlined(
                icon: const Icon(Icons.replay_10, size: 22),
                tooltip: 'Rewind to previous chunk',
                onPressed: () => _playbackController?.previousChunk(),
                style: IconButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(width: 16),
            ],

            // Big Center Play/Pause Capsule
            FilledButton.icon(
              icon: Icon(
                isPlaying || isGap
                    ? Icons.pause
                    : isPaused
                        ? Icons.play_arrow
                        : Icons.play_arrow,
                size: 26,
              ),
              label: Text(
                isPlaying || isGap
                    ? 'Pause'
                    : isPaused
                        ? 'Resume'
                        : 'Start Dictation',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                elevation: 0,
              ),
              onPressed: (isPreparing || !_isEngineReady)
                  ? null
                  : () {
                      if (isPlaying || isGap) {
                        _playbackController?.pause();
                      } else if (isPaused) {
                        _playbackController?.resume();
                      } else {
                        _startPlayback();
                      }
                    },
            ),

            if (isActive) ...[
              const SizedBox(width: 16),
              IconButton.outlined(
                icon: const Icon(Icons.stop, color: Color(0xFFEF4444), size: 22),
                tooltip: 'Stop Dictation',
                onPressed: () => _playbackController?.stop(),
                style: IconButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFECACA)),
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ],
        ),

        // Secondary Voice Command Fallback Buttons (Back, Repeat, Slower, Faster)
        if (isActive) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTactilePillButton(
                icon: Icons.replay,
                label: 'Repeat',
                onPressed: () => _playbackController?.repeatCurrentChunk(),
              ),
              const SizedBox(width: 8),
              _buildTactilePillButton(
                icon: Icons.remove,
                label: 'Slower',
                tooltip: 'Lower writing speed (gives more gap time)',
                onPressed: () {
                  _playbackController?.slower();
                  setState(() {});
                },
              ),
              const SizedBox(width: 8),
              _buildTactilePillButton(
                icon: Icons.add,
                label: 'Faster',
                tooltip: 'Raise writing speed (tightens gaps)',
                onPressed: () {
                  _playbackController?.faster();
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildTactilePillButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    final btn = OutlinedButton.icon(
      icon: Icon(icon, size: 15, color: const Color(0xFF334155)),
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        backgroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      onPressed: onPressed,
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: btn);
    }
    return btn;
  }

  /// In-session Pace Feedback Prompt
  Widget _buildPacePromptCard() {
    if (!_showPacePrompt) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.tune, size: 16, color: Color(0xFF0F172A)),
                  SizedBox(width: 8),
                  Text(
                    'Pace check: Is the dictation comfortable for writing?',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: Color(0xFF94A3B8)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _showPacePrompt = false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _playbackController?.submitPaceFeedback(PacingSignalType.promptTooFast);
                    setState(() => _showPacePrompt = false);
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF94A3B8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Too Slow\n(Speed up)', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () {
                    _playbackController?.submitPaceFeedback(PacingSignalType.promptJustRight);
                    setState(() => _showPacePrompt = false);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE2E8F0),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Just Right\n(Keep pace)', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _playbackController?.submitPaceFeedback(PacingSignalType.promptTooSlow);
                    setState(() => _showPacePrompt = false);
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF94A3B8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Too Fast\n(More time)', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Clean Language, Voice, and Note Input Sheet
  Widget _buildLanguageAndNoteSection() {
    final voices = GnaniVoiceCatalog.getVoicesForLanguage(_currentLanguage);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Language Segmented Control
          Row(
            children: [
              _buildLanguageTab('en-IN', 'English'),
              const SizedBox(width: 8),
              _buildLanguageTab('hi-IN', 'Hindi'),
              const SizedBox(width: 8),
              _buildLanguageTab('kn-IN', 'Kannada'),
            ],
          ),
          const SizedBox(height: 12),

          // Voice Selector Row
          Row(
            children: [
              const Text('Voice:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: voices.any((v) => v.name == _currentVoice) ? _currentVoice : voices.first.name,
                      isExpanded: true,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
                      items: voices.map((v) {
                        return DropdownMenuItem<String>(
                          value: v.name,
                          child: Text('${v.name} (${v.gender[0]} · ${v.model.split('-').last})'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _currentVoice = val;
                            _playbackController?.voice = val;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Sample Note Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: sampleTexts.map((sample) {
                final isSelected = _textController.text == sample['text'];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(sample['title']!, style: const TextStyle(fontSize: 11)),
                    selected: isSelected,
                    selectedColor: const Color(0xFFE2E8F0),
                    backgroundColor: const Color(0xFFF8FAFC),
                    side: BorderSide(color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0)),
                    showCheckmark: false,
                    onSelected: (selected) {
                      if (selected) {
                        _onLanguageChanged(sample['lang']!);
                        _textController.text = sample['text']!;
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Note Text Input Area
          TextField(
            controller: _textController,
            maxLines: 5,
            style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF0F172A)),
            decoration: InputDecoration(
              hintText: 'Paste or type notes to dictate...',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF0F172A)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageTab(String langCode, String label) {
    final isSelected = _currentLanguage == langCode;
    return Expanded(
      child: InkWell(
        onTap: () => _onLanguageChanged(langCode),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : const Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }

  /// Collapsible Session Log Table (Clean unslop format)
  Widget _buildSessionLogSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(
              'Session Audit Log (${_logs.length} phrases)',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_logs.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16, color: Color(0xFF64748B)),
                    tooltip: 'Copy Markdown Table',
                    onPressed: _copySessionLogsToClipboard,
                  ),
                Icon(
                  _isLogsExpanded ? Icons.expand_less : Icons.expand_more,
                  color: const Color(0xFF64748B),
                ),
              ],
            ),
            onTap: () => setState(() => _isLogsExpanded = !_isLogsExpanded),
          ),
          if (_isLogsExpanded) ...[
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            if (_logs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No phrases dictated yet in this session.', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _logs.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: log.isFromCache ? const Color(0xFFFEF3C7) : const Color(0xFFE2E8F0),
                          child: Text(
                            '${log.chunkIndex + 1}',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: log.isFromCache ? const Color(0xFF92400E) : const Color(0xFF334155),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                log.text,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${log.graphemes} letters · Speech: ${log.speechDurationSeconds.toStringAsFixed(1)}s · Gap: ${log.gapSeconds.toStringAsFixed(1)}s · ${log.isFromCache ? '⚡ Cache' : '☁️ API'}',
                                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFEF2F2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage ?? 'An error occurred',
              style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C), fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            onPressed: () => _playbackController?.retryCurrentChunk(),
            child: const Text('Retry', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
  }
}

/// Dedicated, Butter-Smooth Gap Countdown Widget.
/// Uses [ValueListenableBuilder] and [TweenAnimationBuilder] to eliminate all timer jitter and screen rebuild glitches.
class _SmoothGapCountdown extends StatelessWidget {
  const _SmoothGapCountdown({
    required this.progressNotifier,
    required this.remainingNotifier,
    required this.onDone,
  });

  final ValueNotifier<double> progressNotifier;
  final ValueNotifier<Duration> remainingNotifier;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        children: [
          ValueListenableBuilder<double>(
            valueListenable: progressNotifier,
            builder: (context, progress, _) {
              return SizedBox(
                width: 22,
                height: 22,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: progress, end: progress),
                  duration: const Duration(milliseconds: 90),
                  curve: Curves.linear,
                  builder: (context, val, _) {
                    return CircularProgressIndicator(
                      value: (1.0 - val).clamp(0.0, 1.0),
                      strokeWidth: 2.5,
                      backgroundColor: const Color(0xFFDCFCE7),
                      color: const Color(0xFF16A34A),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ValueListenableBuilder<Duration>(
              valueListenable: remainingNotifier,
              builder: (context, remaining, _) {
                final sec = remaining.inMilliseconds / 1000.0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Copy now: ${sec.toStringAsFixed(1)}s writing pause',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF166534),
                      ),
                    ),
                    const Text(
                      'Tap "Done" when finished to advance faster',
                      style: TextStyle(fontSize: 11, color: Color(0xFF15803D)),
                    ),
                  ],
                );
              },
            ),
          ),
          FilledButton(
            onPressed: onDone,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward, size: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
