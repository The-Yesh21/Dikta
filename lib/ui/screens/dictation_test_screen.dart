import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/gnani_config.dart';
import '../../config/pacing_config.dart';
import '../../core/chunker/chunk_info.dart';
import '../../core/chunker/text_chunker.dart';
import '../../core/document/document_item.dart';
import '../../core/document/pdf_document_parser.dart';
import '../../core/pacing/pacing_engine.dart';
import '../../core/spelling/word_speller.dart';
import '../../services/audio/dictation_playback_controller.dart';
import '../../services/storage/user_pacing_storage.dart';
import '../../services/tts/gnani_tts_engine.dart';
import '../theme/dikta_theme.dart';
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
  final AudioPlayer _spellingPlayer = AudioPlayer();
  DictationPlaybackController? _playbackController;

  bool _isEngineReady = false;
  String _statusMessage = 'Connecting Gnani Cloud...';

  // Subscriptions
  StreamSubscription<DictationPlaybackState>? _stateSub;
  StreamSubscription<DictationSessionLog>? _logSub;
  StreamSubscription<Duration>? _gapSub;
  StreamSubscription<String?>? _errorSub;

  // Dedicated ValueNotifiers for jitter-free, 120fps smooth gap timer animation
  final ValueNotifier<double> _gapProgressNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<Duration> _gapRemainingNotifier = ValueNotifier<Duration>(Duration.zero);

  bool _isParsingPdf = false;
  bool _isLogsExpanded = false;
  bool _spellDifficultWords = true;
  bool _isPdfMode = false;
  String? _loadedPdfFileName;
  List<DocumentItem> _parsedDocumentItems = [];
  final ScrollController _pdfScrollController = ScrollController();

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

    // Apply writer-friendly defaults: slow speech rate for dictation, tight gaps (max 6s)
    _pacingEngine.gnaniSpeechRate = 0.80; // Slower clear speech for dictation
    _pacingEngine.maxGapSeconds = 6.0;    // Human gap between phrases (never 30-50s)
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
      spellDifficultWords: _spellDifficultWords,
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
        if (_isPdfMode && _parsedDocumentItems.isNotEmpty) {
          _autoScrollPdfViewer();
        }
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
    _gapProgressNotifier.dispose();
    _gapRemainingNotifier.dispose();
    _playbackController?.dispose();
    _spellingPlayer.dispose();
    _ttsEngine.dispose();
    _textController.dispose();
    _pdfScrollController.dispose();
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
      if (newLang == 'kn-IN' && _currentVoice != 'Saanvi' && _currentVoice != 'Kavin') {
        _currentVoice = 'Saanvi';
      } else if (!voices.any((v) => v.name == _currentVoice)) {
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
    HapticFeedback.lightImpact();
    if (_logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: DiktaColors.burgundyPrimary,
          content: Text('No session logs to copy yet.', style: TextStyle(color: DiktaColors.goldLight)),
        ),
      );
      return;
    }

    final table = DictationSessionLog.formatSessionTableMarkdown(_logs.reversed.toList());
    Clipboard.setData(ClipboardData(text: table));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: DiktaColors.burgundyPrimary,
        content: Text('Copied ${_logs.length} chunk log rows (Markdown)!', style: const TextStyle(color: DiktaColors.goldLight)),
      ),
    );
  }

  Future<void> _speakSingleSpelling(String word) async {
    HapticFeedback.lightImpact();
    final speller = _playbackController?.wordSpeller ?? const WordSpeller();
    final spoken = speller.formatSpellingForSpeech(word);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: DiktaColors.burgundyPrimary,
        content: Text('Spelling: $word (${speller.formatSpellingForDisplay(word)})', style: const TextStyle(color: DiktaColors.goldLight)),
        duration: const Duration(milliseconds: 2000),
      ),
    );
    try {
      final audio = await _ttsEngine.synthesize(
        spoken,
        voice: _currentVoice,
        language: _currentLanguage,
        speed: _pacingEngine.gnaniSpeechRate,
      );
      if (audio.audioFilePath != null) {
        await _spellingPlayer.play(DeviceFileSource(audio.audioFilePath!));
      }
    } catch (_) {}
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

  Future<void> _handleUploadPdf() async {
    HapticFeedback.lightImpact();

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      setState(() => _isParsingPdf = true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: DiktaColors.burgundyPrimary,
            content: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: DiktaColors.goldBright,
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  'Reading and analyzing PDF note structure...',
                  style: TextStyle(color: DiktaColors.goldLight),
                ),
              ],
            ),
            duration: Duration(milliseconds: 1500),
          ),
        );
      }

      final file = result.files.first;
      List<DocumentItem> items = [];

      if (file.bytes != null && file.bytes!.isNotEmpty) {
        items = PdfDocumentParser.parseBytes(file.bytes!);
      }
      if (items.isEmpty && file.path != null && file.path!.isNotEmpty) {
        items = await PdfDocumentParser.parseFile(file.path!);
      }

      if (items.isEmpty) {
        if (mounted) {
          setState(() => _isParsingPdf = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: DiktaColors.crimsonAccent,
              content: Text(
                'No readable text or notes found in the selected PDF.',
                style: TextStyle(color: Colors.white),
              ),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Automatically detect if content is predominantly Kannada, Hindi, or English
      final detectedLangCode = PdfDocumentParser.detectLanguage(items);
      final targetLang = detectedLangCode == 'kn'
          ? 'kn-IN'
          : (detectedLangCode == 'hi' ? 'hi-IN' : 'en-IN');

      // Load structured text with heading and diagram markers
      final structuredText = items
          .map((item) => item.spokenText.trim())
          .where((text) => text.isNotEmpty)
          .join('\n\n');

      // Stop any existing playback
      if (_playbackState == DictationPlaybackState.playingChunk ||
          _playbackState == DictationPlaybackState.waitingGap ||
          _playbackState == DictationPlaybackState.paused) {
        await _playbackController?.stop();
      }

      if (!mounted) return;

      setState(() {
        _isParsingPdf = false;
        _isPdfMode = true;
        _loadedPdfFileName = file.name;
        _parsedDocumentItems = items;
        _textController.text = structuredText;
        _currentLanguage = targetLang;

        final voices = GnaniVoiceCatalog.getVoicesForLanguage(targetLang);
        if (targetLang == 'kn-IN') {
          _currentVoice = 'Saanvi';
        } else if (targetLang == 'hi-IN') {
          _currentVoice = voices.isNotEmpty ? voices.first.name : 'Naveen';
        } else {
          _currentVoice = voices.isNotEmpty ? voices.first.name : 'Shivani';
        }

        _playbackController?.voice = _currentVoice;
        _playbackController?.language = _currentLanguage;

        // Reset chunker and playback state for the new document
        final chunker = TextChunker(config: PacingConfig.defaultConfig);
        final chunks = chunker.chunk(structuredText);
        _totalChunks = chunks.length;
        _currentChunkIndex = 0;
        _currentChunk = chunks.isNotEmpty ? chunks.first : null;
        _logs.clear();
        _errorMessage = null;
      });

      final headingCount = items.where((it) => it.itemType == DocumentItemType.heading).length;
      final diagramCount = items.where((it) => it.itemType == DocumentItemType.diagramPlaceholder).length;
      final langLabel = targetLang == 'kn-IN' ? 'Kannada' : 'English';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: DiktaColors.burgundyPrimary,
            content: Text(
              'PDF loaded ($langLabel): $headingCount headings, $diagramCount diagrams. Starting dictation...',
              style: const TextStyle(color: DiktaColors.goldLight),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // Automatically begin dictation immediately as requested
      await _startPlayback();
    } catch (e) {
      if (mounted) {
        setState(() => _isParsingPdf = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: DiktaColors.crimsonAccent,
            content: Text('Error parsing PDF: $e', style: const TextStyle(color: Colors.white)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DiktaColors.parchmentBackground,
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
                color: DiktaColors.burgundyPrimary,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'Handwriting Dictation Companion',
              style: TextStyle(
                fontSize: 11,
                color: DiktaColors.inkSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        backgroundColor: DiktaColors.cardSurface,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: DiktaColors.goldBorder,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note, color: DiktaColors.goldDark),
            tooltip: 'Calibrate Handwriting Speed',
            onPressed: _openCalibrationScreen,
          ),
          IconButton(
            icon: const Icon(Icons.tune, color: DiktaColors.goldDark),
            tooltip: 'Live Tuning Panel',
            onPressed: _openLiveTuningPanel,
          ),
          IconButton(
            icon: const Icon(Icons.record_voice_over_outlined, color: DiktaColors.goldDark),
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
          if (_errorMessage != null) _buildErrorBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              children: [
                if (_isPdfMode && _parsedDocumentItems.isNotEmpty) ...[
                  _buildPdfDocumentViewerCard(),
                  const SizedBox(height: 16),
                ],
                _buildActiveDictationCard(),
                const SizedBox(height: 12),
                _buildQuickPacingSettingsBar(),
                const SizedBox(height: 16),
                _buildControlsSection(),
                const SizedBox(height: 16),
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

  bool _isItemBeingSpoken(DocumentItem item) {
    if (_currentChunk == null) return false;
    final chunkText = _currentChunk!.text.trim().toLowerCase();
    if (chunkText.isEmpty) return false;

    final itemText = item.text.trim().toLowerCase();
    final spokenText = item.spokenText.trim().toLowerCase();

    if (itemText.isNotEmpty) {
      if (itemText == chunkText) return true;
      if (itemText.length >= 12 && chunkText.contains(itemText)) return true;
      if (chunkText.length >= 12 && itemText.contains(chunkText)) return true;
    }
    if (spokenText.isNotEmpty) {
      if (spokenText == chunkText) return true;
      if (spokenText.length >= 12 && chunkText.contains(spokenText)) return true;
      if (chunkText.length >= 12 && spokenText.contains(chunkText)) return true;
    }
    return false;
  }

  void _autoScrollPdfViewer() {
    if (!_pdfScrollController.hasClients) return;
    if (!_pdfScrollController.position.hasContentDimensions) return;
    if (_parsedDocumentItems.isEmpty) return;
    final activeIndex = _parsedDocumentItems.indexWhere(_isItemBeingSpoken);
    if (activeIndex != -1) {
      final targetOffset = (activeIndex * 68.0).clamp(0.0, _pdfScrollController.position.maxScrollExtent);
      _pdfScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Interactive In-App PDF Document Viewer with Live Dictation Highlighting
  Widget _buildPdfDocumentViewerCard() {
    return Container(
      decoration: BoxDecoration(
        color: DiktaColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DiktaColors.goldBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: DiktaColors.burgundyDeep.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: PDF Document Name, Page Counter, Close/Toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: DiktaColors.goldParchment,
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(
                bottom: BorderSide(color: DiktaColors.goldBorder),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: DiktaColors.burgundyPrimary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf,
                    size: 15,
                    color: DiktaColors.goldLight,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _loadedPdfFileName ?? 'PDF Notes Document',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: DiktaColors.burgundyPrimary,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${_parsedDocumentItems.length} parsed items · Auto-highlighting live speech',
                        style: const TextStyle(
                          fontSize: 10,
                          color: DiktaColors.inkSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _isPdfMode = false;
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: DiktaColors.goldBorder),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close, size: 12, color: DiktaColors.inkSecondary),
                        SizedBox(width: 4),
                        Text(
                          'Exit PDF',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: DiktaColors.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Scrollable In-App Document Sheet with Live Highlighting
          Container(
            constraints: const BoxConstraints(maxHeight: 280),
            child: Scrollbar(
              controller: _pdfScrollController,
              thumbVisibility: true,
              child: ListView.separated(
                controller: _pdfScrollController,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                itemCount: _parsedDocumentItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = _parsedDocumentItems[index];
                  final isSpeaking = _isItemBeingSpoken(item);

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSpeaking
                          ? DiktaColors.goldLight.withOpacity(0.5)
                          : (item.isHeading ? DiktaColors.goldParchment.withOpacity(0.4) : Colors.white),
                      borderRadius: BorderRadius.circular(8),
                      border: Border(
                        left: BorderSide(
                          color: isSpeaking
                              ? DiktaColors.burgundyPrimary
                              : (item.isHeading ? DiktaColors.goldAntique : Colors.transparent),
                          width: isSpeaking ? 4.0 : (item.isHeading ? 3.0 : 0.0),
                        ),
                        top: BorderSide(color: isSpeaking ? DiktaColors.goldBorder : DiktaColors.borderHairline.withOpacity(0.5)),
                        right: BorderSide(color: isSpeaking ? DiktaColors.goldBorder : DiktaColors.borderHairline.withOpacity(0.5)),
                        bottom: BorderSide(color: isSpeaking ? DiktaColors.goldBorder : DiktaColors.borderHairline.withOpacity(0.5)),
                      ),
                      boxShadow: isSpeaking
                          ? [
                              BoxShadow(
                                color: DiktaColors.goldAntique.withOpacity(0.18),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isSpeaking) ...[
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: DiktaColors.burgundyPrimary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.volume_up, size: 10, color: DiktaColors.goldLight),
                                    SizedBox(width: 4),
                                    Text(
                                      'DICTATING NOW',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.6,
                                        color: DiktaColors.goldLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              if (item.pageNumber != null)
                                Text(
                                  'Page ${item.pageNumber}',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: DiktaColors.burgundyPrimary),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                        ],

                        // Heading, Paragraph, or Diagram rendering
                        if (item.isHeading) ...[
                          Text(
                            item.text,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'serif',
                              color: isSpeaking ? DiktaColors.burgundyPrimary : DiktaColors.inkPrimary,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ] else if (item.isDiagramPlaceholder) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: DiktaColors.goldLight.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: DiktaColors.goldBorder.withOpacity(0.6)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.draw_outlined, size: 16, color: DiktaColors.burgundyPrimary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.spokenText,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                      fontWeight: FontWeight.w600,
                                      color: DiktaColors.burgundyPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          Text(
                            item.text,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              fontFamily: 'serif',
                              fontWeight: isSpeaking ? FontWeight.w600 : FontWeight.w400,
                              color: isSpeaking ? DiktaColors.burgundyPrimary : DiktaColors.inkPrimary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
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
        color: DiktaColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DiktaColors.goldBorder.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
            color: DiktaColors.burgundyDeep.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Notebook Ruled Left Margin: Burgundy leather band + Antique gold ruler hairline
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    color: isGap
                        ? DiktaColors.goldAntique
                        : isPlaying
                            ? DiktaColors.burgundyPrimary
                            : DiktaColors.burgundyMedium.withOpacity(0.4),
                  ),
                  Container(
                    width: 1.5,
                    color: DiktaColors.goldBorder,
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Card Header: Progress
                      Text(
                        _totalChunks > 0
                            ? 'PHRASE ${_currentChunkIndex + 1} OF $_totalChunks'
                            : 'DICTATION READY',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: DiktaColors.goldDark,
                        ),
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
                            color: _currentChunk != null ? DiktaColors.inkPrimary : DiktaColors.inkMuted,
                            fontFamily: 'serif',
                          ),
                        ),
                      ),

                      // Catchy Difficult Word Spelling Badges
                      if (_currentChunk != null && _spellDifficultWords) ...[
                        Builder(
                          builder: (context) {
                            final speller = _playbackController?.wordSpeller ?? const WordSpeller();
                            final diffWords = speller.findDifficultWords(_currentChunk!.text);
                            if (diffWords.isEmpty) return const SizedBox.shrink();
                            return Container(
                              margin: const EdgeInsets.only(top: 14),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: DiktaColors.goldParchment,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: DiktaColors.goldBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.spellcheck, size: 14, color: DiktaColors.burgundyPrimary),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'DIFFICULT WORDS SPELLED OUT',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.8,
                                          color: DiktaColors.burgundyPrimary,
                                        ),
                                      ),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: DiktaColors.goldLight,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: DiktaColors.goldBorder.withOpacity(0.5)),
                                        ),
                                        child: Text(
                                          '${diffWords.length} ${diffWords.length == 1 ? 'word' : 'words'}',
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: DiktaColors.burgundyPrimary),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  ...diffWords.map((word) {
                                    final displaySpelling = speller.formatSpellingForDisplay(word);
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: DiktaColors.goldBorder.withOpacity(0.8)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: DiktaColors.goldAntique.withOpacity(0.06),
                                            blurRadius: 3,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  word,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                    color: DiktaColors.inkPrimary,
                                                    fontFamily: 'serif',
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              InkWell(
                                                onTap: () => _speakSingleSpelling(word),
                                                borderRadius: BorderRadius.circular(6),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: DiktaColors.goldLight.withOpacity(0.4),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: DiktaColors.goldBorder.withOpacity(0.6)),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.volume_up_rounded, size: 13, color: DiktaColors.burgundyPrimary),
                                                      SizedBox(width: 4),
                                                      Text(
                                                        'Pronounce',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.w700,
                                                          color: DiktaColors.burgundyPrimary,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: DiktaColors.parchmentBackground,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: DiktaColors.goldBorder.withOpacity(0.4)),
                                            ),
                                            child: Text(
                                              displaySpelling,
                                              softWrap: true,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontFamily: 'monospace',
                                                fontWeight: FontWeight.w700,
                                                color: DiktaColors.burgundyPrimary,
                                                letterSpacing: 0.5,
                                                height: 1.35,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 18),

                      // Writing Countdown & Instant Advance Moment (Smooth, Jitter-Free)
                      if (isGap) ...[
                        _SmoothGapCountdown(
                          progressNotifier: _gapProgressNotifier,
                          remainingNotifier: _gapRemainingNotifier,
                          onDone: () {
                            HapticFeedback.lightImpact();
                            _playbackController?.skipGap();
                          },
                        ),
                      ] else if (isPlaying) ...[
                        Row(
                          children: [
                            const _CatchyAudioVisualizer(),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Speaking phrase at ${_pacingEngine.gnaniSpeechRate.toStringAsFixed(2)}x dictation cadence...',
                                style: const TextStyle(fontSize: 12, color: DiktaColors.burgundyPrimary, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ] else if (isPreparing) ...[
                        const Row(
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2, color: DiktaColors.goldAntique),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Synthesizing next phrase via Gnani...',
                              style: TextStyle(fontSize: 12, color: DiktaColors.inkSecondary, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ] else if (isPaused) ...[
                        const Text(
                          'Playback paused',
                          style: TextStyle(fontSize: 12, color: DiktaColors.goldDark, fontWeight: FontWeight.w600),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: DiktaColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DiktaColors.borderHairline),
      ),
      child: Column(
        children: [
          // Speech Speed Row (Burgundy pills)
          Row(
            children: [
              const Icon(Icons.record_voice_over, size: 14, color: DiktaColors.goldDark),
              const SizedBox(width: 6),
              const Text('Voice Speed:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: DiktaColors.inkSecondary)),
              const Spacer(),
              _buildSpeedPill(0.80, '0.80x (Slow)'),
              const SizedBox(width: 6),
              _buildSpeedPill(0.85, '0.85x'),
              const SizedBox(width: 6),
              _buildSpeedPill(0.92, '0.92x'),
              const SizedBox(width: 6),
              _buildSpeedPill(1.00, '1.00x'),
            ],
          ),
          const Divider(height: 16, color: DiktaColors.borderHairline),
          // Gap Pause Length Row (Gold pills)
          Row(
            children: [
              const Icon(Icons.hourglass_bottom, size: 14, color: DiktaColors.goldDark),
              const SizedBox(width: 6),
              const Text('Pause Between Parts:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: DiktaColors.inkSecondary)),
              const Spacer(),
              _buildGapPill(4.0, 'Tight (4s)'),
              const SizedBox(width: 6),
              _buildGapPill(6.0, 'Normal (6s)'),
              const SizedBox(width: 6),
              _buildGapPill(8.0, 'Relaxed (8s)'),
            ],
          ),
          const Divider(height: 16, color: DiktaColors.borderHairline),
          // Difficult Words Spelling Toggle
          Row(
            children: [
              const Icon(Icons.spellcheck, size: 14, color: DiktaColors.burgundyPrimary),
              const SizedBox(width: 6),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Spell Difficult Words',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: DiktaColors.inkPrimary),
                    ),
                    Text(
                      'Spells long words (≥10 letters) syllable-by-syllable',
                      style: TextStyle(fontSize: 10, color: DiktaColors.inkMuted),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _spellDifficultWords,
                activeColor: DiktaColors.burgundyPrimary,
                activeTrackColor: DiktaColors.goldLight,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (val) {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _spellDifficultWords = val;
                    _playbackController?.spellDifficultWords = val;
                  });
                },
              ),
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
        HapticFeedback.lightImpact();
        setState(() {
          _pacingEngine.gnaniSpeechRate = rate;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? DiktaColors.burgundyPrimary : DiktaColors.parchmentBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? DiktaColors.burgundyPrimary : DiktaColors.borderHairline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: isSelected ? DiktaColors.goldLight : DiktaColors.inkSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildGapPill(double maxGap, String label) {
    final isSelected = (_pacingEngine.maxGapSeconds - maxGap).abs() < 0.5;
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          _pacingEngine.maxGapSeconds = maxGap;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? DiktaColors.goldAntique : DiktaColors.parchmentBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? DiktaColors.goldDark : DiktaColors.borderHairline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : DiktaColors.inkSecondary,
          ),
        ),
      ),
    );
  }

  /// Quiet, tactile dictation controls with velvet burgundy and antique gold styling
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
                icon: const Icon(Icons.replay_10, size: 22, color: DiktaColors.burgundyPrimary),
                tooltip: 'Rewind to previous chunk',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _playbackController?.previousChunk();
                },
                style: IconButton.styleFrom(
                  side: const BorderSide(color: DiktaColors.goldBorder),
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(width: 16),
            ],

            // Big Center Play/Pause Capsule: Velvet Burgundy with Glowing Antique Gold Icon & Text
            FilledButton.icon(
              icon: Icon(
                isPlaying || isGap
                    ? Icons.pause
                    : isPaused
                        ? Icons.play_arrow
                        : Icons.play_arrow,
                size: 26,
                color: DiktaColors.goldBright,
              ),
              label: Text(
                isPlaying || isGap
                    ? 'Pause'
                    : isPaused
                        ? 'Resume'
                        : 'Start Dictation',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: DiktaColors.goldLight,
                  letterSpacing: 0.3,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: DiktaColors.burgundyPrimary,
                foregroundColor: DiktaColors.goldLight,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                elevation: 3,
                shadowColor: DiktaColors.burgundyDeep.withOpacity(0.4),
              ),
              onPressed: (isPreparing || !_isEngineReady)
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
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
                icon: const Icon(Icons.stop, color: DiktaColors.crimsonAccent, size: 22),
                tooltip: 'Stop Dictation',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _playbackController?.stop();
                },
                style: IconButton.styleFrom(
                  side: BorderSide(color: DiktaColors.crimsonAccent.withOpacity(0.4)),
                  backgroundColor: DiktaColors.burgundySoft,
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
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _playbackController?.repeatCurrentChunk();
                },
              ),
              const SizedBox(width: 8),
              _buildTactilePillButton(
                icon: Icons.remove,
                label: 'Slower',
                tooltip: 'Lower writing speed (gives more gap time)',
                onPressed: () {
                  HapticFeedback.lightImpact();
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
                  HapticFeedback.lightImpact();
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
      icon: Icon(icon, size: 15, color: DiktaColors.burgundyPrimary),
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: DiktaColors.inkPrimary)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: DiktaColors.goldBorder),
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

  /// Clean Language, Voice, and Note Input Sheet
  Widget _buildLanguageAndNoteSection() {
    final voices = GnaniVoiceCatalog.getVoicesForLanguage(_currentLanguage);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DiktaColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DiktaColors.borderHairline),
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
              const Text('Voice:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: DiktaColors.inkSecondary)),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: DiktaColors.goldBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: voices.any((v) => v.name == _currentVoice) ? _currentVoice : voices.first.name,
                      isExpanded: true,
                      style: const TextStyle(fontSize: 13, color: DiktaColors.inkPrimary, fontWeight: FontWeight.w600),
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
                    label: Text(
                      sample['title']!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? DiktaColors.burgundyPrimary : DiktaColors.inkSecondary,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: DiktaColors.goldLight,
                    backgroundColor: DiktaColors.parchmentBackground,
                    side: BorderSide(color: isSelected ? DiktaColors.burgundyPrimary : DiktaColors.borderHairline),
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

          // Upload PDF Notes Button (Burgundy & Antique Gold)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _isParsingPdf
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(DiktaColors.goldLight),
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf, color: DiktaColors.goldBright, size: 18),
              label: Text(
                _isParsingPdf ? 'Parsing PDF Document...' : 'Upload PDF Notes',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: DiktaColors.goldLight,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: DiktaColors.burgundyPrimary,
                foregroundColor: DiktaColors.goldLight,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: DiktaColors.goldAntique, width: 1.2),
                ),
                elevation: 1,
                shadowColor: DiktaColors.burgundyDeep.withOpacity(0.3),
              ),
              onPressed: _isParsingPdf ? null : _handleUploadPdf,
            ),
          ),
          const SizedBox(height: 12),

          // Note Text Input Area
          TextField(
            controller: _textController,
            maxLines: 5,
            style: const TextStyle(fontSize: 14, height: 1.5, color: DiktaColors.inkPrimary),
            decoration: InputDecoration(
              hintText: 'Paste or type notes to dictate...',
              hintStyle: const TextStyle(color: DiktaColors.inkMuted),
              filled: true,
              fillColor: DiktaColors.parchmentBackground,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: DiktaColors.borderHairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: DiktaColors.borderHairline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: DiktaColors.burgundyPrimary, width: 1.5),
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
            color: isSelected ? DiktaColors.burgundyPrimary : DiktaColors.goldParchment,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? DiktaColors.burgundyPrimary : DiktaColors.borderHairline,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? DiktaColors.goldLight : DiktaColors.inkSecondary,
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
        color: DiktaColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DiktaColors.borderHairline),
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(
              'Session Audit Log (${_logs.length} phrases)',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: DiktaColors.burgundyPrimary),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_logs.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16, color: DiktaColors.goldDark),
                    tooltip: 'Copy Markdown Table',
                    onPressed: _copySessionLogsToClipboard,
                  ),
                Icon(
                  _isLogsExpanded ? Icons.expand_less : Icons.expand_more,
                  color: DiktaColors.goldDark,
                ),
              ],
            ),
            onTap: () => setState(() => _isLogsExpanded = !_isLogsExpanded),
          ),
          if (_isLogsExpanded) ...[
            const Divider(height: 1, color: DiktaColors.borderHairline),
            if (_logs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No phrases dictated yet in this session.', style: TextStyle(fontSize: 12, color: DiktaColors.inkMuted)),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _logs.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: DiktaColors.borderHairline),
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: log.isFromCache ? DiktaColors.goldLight : DiktaColors.burgundySoft,
                          child: Text(
                            '${log.chunkIndex + 1}',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: log.isFromCache ? DiktaColors.goldDark : DiktaColors.burgundyPrimary,
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
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: DiktaColors.inkPrimary),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${log.graphemes} letters · Speech: ${log.speechDurationSeconds.toStringAsFixed(1)}s · Gap: ${log.gapSeconds.toStringAsFixed(1)}s · ${log.isFromCache ? '⚡ Cache' : '☁️ API'}',
                                style: const TextStyle(fontSize: 10, color: DiktaColors.inkSecondary),
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
      color: DiktaColors.burgundySoft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: DiktaColors.crimsonAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage ?? 'An error occurred',
              style: const TextStyle(fontSize: 12, color: DiktaColors.burgundyPrimary, fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            onPressed: () => _playbackController?.retryCurrentChunk(),
            child: const Text('Retry', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: DiktaColors.crimsonAccent)),
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
        color: DiktaColors.goldParchment,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DiktaColors.goldBorder),
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
                      backgroundColor: DiktaColors.goldLight,
                      color: DiktaColors.goldAntique,
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
                        color: DiktaColors.burgundyPrimary,
                      ),
                    ),
                    const Text(
                      'Tap "Done" when finished to advance faster',
                      style: TextStyle(fontSize: 11, color: DiktaColors.inkSecondary),
                    ),
                  ],
                );
              },
            ),
          ),
          FilledButton(
            onPressed: onDone,
            style: FilledButton.styleFrom(
              backgroundColor: DiktaColors.burgundyPrimary,
              foregroundColor: DiktaColors.goldLight,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: DiktaColors.goldLight)),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward, size: 14, color: DiktaColors.goldBright),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Catchy, Smooth Audio Equalizer Bars animation for active speech playback.
/// Styled in gilded antique gold gradients.
class _CatchyAudioVisualizer extends StatefulWidget {
  const _CatchyAudioVisualizer();

  @override
  State<_CatchyAudioVisualizer> createState() => _CatchyAudioVisualizerState();
}

class _CatchyAudioVisualizerState extends State<_CatchyAudioVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final heights = [
          7.0 + 10.0 * t,
          15.0 - 8.0 * t,
          9.0 + 12.0 * ((t + 0.4) % 1.0),
          16.0 - 10.0 * ((t + 0.2) % 1.0),
          10.0 + 7.0 * ((t + 0.7) % 1.0),
        ];

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(5, (index) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3.2,
              height: heights[index].clamp(5.0, 18.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: const LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [DiktaColors.goldDark, DiktaColors.goldBright],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
