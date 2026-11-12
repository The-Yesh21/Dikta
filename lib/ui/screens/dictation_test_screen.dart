import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/gnani_config.dart';
import '../../config/pacing_config.dart';
import '../../core/chunker/chunk_info.dart';
import '../../core/chunker/text_chunker.dart';
import '../../core/pacing/pacing_engine.dart';
import '../../services/audio/dictation_playback_controller.dart';
import '../../services/tts/gnani_tts_engine.dart';
import 'live_tuning_panel.dart';
import 'voice_audition_screen.dart';
import 'writing_calibration_screen.dart';

/// Test screen for Dictation App: Cloud-first MVP using Gnani Cloud TTS & Grapheme Pacing.
class DictationTestScreen extends StatefulWidget {
  const DictationTestScreen({super.key});

  @override
  State<DictationTestScreen> createState() => _DictationTestScreenState();
}

class _DictationTestScreenState extends State<DictationTestScreen> {
  final TextEditingController _textController = TextEditingController();

  late final GnaniTtsEngine _ttsEngine;
  late final PacingEngine _pacingEngine;
  DictationPlaybackController? _playbackController;

  bool _isEngineReady = false;
  String _statusMessage = 'Initializing Gnani Cloud TTS...';

  // State subscriptions
  StreamSubscription<DictationPlaybackState>? _stateSub;
  StreamSubscription<DictationSessionLog>? _logSub;
  StreamSubscription<Duration>? _gapSub;
  StreamSubscription<String?>? _errorSub;

  DictationPlaybackState _playbackState = DictationPlaybackState.idle;
  final List<DictationSessionLog> _logs = [];
  Duration _remainingGap = Duration.zero;
  double _gapProgress = 0.0;
  ChunkInfo? _currentChunk;
  int _currentChunkIndex = 0;
  int _totalChunks = 0;
  String? _errorMessage;

  String _currentLanguage = 'en-IN';
  String _currentVoice = 'Shivani';

  static const List<Map<String, String>> sampleTexts = [
    {
      'lang': 'en-IN',
      'title': 'English: Mitochondria (Biology)',
      'text':
          'Mitochondria are membrane-bound cell organelles that generate most of the chemical energy needed to power the biochemical reactions of the cell. Chemical energy produced by the mitochondria is stored in a small molecule called ATP.',
    },
    {
      'lang': 'hi-IN',
      'title': 'Hindi: प्रकाश संश्लेषण (Biology)',
      'text':
          'प्रकाश संश्लेषण एक ऐसी जैविक प्रक्रिया है जिसके द्वारा हरे पौधे सूर्य के प्रकाश की ऊर्जा को रासायनिक ऊर्जा में परिवर्तित करते हैं। इस प्रक्रिया में पौधे वायुमंडल से कार्बन डाइऑक्साइड और मिट्टी से जल अवशोषित करते हैं।',
    },
    {
      'lang': 'kn-IN',
      'title': 'Kannada: ದ್ಯುತಿಸಂಶ್ಲೇಷಣೆ (Biology)',
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

  void _initEngine() {
    _ttsEngine = GnaniTtsEngine();
    _pacingEngine = PacingEngine(config: PacingConfig.defaultConfig);

    _playbackController = DictationPlaybackController(
      voiceEngine: _ttsEngine,
      pacingEngine: _pacingEngine,
      voice: _currentVoice,
      language: _currentLanguage,
    );

    _stateSub = _playbackController!.onStateChanged.listen((state) {
      if (mounted) {
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

    _gapSub = _playbackController!.onGapTick.listen((remaining) {
      if (mounted) {
        setState(() {
          _remainingGap = remaining;
          _gapProgress = _playbackController?.currentGapProgress ?? 0.0;
        });
      }
    });

    _errorSub = _playbackController!.onErrorChanged.listen((err) {
      if (mounted) {
        setState(() {
          _errorMessage = err;
        });
      }
    });

    setState(() {
      _isEngineReady = true;
      _statusMessage = 'Gnani Cloud TTS Ready';
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _logSub?.cancel();
    _gapSub?.cancel();
    _errorSub?.cancel();
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
      SnackBar(content: Text('Copied ${_logs.length} chunk log rows to clipboard (Markdown)!')),
    );
  }

  void _openCalibrationScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WritingCalibrationScreen(
          language: _currentLanguage,
          onSpeedCalibrated: (script, secPerGrapheme) {
            _pacingEngine.setSecondsPerGrapheme(script, secPerGrapheme);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Set ${script.name.toUpperCase()} writing speed to ${secPerGrapheme.toStringAsFixed(3)} s/grapheme',
                ),
              ),
            );
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dictation Cloud MVP (Gnani)'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: 'Calibrate Handwriting Speed',
            onPressed: _openCalibrationScreen,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Live Tuning Panel',
            onPressed: _openLiveTuningPanel,
          ),
          IconButton(
            icon: const Icon(Icons.record_voice_over),
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
          _buildStatusBar(),
          if (_errorMessage != null) _buildErrorCard(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildLanguageAndVoiceSelector(),
                const SizedBox(height: 12),
                _buildQuickTuningRow(),
                const SizedBox(height: 12),
                _buildSampleTextChips(),
                const SizedBox(height: 12),
                _buildTextInput(),
                const SizedBox(height: 16),
                _buildControls(),
                const SizedBox(height: 16),
                _buildCurrentChunkStatus(),
                const SizedBox(height: 16),
                _buildSessionLogList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final activeScript = PacingEngine.detectScript(_textController.text, languageCode: _currentLanguage);
    final secPerGrapheme = _pacingEngine.getWritingSecondsPerGrapheme(script: activeScript);

    return Container(
      width: double.infinity,
      color: Colors.teal.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.cloud_done, color: Colors.teal, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$_statusMessage | Pace: ${secPerGrapheme.toStringAsFixed(2)}s/gr',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal),
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('Calibrate', style: TextStyle(fontSize: 12)),
            onPressed: _openCalibrationScreen,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      width: double.infinity,
      color: Colors.red.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Playback Error (Chunk preserved)',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                Text(_errorMessage!, style: const TextStyle(color: Colors.black87, fontSize: 12)),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            onPressed: () => _playbackController?.retryCurrentChunk(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageAndVoiceSelector() {
    final voices = GnaniVoiceCatalog.getVoicesForLanguage(_currentLanguage);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Language & Cloud Voice', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _currentLanguage,
                    decoration: const InputDecoration(
                      labelText: 'Language',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'en-IN', child: Text('English (en-IN)')),
                      DropdownMenuItem(value: 'hi-IN', child: Text('Hindi (hi-IN)')),
                      DropdownMenuItem(value: 'kn-IN', child: Text('Kannada (kn-IN)')),
                    ],
                    onChanged: (val) {
                      if (val != null) _onLanguageChanged(val);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: voices.any((v) => v.name == _currentVoice) ? _currentVoice : voices.first.name,
                    decoration: const InputDecoration(
                      labelText: 'Voice',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: voices.map((v) {
                      return DropdownMenuItem<String>(
                        value: v.name,
                        child: Text(
                          '${v.name} (${v.gender[0]} • ${v.model.split('-').last})',
                          overflow: TextOverflow.ellipsis,
                        ),
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
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickTuningRow() {
    final activeScript = PacingEngine.detectScript(_textController.text, languageCode: _currentLanguage);
    final secPerGrapheme = _pacingEngine.getWritingSecondsPerGrapheme(script: activeScript);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${activeScript.name.toUpperCase()} Pace: ${secPerGrapheme.toStringAsFixed(2)}s / grapheme',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text('Live Tuning', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _openLiveTuningPanel,
                ),
              ],
            ),
            Slider(
              value: secPerGrapheme.clamp(0.12, 1.20),
              min: 0.12,
              max: 1.20,
              divisions: 54,
              activeColor: Colors.teal,
              label: '${secPerGrapheme.toStringAsFixed(2)} s/gr',
              onChanged: (val) {
                setState(() {
                  _pacingEngine.setSecondsPerGrapheme(activeScript, val);
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSampleTextChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: sampleTexts.map((sample) {
          final isSelected = _textController.text == sample['text'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(sample['title']!),
              selected: isSelected,
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
    );
  }

  Widget _buildTextInput() {
    return TextField(
      controller: _textController,
      maxLines: 4,
      decoration: InputDecoration(
        labelText: 'Text to Dictate',
        hintText: 'Enter text here...',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => _textController.clear(),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final isPlaying = _playbackState == DictationPlaybackState.playingChunk;
    final isPreparing = _playbackState == DictationPlaybackState.preparing;
    final isGap = _playbackState == DictationPlaybackState.waitingGap;
    final isPaused = _playbackState == DictationPlaybackState.paused;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: Icon(
                  isPlaying || isGap
                      ? Icons.pause
                      : isPaused
                          ? Icons.play_arrow
                          : Icons.record_voice_over,
                ),
                label: Text(
                  isPlaying || isGap
                      ? 'Pause'
                      : isPaused
                          ? 'Resume'
                          : 'Start Dictation',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: isPaused ? Colors.amber.shade800 : Colors.teal,
                  foregroundColor: Colors.white,
                ),
                onPressed: isPreparing
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
            ),
            if (isGap) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: 'Skip remaining gap and adapt faster',
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.skip_next),
                  label: const Text('Next', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _playbackController?.skipGap(),
                ),
              ),
            ],
            if (isPlaying || isPaused || isGap) ...[
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.stop),
                style: IconButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => _playbackController?.stop(),
              ),
            ],
          ],
        ),
        if (isPlaying || isPaused || isGap) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.fast_rewind),
                label: const Text('Back'),
                onPressed: () => _playbackController?.previousChunk(),
              ),
              TextButton.icon(
                icon: const Icon(Icons.replay),
                label: const Text('Repeat'),
                onPressed: () => _playbackController?.repeatCurrentChunk(),
              ),
              TextButton.icon(
                icon: const Icon(Icons.slow_motion_video),
                label: const Text('Slower'),
                onPressed: () {
                  _playbackController?.slower();
                  setState(() {});
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.speed),
                label: const Text('Faster'),
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

  Widget _buildCurrentChunkStatus() {
    final isPlaying = _playbackState == DictationPlaybackState.playingChunk;
    final isPreparing = _playbackState == DictationPlaybackState.preparing;
    final isGap = _playbackState == DictationPlaybackState.waitingGap;
    final isPaused = _playbackState == DictationPlaybackState.paused;

    Color cardColor = Colors.grey.shade100;
    String statusTitle = 'Idle';

    if (isPreparing) {
      cardColor = Colors.orange.shade50;
      statusTitle = '☁️ Calling Gnani TTS API...';
    } else if (isPlaying) {
      cardColor = Colors.green.shade50;
      statusTitle = 'Speaking Chunk (${_currentChunkIndex + 1} / $_totalChunks)';
    } else if (isGap) {
      cardColor = Colors.blue.shade50;
      statusTitle = 'Writing Pause (Gap Countdown)';
    } else if (isPaused) {
      cardColor = Colors.amber.shade50;
      statusTitle = 'Paused';
    }

    return Card(
      elevation: 2,
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  statusTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                if (isPreparing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (isGap)
                  Text(
                    '${(_remainingGap.inMilliseconds / 1000.0).toStringAsFixed(1)}s left',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
              ],
            ),
            if (isGap) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (1.0 - _gapProgress).clamp(0.0, 1.0),
                backgroundColor: Colors.blue.shade100,
                color: Colors.blue,
              ),
            ],
            if (_currentChunk != null) ...[
              const SizedBox(height: 10),
              Text(
                '"${_currentChunk!.text}"',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 4),
              Text(
                'Graphemes: ${PacingEngine.countGraphemes(_currentChunk!.text)} | Boundary: ${_currentChunk!.boundaryType.name}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSessionLogList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Session Chunk Audit Log',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54),
            ),
            if (_logs.isNotEmpty)
              ElevatedButton.icon(
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('Copy Table', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  backgroundColor: Colors.teal.shade50,
                  foregroundColor: Colors.teal.shade900,
                  elevation: 0,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _copySessionLogsToClipboard,
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_logs.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Text('No chunks dictated yet.', style: TextStyle(color: Colors.grey)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _logs.length,
            itemBuilder: (context, index) {
              final log = _logs[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: log.isFromCache ? Colors.amber.shade100 : Colors.teal.shade100,
                                child: Text(
                                  '#${log.chunkIndex}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: log.isFromCache ? Colors.amber.shade900 : Colors.teal.shade900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                log.text,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: log.isFromCache ? Colors.amber.shade50 : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              log.isFromCache ? '⚡ Cache' : '☁️ API',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: log.isFromCache ? Colors.amber.shade800 : Colors.blue.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          _buildMetricChip('Graphemes', '${log.graphemes}'),
                          _buildMetricChip('Speech', '${log.speechDurationSeconds.toStringAsFixed(2)}s'),
                          _buildMetricChip('Budget', '${log.writingBudgetSeconds.toStringAsFixed(2)}s'),
                          _buildMetricChip('Gap', '${log.gapSeconds.toStringAsFixed(2)}s'),
                          _buildMetricChip('Cycle', '${log.totalCycleSeconds.toStringAsFixed(2)}s'),
                          _buildMetricChip('Boundary', log.boundaryType.name),
                          if (log.userAction != 'none')
                            _buildMetricChip('Action', log.userAction, color: Colors.purple),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildMetricChip(String label, String value, {Color? color}) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label: ', style: const TextStyle(fontSize: 11, color: Colors.black54)),
          TextSpan(
            text: value,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color ?? Colors.black87),
          ),
        ],
      ),
    );
  }
}
